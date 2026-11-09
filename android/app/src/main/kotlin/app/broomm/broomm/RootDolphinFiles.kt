package app.broomm.broomm

import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import java.io.DataInputStream
import java.io.File
import java.io.FileInputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer

internal const val DOLPHIN_PACKAGE = "org.dolphinemu.dolphinemu"
internal const val DOLPHIN_SIGNER = "8e7556d64ce8f7f15e36c4b3380aab0e326431146f9b26d2adee35326951fcab"
internal const val DOLPHIN_VERSION = "2609a"

private const val DOLPHIN_STATE_BYTES = 64 * 1024 * 1024
private const val DOLPHIN_WII_BYTES = 32 * 1024 * 1024
private const val DOLPHIN_GCI_BYTES = 17 * 1024 * 1024
private val dolphinUndoFiles = setOf(
    "files/StateSaves/lastState.sav",
    "files/StateSaves/lastState.sav.dtm",
    "files/StateSaves/undo.dtm",
)

/** The official app's default GCI slots, Wii disc save data and numbered states. */
internal class RootDolphinFiles(identity: Map<String, Any>, private val live: () -> Unit) {
    private val uid = identity.getValue("uid") as Int
    private val internal = File(identity.getValue("dataDir") as String).canonicalFile
    private val internalLabel = Os.getxattr(internal.path, "security.selinux")
    private val label = String(internalLabel).replace("app_data_file:", "media_rw_data_file:").toByteArray()
    private val root = File("/data/media/0/Android/data/$DOLPHIN_PACKAGE")
    private val logical = File("/storage/emulated/0/Android/data/$DOLPHIN_PACKAGE")
    private val first = Os.lstat(root.path)
    private val files = RootSaveFiles(root, uid, label, live, writerClosed = ::closed, mediaGroup = 1078)
    private val privateFiles = RootSaveFiles(internal, uid, internalLabel, live)

    init {
        require(identity["package"] == DOLPHIN_PACKAGE && identity["user"] == 0 &&
            identity["version"] == DOLPHIN_VERSION && identity["signer"] == DOLPHIN_SIGNER)
        verifyMount()
    }

    private fun closed() = requireNoEmulatorProcess(uid, "Dolphin", live)

    private fun sameDirectory(a: StructStat, b: StructStat): Boolean =
        a.st_dev == b.st_dev && a.st_ino == b.st_ino && a.st_mode == b.st_mode &&
            a.st_uid == b.st_uid && a.st_gid == b.st_gid

