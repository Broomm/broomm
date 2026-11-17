package app.broomm.broomm

import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import android.util.Xml
import org.xmlpull.v1.XmlPullParser
import java.io.File

internal const val MELON_PACKAGE = "me.magnum.melonds"
internal const val MELON_SIGNER = "0493bb8749289f0304cc868489dd68b930c19ccc4dce2da876bfe6b9bdbabebc"
internal const val MELON_VERSION = "2.0.1 GH"

internal fun requireMelonSharedFolder(internal: RootSaveFiles, expected: String) {
    val relative = "shared_prefs/${MELON_PACKAGE}_preferences.xml"
    require(!internal.present(internal.path("$relative.bak"))) { "Open melonDS once to finish recovering its settings." }
    val prefs = internal.bytes(internal.existing(relative), 256 * 1024)
    val parser = Xml.newPullParser()
    parser.setFeature(XmlPullParser.FEATURE_PROCESS_DOCDECL, false)
    parser.setInput(prefs.inputStream(), "UTF-8")
    require(parser.nextTag() == XmlPullParser.START_TAG && parser.name == "map")
    var useRomDirectory = true
    var stateLocation = "save_dir"
    val selected = mutableListOf<String>()
    val seen = mutableSetOf<String>()
    while (parser.next() != XmlPullParser.END_DOCUMENT) {
        if (parser.eventType != XmlPullParser.START_TAG || parser.depth != 2) continue
        val key = parser.getAttributeValue(null, "name") ?: continue
        if (key !in setOf("use_rom_dir", "save_state_location", "sram_dir")) continue
        require(seen.add(key))
        when (key) {
            "use_rom_dir" -> {
                require(parser.name == "boolean")
                useRomDirectory = parser.getAttributeValue(null, "value").toBooleanStrict()
            }
            "save_state_location" -> {
                require(parser.name == "string")
                stateLocation = parser.nextText()
            }
            "sram_dir" -> {
                require(parser.name == "set")
                while (parser.nextTag() == XmlPullParser.START_TAG) {
                    require(parser.name == "string" && selected.isEmpty())
                    selected.add(parser.nextText())
                }
            }
        }
    }
    val uri = selected.singleOrNull()?.let(android.net.Uri::parse)
    require(!useRomDirectory && stateLocation.equals("save_dir", ignoreCase = true) &&
        uri?.scheme == "content" && uri.authority == "com.android.externalstorage.documents" &&
        uri.pathSegments == listOf("tree", expected) && uri.query == null && uri.fragment == null) {
        "Choose Internal storage/Broomm/melonDS as the save folder in melonDS and set Save state location to Save directory."
    }
}

