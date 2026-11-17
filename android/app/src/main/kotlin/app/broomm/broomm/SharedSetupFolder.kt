package app.broomm.broomm

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.os.Bundle
import android.os.ParcelFileDescriptor
import java.io.File
import java.io.FileInputStream

internal fun defaultSharedSetupFolder(pkg: String?): String? = when (pkg) {
    "org.azahar_emu.azahar", "io.github.lime3ds.android" -> "Broomm/Azahar"
    "org.citra.emu", "com.antutu.ABenchMark" -> "citra-emu"
    "org.ppsspp.ppsspp", "org.ppsspp.ppssppgold" -> "Broomm/PPSSPP"
    "me.magnum.melonds" -> "Broomm/melonDS"
    "com.github.stenzek.duckstation" -> "Broomm/DuckStation"
    "com.armsx2", "com.armsx2.nightly" -> "Broomm/ARMSX2"
    else -> null
}

/** Create only a fixed primary-storage directory. Existing folders and their
 * contents are user-owned and keep their original metadata. */
internal const val ARMSX2_IMPORT_BIOS = "Broomm BIOS/broomm-ps2-bios.bin"

internal fun prepareSharedSetupFolder(pkg: String): File {
    val root = requireNotNull(defaultSharedSetupFolder(pkg))
    val directory = sharedSetupDirectory(root, create = true)
    if (pkg in setOf("org.ppsspp.ppsspp", "org.ppsspp.ppssppgold")) {
        sharedSetupDirectory("$root/PSP/SAVEDATA", create = true)
        sharedSetupDirectory("$root/PSP/PPSSPP_STATE", create = true)
    }
    if (pkg == "com.github.stenzek.duckstation") {
        sharedSetupDirectory("$root/memcards", create = true)
        sharedSetupDirectory("$root/savestates", create = true)
    }
    return directory
}

internal fun sharedSetupDirectory(path: String, create: Boolean = false): File {
    var logical = File("/storage/emulated/0")
    var physical = File("/data/media/0")
    for (name in path.split('/')) {
        require(logical.canonicalPath == logical.path && physical.canonicalPath == physical.path)
        logical = File(logical, name)
        physical = File(physical, name)
        if (create) try {
            // Use Android's emulated storage mount so the media provider assigns
            // the owner, permissions and security label as part of creation.
            Os.mkdir(logical.path, 504) // 0770
        } catch (e: ErrnoException) {
            if (e.errno != OsConstants.EEXIST) throw e
        }
        val shared = Os.lstat(logical.path)
        val backing = Os.lstat(physical.path)
        require(OsConstants.S_ISDIR(shared.st_mode) && OsConstants.S_ISDIR(backing.st_mode) &&
            shared.st_ino == backing.st_ino) {
            "Android could not verify the shared folder for $path."
        }
    }
    return physical
}

internal fun publishArmsx2ImportBios(
    payload: ByteArray, expected: String, live: () -> Unit,
    root: String = requireNotNull(defaultSharedSetupFolder(ARMSX2_PACKAGE)),
) {
    val bytes = 4 * 1024 * 1024
    val header = String(payload, 0, minOf(payload.size, 512 * 1024), Charsets.ISO_8859_1)
    require(payload.size == bytes && "ROMDIR" in header && "ROMVER" in header &&
        Regex("[a-f0-9]{64}").matches(expected) && RootSaveFiles.digest(payload) == expected) {
        "The staged PS2 BIOS failed validation."
    }
    sharedSetupDirectory("$root/memcards", create = true)
    sharedSetupDirectory("$root/sstates", create = true)
    val path = "$root/${ARMSX2_IMPORT_BIOS.substringBeforeLast('/')}"
    val directory = sharedSetupDirectory(path, create = true)
    val info = Os.lstat(directory.path)
    val label = Os.getxattr(directory.path, "security.selinux")
    val files = RootSaveFiles(directory, info.st_uid, label, live, mediaGroup = info.st_gid)
    val name = ARMSX2_IMPORT_BIOS.substringAfterLast('/')
    val target = files.path(name)
    if (files.present(target) && Os.lstat(target.path).st_nlink == 1L) {
        require(files.hash(target, bytes) == expected) {
            "The BIOS import folder already contains a different file. Existing firmware was kept."
        }
    } else {
        files.replaceStandalone(name, null, expected, payload,
            "${info.st_uid} ${info.st_gid} 664 ${String(label).trimEnd('\u0000')}", expected.take(32) + "-in", bytes) {
            val current = Os.lstat(sharedSetupDirectory(path).path)
            require(current.st_dev == info.st_dev && current.st_ino == info.st_ino) {
                "The ARMSX2 BIOS folder changed during preparation."
            }
        }
    }
    val visible = File("/storage/emulated/0/$root", ARMSX2_IMPORT_BIOS)
    require(Os.lstat(visible.path).st_ino == Os.lstat(target.path).st_ino &&
        files.hash(visible, bytes) == expected) { "Android could not verify the published BIOS." }
}