    private fun verifyDirectory(file: File, stat: StructStat) {
        require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == uid && stat.st_gid == 1078 &&
            stat.st_dev == first.st_dev && (stat.st_mode and 4095) == 1528 &&
            Os.getxattr(file.path, "security.selinux").contentEquals(label)) {
            "Dolphin storage ownership or security label changed. Recovery was kept."
        }
    }

    private fun verifyMount() {
        live()
        require(root.canonicalPath == root.path && logical.canonicalPath == logical.path &&
            sameDirectory(first, Os.lstat(root.path)) && sameDirectory(first, Os.lstat(logical.path))) {
            "Dolphin storage mount changed. Recovery was kept."
        }
        verifyDirectory(root, first)
        verifyDirectory(logical, first)
    }

    private fun path(relative: String): File {
        verifyMount()
        val file = files.path(relative)
        var parent = file.parentFile!!
        while (parent != root) {
            if (files.present(parent)) verifyDirectory(parent, Os.lstat(parent.path))
            parent = parent.parentFile!!
        }
        return file
    }

    private fun configuration(relative: String, private: Boolean = false): Map<String, String>? {
        val access = if (private) privateFiles else files
        val file = if (private) access.path(relative) else path(relative)
        if (!access.present(file)) return null
        access.existing(relative)
        val bytes = access.bytes(file, 256 * 1024)
        val config = mutableMapOf<String, String>()
        var section = ""
        for (line in bytes.toString(Charsets.UTF_8).removePrefix("\uFEFF").lineSequence()) {
            val text = line.trim()
            if (text.startsWith('[') && text.endsWith(']')) {
                section = text.substring(1, text.length - 1).trim().lowercase()
                continue
            }
            if (text.startsWith('#') || text.startsWith(';') || '=' !in text) continue
            val key = text.substringBefore('=').trim().lowercase()
            if (key !in SAVE_SETTINGS) continue
            val value = text.substringAfter('=').trim().removeSurrounding("\"")
            val name = "$section/$key"
            require(config.put(name, value)?.let { it == value } != false) {
                "Dolphin has conflicting save settings."
            }
        }
        return config
    }

    private fun requireDefaults(config: Map<String, String>, platform: String, game: Boolean) {
        for ((name, value) in config) {
            val key = name.substringAfter('/')
            val valid = when {
                platform == "ngc" && key == "slota" -> value == "8"
                platform == "ngc" && key == "slotb" -> value in setOf("8", "255")
                platform == "ngc" && key in GC_PATHS -> value.isEmpty()
                platform == "ngc" && key == "overrideregionsettings" ->
                    value.equals("false", ignoreCase = true) || value == "0"
                platform == "wii" && key == "nandrootpath" -> value.isEmpty()
                else -> true
            }
            require(valid) {
                if (game) "Dolphin has a save setting override for this game. Use its default save paths."
                else if (platform == "ngc") "Set Dolphin Slot A to GCI Folder and Slot B to GCI Folder or None, with the default card paths."
                else "Dolphin’s Wii NAND must use its default user-data path."
            }
        }
    }

    fun report(platform: String): Bundle {
        require(platform == "ngc" || platform == "wii")
        closed()
        val config = configuration("files/Config/Dolphin.ini")
            ?: error("Open Dolphin once, close it and retry Setup.")
        requireDefaults(config, platform, false)
        verifyMount()
        closed()
        return Bundle().apply {
            putString("label", String(internalLabel).trimEnd('\u0000'))
            putString("externalLabel", String(label).trimEnd('\u0000'))
            putString("externalGid", "1078")
            putString("externalDevice", first.st_dev.toString())
            putString("externalInode", first.st_ino.toString())
        }
    }

    private fun children(relative: String, limit: Int): List<File> {
        val directory = path(relative)
        if (!files.present(directory)) return emptyList()
        verifyDirectory(directory, Os.lstat(directory.path))
        val entries = directory.listFiles() ?: error("Cannot inspect Dolphin’s save directory.")
        require(entries.size <= limit) { "Dolphin’s save directory exceeds the supported file count." }
        return entries.sortedBy { it.name }
    }

    private fun scope(platform: String, disc: DolphinDisc): DolphinScope {
        val id = disc.id
        val iniNames = listOf(id.take(1), id.take(3), id, "${id}r${disc.revision}")
        for (name in iniNames) {
            for (config in listOfNotNull(
                configuration("files/GameSettings/$name.ini"),
                configuration("files/Sys/GameSettings/$name.ini", private = true),
            )) requireDefaults(config, platform, true)
        }
        val data = if (platform == "wii") {
            "files/Wii/title/00010000/" + id.take(4).toByteArray(Charsets.US_ASCII)
                .joinToString("") { "%02x".format(it.toInt()) } + "/data"
        } else {
            val region = when (id[3]) {
                'E' -> "USA"
                'J' -> "JAP"
                'P' -> "EUR"
                else -> error("This GameCube region needs verified Dolphin save paths.")
            }
            val raw = children("files/GC", 4096).any {
                Regex("MemoryCard[AB]\\.$region(?:\\.[0-9]+)?\\.raw", RegexOption.IGNORE_CASE).matches(it.name)
            }
            require(!raw) { "Dolphin can import an existing raw card into the GCI folder. Use shared-folder setup for this installation." }
            "files/GC/$region"
        }
        return DolphinScope(id, platform, data)
    }

    private fun entry(relative: String, limit: Int): ByteArray {
        val file = path(relative)
        val before = files.metadata(file)
        val bytes = files.bytes(file, limit)
        require(before == files.metadata(file))
        return bytes
    }

    private fun header(file: File): String {
        files.metadata(file)
        val fd = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW or OsConstants.O_NONBLOCK, 0)
        return DataInputStream(FileInputStream(fd)).use { input ->
            val bytes = ByteArray(6)
            input.readFully(bytes)
            bytes.toString(Charsets.US_ASCII)
        }
    }

    private fun candidates(scope: DolphinScope): List<String> {
        val selected = mutableListOf<String>()
        if (scope.platform == "ngc") {
            for (slot in listOf("Card A", "Card B")) {
                val dir = "${scope.data}/$slot"
                for (file in children(dir, 4096)) {
                    if (!file.name.endsWith(".gci") && !file.name.endsWith(".gci.deleted")) continue
                    if (header(path("$dir/${file.name}")) == scope.id) selected.add("$dir/${file.name}")
                }
            }
        } else {
            fun walk(dir: String, depth: Int) {
                require(depth <= 12) { "Dolphin’s Wii save tree is too deep." }
                for (file in children(dir, 128)) {
                    live()
                    if (STAGE.matches(file.name)) continue
                    val relative = "$dir/${file.name}"
                    val stat = Os.lstat(path(relative).path)
                    if (OsConstants.S_ISDIR(stat.st_mode)) walk(relative, depth + 1)
                    else {
                        require(OsConstants.S_ISREG(stat.st_mode))
                        selected.add(relative)
                        require(selected.size <= 96)
                    }
                }
            }
            walk(scope.data, 0)
        }
        for (slot in 0..10) {
            val relative = scope.state(slot)
            require(!files.present(path("$relative.dtm"))) {
                "Dolphin has a movie recording attached to a state. Use shared-folder setup."
            }
            if (files.present(path(relative))) selected.add(relative)
        }
        // Native state overwrites can replace these global files even when
        // their previous contents belonged to a different game.
        selected.addAll(dolphinUndoFiles.filter { files.present(path(it)) })
        require(selected.size <= 96 && selected.sumOf { it.toByteArray().size } <= 48 * 1024) {
            "Dolphin’s save inventory exceeds its supported limit."
        }
        return selected
    }

    private fun row(relative: String, bytes: ByteArray): Bundle = Bundle().apply {
        putLong("bytes", bytes.size.toLong())
        putString("sha256", RootSaveFiles.digest(bytes))
        putString("metadata", files.metadata(path(relative)))
    }

    fun operation(request: Bundle, game: File, caller: Int): Bundle {
        val platform = request.getString("platform")!!
        val binding = report(platform)
        require(binding.keySet().all { binding.getString(it) == request.getString(it) }) {
            "Dolphin’s installation or save storage changed. Recovery was kept."
        }
        val disc = readDolphinDisc(game, platform)
        val scope = scope(platform, disc)
        return when (request.getString("operation")) {
            "dolphincheck" -> Bundle()
            "dolphinlist" -> Bundle().apply {
                var total = 0L
                val inventory = Bundle()
                for (relative in candidates(scope)) {
                    val bytes = entry(relative, scope.limit(relative))
                    scope.validate(relative, bytes)
                    total += bytes.size
                    require(total <= 512L * 1024 * 1024)
                    inventory.putBundle(relative, row(relative, bytes))
                }
                putBundle("files", inventory)
            }
            "dolphinread" -> {
                val relative = request.getString("path")!!
                val bytes = entry(relative, scope.limit(relative))
                scope.validate(relative, bytes)
                val entry = row(relative, bytes)
                require(entry.getLong("bytes") == request.getLong("bytes") &&
                    entry.getString("sha256") == request.getString("sha256") &&
                    entry.getString("metadata") == request.getString("metadata")) {
                    "Dolphin progress changed before capture. Recovery was kept."
                }
                closed()
                RootSaveTransfer.write(request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller, bytes, live)
                Bundle()
            }
            "dolphinreplace" -> {
                val relative = request.getString("path")!!
                val limit = scope.limit(relative)
                val source = request.getParcelable<ParcelFileDescriptor>("transfer")
                val bytes = source?.let { RootSaveTransfer.read(it, caller, limit, live) }
                if (bytes != null) scope.validate(relative, bytes)
                val target = path(relative)
                if (files.present(target) && scope.hasHeader(relative)) {
                    // An interrupted exclusive publication can briefly have two
                    // links. The publisher verifies and recovers that exact link.
                    if (Os.lstat(target.path).st_nlink == 1L)
                        require(header(target) == scope.id) { "Dolphin progress belongs to another title." }
                }
                files.replaceStandalone(relative, request.getString("before"), request.getString("after"),
                    bytes, request.getString("metadata"), request.getString("token")!!, limit) {
                    val current = report(platform)
                    require(current.keySet().all { current.getString(it) == request.getString(it) })
                    require(scope(platform, disc) == scope)
                    path(relative)
                }
                Bundle()
            }
            else -> error("Unsupported Dolphin root operation.")
        }.also { verifyMount(); closed() }
    }

    private companion object {
        val GC_PATHS = setOf("gcifolderapath", "gcifolderbpath", "gcifolderapathoverride",
            "gcifolderbpathoverride", "memcardapath", "memcardbpath")
        val SAVE_SETTINGS = GC_PATHS + setOf("slota", "slotb", "nandrootpath", "overrideregionsettings")
        val STAGE = Regex("(?:\\..+\\.broomm-|\\.broomm-dir-)[a-f0-9]{32}-(?:in|out)")
    }
}

