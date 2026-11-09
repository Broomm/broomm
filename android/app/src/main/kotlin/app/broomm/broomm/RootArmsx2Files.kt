package app.broomm.broomm

import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import java.io.File

internal const val ARMSX2_PACKAGE = "com.armsx2"
internal const val ARMSX2_VERSION = "2.9.2"
internal const val ARMSX2_SIGNER = "df91c9ce39d3f53c9bab5f2c1e0820e761800c93f1805305b87e87486d244d5a"
private const val BIOS_BYTES = 4 * 1024 * 1024

/** Firmware and game-specific progress in the reviewed ARMSX2 data root. */
internal class RootArmsx2Files(identity: Map<String, Any>, private val live: () -> Unit) {
    private val uid = identity.getValue("uid") as Int
    private val internal = File(identity.getValue("dataDir") as String).canonicalFile
    private val internalLabel = Os.getxattr(internal.path, "security.selinux")
    private val label = String(internalLabel).replace("app_data_file:", "media_rw_data_file:").toByteArray()
    private val root = File("/data/media/0/Android/data/$ARMSX2_PACKAGE")
    private val logical = File("/storage/emulated/0/Android/data/$ARMSX2_PACKAGE")
    private val first = Os.lstat(root.path)
    private val files = RootSaveFiles(root, uid, label, live, writerClosed = ::closed, mediaGroup = 1078)
    private val privateFiles = RootSaveFiles(internal, uid, internalLabel, live)

    private fun closed() = requireNoEmulatorProcess(uid, "ARMSX2", live)

    private fun verify() {
        closed()
        for (path in listOf(root, logical)) {
            val info = Os.lstat(path.path)
            require(path.canonicalPath == path.path && OsConstants.S_ISDIR(info.st_mode) &&
                info.st_dev == first.st_dev && info.st_ino == first.st_ino &&
                info.st_uid == uid && info.st_gid == 1078 && (info.st_mode and 4095) == 1528 &&
                Os.getxattr(path.path, "security.selinux").contentEquals(label)) {
                "ARMSX2’s native firmware storage could not be verified."
            }
        }
    }