/** The root service owns only the fixed primary-storage folder. Keep the
 * ordinary save journal and checksums shared with the document-provider route. */
internal class RootPreparedFolder(
    private val root: File,
    private val recheck: () -> Unit,
    private val writerClosed: () -> Unit = {},
) {
    private val visible = File("/storage/emulated/0", root.path.removePrefix("/data/media/0/"))
    private val rootStat = Os.lstat(root.path)

    private fun live() {
        recheck()
        val current = Os.lstat(root.path)
        require(current.st_dev == rootStat.st_dev && current.st_ino == rootStat.st_ino &&
            OsConstants.S_ISDIR(current.st_mode) && visible.canonicalPath == visible.path &&
            Os.lstat(visible.path).st_ino == current.st_ino) { "The prepared emulator folder changed." }
    }

    private fun path(parts: List<String>): File {
        live()
        var file = root
        for (part in parts) {
            file = File(file, part)
            // Android can canonicalize the spelling of a regular file on
            // casefolded storage. Check the entry type without following links.
            statIfPresent(file)
        }
        return file
    }

    private fun entries(folder: File): List<File> {
        val relative = folder.toRelativeString(root)
        val checked = path(if (relative.isEmpty()) emptyList() else relative.split('/'))
        require(statIfPresent(checked)?.let { OsConstants.S_ISDIR(it.st_mode) } == true)
        val names = folder.list() ?: error("The prepared emulator folder could not be read.")
        require(names.size <= 10000)
        return names.map { name ->
            require(sharedSavePath(name) == listOf(name))
            File(folder, name)
        }
    }

    private fun inspect(file: File, limit: Int, read: (FileInputStream, Int) -> ByteArray): ByteArray {
        live()
        val fd = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW or OsConstants.O_NONBLOCK, 0)
        return FileInputStream(fd).use { input ->
            val stat = Os.fstat(fd)
            require(OsConstants.S_ISREG(stat.st_mode) && stat.st_size in 0..limit.toLong())
            val result = read(input, stat.st_size.toInt())
            val latest = Os.lstat(file.path)
            require(stat.st_dev == latest.st_dev && stat.st_ino == latest.st_ino &&
                stat.st_size == latest.st_size && stat.st_mtime == latest.st_mtime &&
                stat.st_ctime == latest.st_ctime) { "The emulator file changed during inspection." }
            result
        }
    }

    private fun bytes(file: File, limit: Int) =
        inspect(file, limit) { input, size -> RootSaveTransfer.readExact(input, size, ::live) }

    private fun statIfPresent(file: File) = try {
        Os.lstat(file.path).also {
            require(!OsConstants.S_ISLNK(it.st_mode)) { "Linked emulator paths are unsupported." }
        }
    } catch (error: ErrnoException) {
        if (error.errno != OsConstants.ENOENT) throw error
        null
    }

    private fun present(file: File) = statIfPresent(file) != null

    private fun cardName(file: File): String {
        if (!present(file.parentFile!!)) return file.name
        val matches = entries(file.parentFile!!).filter { it.name.equals(file.name, ignoreCase = true) }
        require(matches.size <= 1 && matches.none { it.isDirectory }) { "ARMSX2 memory card names are ambiguous." }
        val listed = matches.singleOrNull() ?: return file.name
        if (!present(file)) return file.name
        val a = Os.lstat(file.path)
        val b = Os.lstat(listed.path)
        require(OsConstants.S_ISREG(a.st_mode) && a.st_dev == b.st_dev && a.st_ino == b.st_ino)
        return listed.name
    }

    private fun inventory(areas: List<Map<String, String>>): Map<String, Map<String, Any>> {
        require(areas.size in 1..16)
        val result = linkedMapOf<String, Map<String, Any>>()
        var scanned = 0
        var total = 0L
        for (area in areas) {
            require(area.keys.all { it in setOf("path", "prefix", "suffix", "exact", "pattern", "folderPrefix", "gciId", "excluded") })
            val base = area.getValue("path")
            val directory = path(sharedSavePath(base))
            if (!present(directory)) continue
            val pattern = area["pattern"]?.toRegex()
            val excluded = area["excluded"]?.let { org.json.JSONArray(it) }
            fun visit(folder: File, prefix: String, depth: Int) {
                require(depth < 32)
                for (file in entries(folder)) {
                    require(++scanned <= 16384)
                    val name = "$prefix${file.name}"
                    if (area["folderPrefix"]?.let { !name.substringBefore('/').startsWith(it) } == true) continue
                    if (area["prefix"]?.let { !name.startsWith(it) } == true ||
                        area["exact"]?.let { it != name } == true) continue
                    val stat = Os.lstat(file.path)
                    if (OsConstants.S_ISDIR(stat.st_mode)) {
                        if (area["prefix"] == null && area["exact"] == null && area["gciId"] == null)
                            visit(file, "$name/", depth + 1)
                        continue
                    }
                    if (area["suffix"]?.let { !name.endsWith(it) } == true ||
                        pattern?.matches(name) == false ||
                        excluded?.let { a -> (0 until a.length()).any { a.getString(it) == name } } == true) continue
                    require(OsConstants.S_ISREG(stat.st_mode))
                    val fileBytes = bytes(file, MAX_FILE)
                    if (area["gciId"]?.let { fileBytes.size < 6 || String(fileBytes, 0, 6, Charsets.US_ASCII) != it } == true) continue
                    total += fileBytes.size
                    require(total <= 512L * 1024 * 1024 && result.size < 4096)
                    require(result.put("$base/$name", mapOf("bytes" to fileBytes.size.toLong(),
                        "sha256" to RootSaveFiles.digest(fileBytes))) == null)
                }
            }
            visit(directory, "", 0)
        }
        return result
    }

    fun operation(request: Bundle, caller: Int): Bundle {
        val operation = request.getString("operation")!!
        val value = request.getString("path")
        val file = value?.takeIf(String::isNotEmpty)?.let { path(sharedSavePath(it)) }
        return Bundle().apply {
            when (operation) {
                "preparedsharedcheck" -> live()
                "preparedsharedchildren" -> {
                    val parent = if (value.isNullOrEmpty()) root else file!!
                    val rows = if (!present(parent)) emptyList() else entries(parent).map {
                        val stat = Os.lstat(it.path)
                        require(OsConstants.S_ISDIR(stat.st_mode) || OsConstants.S_ISREG(stat.st_mode))
                        Bundle().apply {
                            putString("name", it.name); putBoolean("directory", OsConstants.S_ISDIR(stat.st_mode))
                        }
                    }
                    require(rows.size <= 4096)
                    putParcelableArrayList("children", ArrayList(rows))
                }
                "preparedsharedarmsx2cardname" -> putString("name", cardName(file!!))
                "preparedsharedstat" -> if (present(file!!)) {
                    val stat = Os.lstat(file.path)
                    require(OsConstants.S_ISREG(stat.st_mode))
                    putString("id", "${stat.st_dev}:${stat.st_ino}")
                    putLong("bytes", stat.st_size); putLong("modified", stat.st_mtime * 1000)
                }
                "preparedsharedbytes" -> if (present(file!!)) putByteArray("bytes", bytes(file, 512 * 1024))
                "preparedsharedlist" -> putBundle("files", Bundle().apply {
                    val areas = request.getParcelableArrayList<Bundle>("areas")!!.map { area ->
                        area.keySet().associateWith { area.getString(it)!! }
                    }
                    val inventory = inventory(areas)
                    require(inventory.keys.sumOf { it.length + 128 } <= 240_000) {
                        "The prepared save inventory exceeds Android’s transfer limit."
                    }
                    for ((name, item) in inventory) putBundle(name, Bundle().apply {
                        putLong("bytes", item.getValue("bytes") as Long)
                        putString("sha256", item.getValue("sha256") as String)
                    })
                })
                "preparedsharedread" -> {
                    val expected = request.getLong("bytes")
                    require(expected in 0..MAX_FILE.toLong())
                    val content = bytes(file!!, expected.toInt())
                    require(content.size.toLong() == expected && RootSaveFiles.digest(content) == request.getString("sha256"))
                    writerClosed()
                    RootSaveTransfer.write(request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller, content, ::live)
                }
                "preparedsharedreplace" -> {
                    require(file != null && value != "@root")
                    val source = request.getParcelable<ParcelFileDescriptor>("transfer")
                    val after = request.getString("after")
                    require((source == null) == (after == null))
                    if (!present(file.parentFile!!) && after == null) {
                        require(request.getString("before") == null)
                        return@apply
                    }
                    val parent = file.parentFile!!
                    val logical = parent.path.removePrefix("/data/media/0/")
                    val verified = sharedSetupDirectory(logical, create = after != null)
                    val stat = Os.lstat(verified.path)
                    val label = Os.getxattr(verified.path, "security.selinux")
                    val files = RootSaveFiles(verified, stat.st_uid, label, ::live, writerClosed = writerClosed, mediaGroup = stat.st_gid)
                    val payload = source?.let { RootSaveTransfer.read(it, caller, MAX_FILE, ::live) }
                    val metadata = if (payload != null) {
                        if (files.present(file)) files.metadata(file, Os.lstat(file.path).st_nlink.coerceAtMost(2L))
                        else "${stat.st_uid} ${stat.st_gid} 660 ${String(label).trimEnd('\u0000')}"
                    } else null
                    files.replaceStandalone(file.name, request.getString("before"), after, payload,
                        metadata, request.getString("token")!!, MAX_FILE) {
                        val current = Os.lstat(sharedSetupDirectory(logical).path)
                        require(current.st_dev == stat.st_dev && current.st_ino == stat.st_ino)
                    }
                }
                else -> error("Unsupported prepared emulator folder operation.")
            }
        }
    }

    private companion object { const val MAX_FILE = 72 * 1024 * 1024 }
}