private data class DolphinScope(val id: String, val platform: String, val data: String) {
    fun state(slot: Int): String = "files/StateSaves/$id.s${slot.toString().padStart(2, '0')}"

    fun limit(path: String): Int {
        if (path in dolphinUndoFiles || (0..10).any { path == state(it) })
            return DOLPHIN_STATE_BYTES
        if (platform == "ngc") {
            val folder = path.substringBeforeLast('/')
            require(folder in setOf("$data/Card A", "$data/Card B") &&
                (path.endsWith(".gci") || path.endsWith(".gci.deleted")))
            return DOLPHIN_GCI_BYTES
        }
        require(path.startsWith("$data/") && path.length > data.length + 1)
        return DOLPHIN_WII_BYTES
    }

    fun hasHeader(path: String): Boolean =
        path !in dolphinUndoFiles && (platform == "ngc" || path.startsWith("files/StateSaves/"))

    fun validate(path: String, bytes: ByteArray) {
        if (hasHeader(path)) {
            val minimum = if (path.startsWith("files/StateSaves/")) 32 else 64
            require(bytes.size >= minimum && String(bytes, 0, 6, Charsets.US_ASCII) == id) {
                "Dolphin progress belongs to another title or has a truncated header."
            }
        }
    }
}

internal data class DolphinDisc(val id: String, val revision: Int)