    private val bios = "files/bios/bios.bin"
    private fun biosMissing(): Boolean {
        val directory = files.path("files/bios")
        if (!files.present(directory)) return true
        val stat = Os.lstat(directory.path)
        require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_dev == first.st_dev &&
            stat.st_uid == uid && stat.st_gid == 1078 &&
            Os.getxattr(directory.path, "security.selinux").contentEquals(label))
        val entries = directory.listFiles() ?: error("ARMSX2’s BIOS folder could not be read.")
        require(entries.size <= 32)
        // Existing BIOS content belongs to ARMSX2. Only an empty directory or
        // Broomm's own interrupted publication can use automatic installation.
        val target = files.path(bios)
        if (entries.isEmpty()) return true
        if (entries.size <= 2 && entries.all {
            it == target || Regex("\\.bios\\.bin\\.broomm-[a-f0-9]{32}-in").matches(it.name)
        } && (!files.present(target) || Os.lstat(target.path).st_nlink == 2L)) return true
        return false
    }

    private fun report(): Bundle {
        verify()
        return Bundle().apply {
            putString("label", String(internalLabel).trimEnd('\u0000'))
            putString("externalLabel", String(label).trimEnd('\u0000'))
            putString("externalGid", "1078")
            putString("externalDevice", first.st_dev.toString())
            putString("externalInode", first.st_ino.toString())
        }
    }

    fun status() = report().apply { putString("missing", biosMissing().toString()) }

    fun provision(request: Bundle, caller: Int): Bundle {
        val binding = status()
        require(binding.keySet().filter { it != "missing" }.all { binding.getString(it) == request.getString(it) }) {
            "ARMSX2’s storage changed. No BIOS was replaced."
        }
        if (binding.getString("missing") == "true") {
            val expected = request.getString("after")!!
            require(Regex("[a-f0-9]{64}").matches(expected))
            val payload = RootSaveTransfer.read(request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller, BIOS_BYTES, live)
            val header = String(payload, 0, minOf(payload.size, 512 * 1024), Charsets.ISO_8859_1)
            require(payload.size == BIOS_BYTES && "ROMDIR" in header && "ROMVER" in header) { "Invalid PS2 BIOS." }
            files.replaceStandalone(bios, null, expected, payload, null, expected.take(32) + "-in", BIOS_BYTES) {
                verify()
                require(biosMissing()) { "An ARMSX2 BIOS appeared during installation. It was kept." }
            }
            require(files.hash(files.existing(bios), BIOS_BYTES) == expected)
        }
        verify()
        return Bundle()
    }

    private fun readConfig(access: RootSaveFiles, relative: String): ByteArray? {
        val file = access.path(relative)
        return if (access.present(file)) access.bytes(access.existing(relative), 1024 * 1024) else null
    }

    private fun verifySettings(disc: Armsx2Disc? = null) {
        val ini = readConfig(files, "files/PCSX2-Android.ini") ?: run {
            require(!biosMissing() && listOf("files/memcards", "files/sstates").all { relative ->
                val directory = verifyParent(relative)
                !files.present(directory) || directory.list()?.isEmpty() == true
            }) { "Initialize ARMSX2 with its default data folder and PS2 BIOS, then close it and retry Setup." }
            // The reviewed launcher initializes native settings on its first
            // external boot when a BIOS is already available.
            ByteArray(0)
        }
        val prefs = readConfig(privateFiles, "shared_prefs/ARMSX2.xml")
        val backup = readConfig(files, "files/armsx2-settings.json")
        requireArmsx2DefaultSettings(logical.path + "/files", ini, prefs, backup, disc)
        if (disc != null) {
            val gameIni = readConfig(files, "files/gamesettings/${disc.serial}_${disc.crc}.ini")
                ?: readConfig(files, "files/gamesettings/${disc.crc}.ini")
            gameIni?.let { requireArmsx2IniDefaults(logical.path + "/files", it) }
        }
    }

    fun setup(): Bundle = report().also {
        verifySettings()
        verify()
    }

    private fun validateBinding(request: Bundle) {
        val current = report()
        require(current.keySet().all { current.getString(it) == request.getString(it) }) {
            "ARMSX2’s installation or save storage changed. Recovery was kept."
        }
    }

    fun progress(request: Bundle, game: File, caller: Int): Bundle {
        validateBinding(request)
        require(armsx2MediaStamp(game) == request.getString("mediaStamp")) {
            "The ARMSX2 disc changed between Android storage views. Recovery was kept."
        }
        val serial = request.getString("serial")!!
        val crc = request.getString("crc")!!
        require(Regex("[A-Z]{4}-[0-9]{5}").matches(serial) && Regex("[0-9A-F]{8}").matches(crc))
        val disc = Armsx2Disc(serial, crc)
        verifySettings(disc)
        val operation = request.getString("operation")
        if (operation == "armsx2scope") return Bundle().apply {
            verify()
            putString("serial", disc.serial)
            putString("crc", disc.crc)
            putString("mediaStamp", request.getString("mediaStamp"))
        }
        val result = when (operation) {
            "armsx2check" -> Bundle()
            "armsx2list" -> Bundle().apply {
                val inventory = Bundle()
                var total = 0L
                for (relative in progressPaths(disc)) {
                    val bytes = progressBytes(disc, relative)
                    total += bytes.size
                    require(total <= 512L * 1024 * 1024) { "ARMSX2 progress exceeds the supported inventory size." }
                    inventory.putBundle(relative, row(relative, bytes))
                }
                putBundle("files", inventory)
            }
            "armsx2read" -> {
                val relative = request.getString("path")!!
                val bytes = progressBytes(disc, relative)
                val entry = row(relative, bytes)
                require(entry.getLong("bytes") == request.getLong("bytes") &&
                    entry.getString("sha256") == request.getString("sha256") &&
                    entry.getString("metadata") == request.getString("metadata")) {
                    "ARMSX2 progress changed before capture. Recovery was kept."
                }
                closed()
                RootSaveTransfer.write(request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller, bytes, live)
                Bundle()
            }
            "armsx2replace" -> {
                val relative = request.getString("path")!!
                val limit = limit(disc, relative)
                val source = request.getParcelable<ParcelFileDescriptor>("transfer")
                val bytes = source?.let { RootSaveTransfer.read(it, caller, limit, live) }
                bytes?.let { validateProgress(relative, it) }
                verifyParent(relative.substringBeforeLast('/'))
                files.replaceStandalone(relative, request.getString("before"), request.getString("after"),
                    bytes, request.getString("metadata"), request.getString("token")!!, limit) {
                    validateBinding(request)
                    require(armsx2MediaStamp(game) == request.getString("mediaStamp"))
                    verifySettings(disc)
                    verifyParent(relative.substringBeforeLast('/'))
                }
                Bundle()
            }
            else -> error("Unsupported ARMSX2 save operation.")
        }
        verify()
        return result
    }

    private fun verifyParent(relative: String): File {
        val directory = files.path(relative)
        var parent = directory
        while (parent != root) {
            if (files.present(parent)) {
                val stat = Os.lstat(parent.path)
                require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_dev == first.st_dev &&
                    stat.st_uid == uid && stat.st_gid == 1078 && (stat.st_mode and 4095) == 1528 &&
                    Os.getxattr(parent.path, "security.selinux").contentEquals(label)) {
                    "ARMSX2 save directory ownership changed. Recovery was kept."
                }
            }
            parent = parent.parentFile!!
        }
        return directory
    }

    private fun progressPaths(disc: Armsx2Disc): List<String> {
        verifyParent("files/memcards")
        val states = verifyParent("files/sstates")
        val selected = if (!files.present(states)) emptyList() else states.list()
            ?.filter(disc::acceptsState)?.sorted() ?: error("ARMSX2 save states could not be listed.")
        require(selected.size <= 32) { "ARMSX2 has too many states for this game." }
        return CARD_PATHS.filter { files.present(files.path(it)) } + selected.map { "files/sstates/$it" }
    }

    private fun limit(disc: Armsx2Disc, relative: String): Int {
        if (relative in CARD_PATHS) return CARD_BYTES.last()
        require(relative.startsWith("files/sstates/") && disc.acceptsState(relative.removePrefix("files/sstates/"))) {
            "ARMSX2 progress is outside the selected game."
        }
        return 64 * 1024 * 1024
    }

    private fun progressBytes(disc: Armsx2Disc, relative: String): ByteArray {
        val max = limit(disc, relative)
        verifyParent(relative.substringBeforeLast('/'))
        return files.bytes(files.existing(relative), max).also { validateProgress(relative, it) }
    }

    private fun row(relative: String, bytes: ByteArray) = Bundle().apply {
        putLong("bytes", bytes.size.toLong())
        putString("sha256", RootSaveFiles.digest(bytes))
        putString("metadata", files.metadata(files.path(relative)))
    }

    private fun validateProgress(relative: String, bytes: ByteArray) {
        if (relative in CARD_PATHS) {
            require(bytes.size in CARD_BYTES && (bytes.take(28).all { it == 0xff.toByte() } ||
                String(bytes, 0, 28, Charsets.US_ASCII) == "Sony PS2 Memory Card Format ")) {
                "ARMSX2 needs a native whole PS2 memory card."
            }
        } else require(bytes.size >= 22 && bytes[0] == 0x50.toByte() && bytes[1] == 0x4b.toByte() &&
            bytes[2] == 3.toByte() && bytes[3] == 4.toByte()) { "ARMSX2 save state has an invalid container." }
    }

    private companion object {
        val CARD_PATHS = listOf("files/memcards/mcd001.ps2", "files/memcards/mcd002.ps2")
        val CARD_BYTES = listOf(8, 16, 32, 64).map { it * 1024 * 1024 / 512 * 528 }
    }
}