/** File effects for the reviewed release's default DS cartridge paths. */
internal class RootMelonFiles(
    private val identity: Map<String, Any>, private val live: () -> Unit,
) {
    private val uid = identity.getValue("uid") as Int
    private val internal = File(identity.getValue("dataDir") as String).canonicalFile
    private val internalLabel = Os.getxattr(internal.path, "security.selinux")
    private val root = File("/data/media/0/Android/data/$MELON_PACKAGE")
    private val logical = File("/storage/emulated/0/Android/data/$MELON_PACKAGE")
    private val rootLabel = Os.getxattr(root.path, "security.selinux")
    private val label = String(internalLabel).replace("app_data_file:", "media_rw_data_file:").toByteArray()
    private val first = Os.lstat(root.path)
    private val gid = first.st_gid
    private val fileAccess = RootSaveFiles(root, uid, label, live, writerClosed = ::closed, mediaGroup = gid)

    init {
        require(identity["package"] == MELON_PACKAGE && identity["user"] == 0 &&
            identity["version"] == MELON_VERSION && identity["signer"] == MELON_SIGNER)
        require(rootLabel.contentEquals(label) ||
            String(rootLabel).trimEnd('\u0000') == "u:object_r:media_rw_data_file:s0")
        verifyRoot()
    }

    private fun sameDirectory(a: StructStat, b: StructStat): Boolean =
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode &&
            a.st_uid == b.st_uid && a.st_gid == b.st_gid

    private fun verifyRoot() {
        live()
        require(root.canonicalPath == root.path && logical.canonicalPath == logical.path &&
            OsConstants.S_ISDIR(first.st_mode) && first.st_uid == uid && gid == 1078 &&
            (first.st_mode and 4095) == 1528 &&
            sameDirectory(first, Os.lstat(root.path)) && sameDirectory(first, Os.lstat(logical.path)) &&
            Os.getxattr(root.path, "security.selinux").contentEquals(rootLabel) &&
            Os.getxattr(logical.path, "security.selinux").contentEquals(rootLabel)) {
            "melonDS storage ownership or mount changed. Recovery was kept."
        }
    }

    private fun closed() = requireNoEmulatorProcess(uid, "melonDS", live)

    private fun stateDirectory(): String {
        val storage = RootSaveFiles(internal, uid, internalLabel, live)
        val relative = "shared_prefs/${MELON_PACKAGE}_preferences.xml"
        val config = storage.path(relative)
        require(!storage.present(storage.path("$relative.bak"))) {
            "melonDS settings are being recovered. Open melonDS once and close it before retrying."
        }
        require(storage.present(config)) { "Open melonDS once to initialize it, close it and retry Setup." }
        storage.existing(relative)
        val bytes = storage.bytes(config, 256 * 1024)
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_DOCDECL, false)
        parser.setInput(bytes.inputStream(), "UTF-8")
        require(parser.nextTag() == XmlPullParser.START_TAG && parser.name == "map")
        var useRomDirectory = true
        var customSaveDirectory = false
        var scansRomDirectories = false
        var customBios = false
        var console = "ds"
        var stateLocation = "save_dir"
        val seen = mutableSetOf<String>()
        while (parser.next() != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType != XmlPullParser.START_TAG || parser.depth != 2) continue
            val key = parser.getAttributeValue(null, "name") ?: continue
            if (key !in setOf("use_rom_dir", "sram_dir", "save_state_location", "rom_search_dirs", "console_type", "use_custom_bios")) continue
            require(seen.add(key)) { "Ambiguous melonDS save preferences." }
            when (key) {
                "use_rom_dir", "use_custom_bios" -> {
                    require(parser.name == "boolean")
                    val enabled = parser.getAttributeValue(null, "value").toBooleanStrict()
                    if (key == "use_rom_dir") useRomDirectory = enabled else customBios = enabled
                }
                "sram_dir", "rom_search_dirs" -> {
                    require(parser.name == "set")
                    val configured = parser.nextTag() != XmlPullParser.END_TAG
                    if (key == "sram_dir") customSaveDirectory = configured else scansRomDirectories = configured
                }
                "save_state_location", "console_type" -> {
                    require(parser.name == "string")
                    val value = parser.nextText().lowercase()
                    if (key == "save_state_location") stateLocation = value else console = value
                }
            }
        }
        require(useRomDirectory || !customSaveDirectory) {
            "melonDS uses a custom save directory. Use shared-folder setup for that directory."
        }
        val cache = "files/rom_data.json"
        // The native resolver can substitute a scanned ROM with the same name
        // and size, including its writable parent and per-game settings.
        require(!scansRomDirectories &&
            (!storage.present(storage.path(cache)) ||
                String(storage.bytes(storage.existing(cache), 256 * 1024)).trim() == "[]")) {
            "melonDS has its own ROM library. Use shared-folder setup so those native files remain separate."
        }
        require(console == "ds" && !customBios) {
            "Root melonDS currently supports standard DS mode with the built-in BIOS."
        }
        return when (stateLocation) {
            "save_dir" -> "files/saves"
            "internal_dir" -> "files/savestates"
            else -> error("Set melonDS save states to Save directory or Internal directory before root setup.")
        }
    }

    fun report(): Bundle {
        closed()
        return Bundle().apply {
            putString("label", String(internalLabel).trimEnd('\u0000'))
            // Android can relabel the package directory on first use. Bind
            // the effective file label separately from the directory check.
            putString("externalLabel", String(label).trimEnd('\u0000'))
            putString("externalGid", gid.toString())
            putString("externalDevice", first.st_dev.toString())
            putString("externalInode", first.st_ino.toString())
            putString("stateDirectory", stateDirectory())
        }.also { verifyRoot(); closed() }
    }

    private fun scope(request: Bundle): Map<String, Int> {
        val native = report()
        require(native.keySet().all { native.getString(it) == request.getString(it) }) {
            "melonDS’s installation, save preferences or storage changed. Recovery was kept."
        }
        val filename = request.getString("libraryRelative")!!.substringAfterLast('/')
        require(filename.endsWith(".nds", ignoreCase = true)) { "Root melonDS currently needs a raw .nds cartridge." }
        val stem = filename.substringBeforeLast('.')
        require(stem.isNotBlank() && stem.toByteArray().size <= 200 &&
            stem.none { it.code < 32 || it == '/' || it == '\\' })
        val states = native.getString("stateDirectory")!!
        return mapOf("files/saves/$stem.sav" to 8 * 1024 * 1024) +
            (0..8).associate { "$states/$stem.ml$it" to 32 * 1024 * 1024 }
    }

    private fun resolve(path: String): File {
        verifyRoot()
        val file = fileAccess.path(path)
        var parent = file.parentFile!!
        while (parent != root) {
            if (fileAccess.present(parent)) {
                val s = Os.lstat(parent.path)
                require(OsConstants.S_ISDIR(s.st_mode) && s.st_uid == uid && s.st_gid == gid &&
                    (s.st_mode and 3072) == 1024 && Os.getxattr(parent.path, "security.selinux").contentEquals(label))
            }
            parent = parent.parentFile!!
        }
        return file
    }

    private fun entry(path: String, max: Int): Pair<Bundle, ByteArray>? {
        val file = resolve(path)
        if (!fileAccess.present(file)) return null
        val metadata = fileAccess.metadata(file)
        val payload = fileAccess.bytes(file, max)
        require(fileAccess.metadata(file) == metadata)
        return Bundle().apply {
            putLong("bytes", payload.size.toLong())
            putString("sha256", RootSaveFiles.digest(payload))
            putString("metadata", metadata)
        } to payload
    }

    fun operation(request: Bundle, caller: Int): Bundle {
        val scope = scope(request)
        return when (request.getString("operation")) {
            "meloncheck" -> Bundle()
            "melonlist" -> Bundle().apply {
                val files = Bundle()
                for ((path, max) in scope) {
                    val (entry, _) = entry(path, max) ?: continue
                    files.putBundle(path, entry)
                }
                putBundle("files", files)
            }
            "melonread" -> {
                val path = request.getString("path")!!
                val (entry, payload) = entry(path, scope.getValue(path)) ?: error("The melonDS save is missing.")
                require(entry.getLong("bytes") == request.getLong("bytes") &&
                    entry.getString("sha256") == request.getString("sha256") &&
                    entry.getString("metadata") == request.getString("metadata")) {
                    "melonDS progress changed before capture. Recovery was kept."
                }
                closed()
                RootSaveTransfer.write(request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller, payload, live)
                Bundle()
            }
            "melonreplace" -> {
                val path = request.getString("path")!!
                val limit = scope.getValue(path)
                val source = request.getParcelable<ParcelFileDescriptor>("transfer")
                val payload = source?.let { RootSaveTransfer.read(it, caller, limit, live) }
                // The publisher verifies the file and can recover its own
                // interrupted two-link publication.
                resolve(path)
                fileAccess.replaceStandalone(path, request.getString("before"), request.getString("after"),
                    payload, request.getString("metadata"), request.getString("token")!!, limit) {
                    require(scope(request) == scope)
                    resolve(path)
                }
                Bundle()
            }
            else -> error("Unsupported melonDS root operation.")
        }.also { verifyRoot(); closed() }
    }
}