internal fun readDolphinDisc(file: File, platform: String): DolphinDisc = RandomAccessFile(file, "r").use { input ->
    val bytes = ByteArray(128)
    input.readFully(bytes)
    when (ByteBuffer.wrap(bytes).getInt(0)) {
        0x52565a01, 0x57494101 -> {
            input.seek(0x58)
            input.readFully(bytes)
        }
        0x57424653 -> {
            require(platform == "wii")
            val shift = bytes[8].toInt() and 255
            val blockShift = bytes[9].toInt() and 255
            require(shift in 9..20 && blockShift in shift..26)
            val slots = ByteArray((1 shl shift) - 12)
            input.seek(12)
            input.readFully(slots)
            require(slots[0] == 1.toByte() && (1 until slots.size).all { slots[it] == 0.toByte() }) {
                "Root Dolphin supports single-disc WBFS files in slot zero."
            }
            val discInfo = 1L shl shift
            input.seek(discInfo)
            input.readFully(bytes)
            val copy = bytes.copyOf()
            input.seek(discInfo + 256)
            val firstBlock = input.readUnsignedShort()
            require(firstBlock > 0)
            input.seek(firstBlock.toLong() shl blockShift)
            input.readFully(bytes)
            require(bytes.contentEquals(copy)) { "WBFS disc headers disagree." }
        }
    }
    val header = ByteBuffer.wrap(bytes)
    require(if (platform == "ngc") header.getInt(0x1c) == 0xc2339f3d.toInt()
        else header.getInt(0x18) == 0x5d1c9ea3) { "Unsupported Dolphin disc header." }
    val id = String(bytes, 0, 6, Charsets.US_ASCII)
    require(Regex("[A-Z0-9]{6}").matches(id)) { "Invalid Dolphin disc identity." }
    DolphinDisc(id, bytes[7].toInt() and 255)
}
