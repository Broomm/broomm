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

/** Firmware bootstrap for ARMSX2's reviewed launcher adoption contract. */
internal class RootArmsx2Firmware(identity: Map<String, Any>, private val live: () -> Unit) {
    private val uid = identity.getValue("uid") as Int
    private val internal = File(identity.getValue("dataDir") as String).canonicalFile
    private val internalLabel = Os.getxattr(internal.path, "security.selinux")
    private val label = String(internalLabel).replace("app_data_file:", "media_rw_data_file:").toByteArray()
    private val root = File("/data/media/0/Android/data/$ARMSX2_PACKAGE")
    private val logical = File("/storage/emulated/0/Android/data/$ARMSX2_PACKAGE")
    private val first = Os.lstat(root.path)
    private val files = RootSaveFiles(root, uid, label, live, writerClosed = ::closed, mediaGroup = 1078)

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

    fun status(): Bundle {
        verify()
        return Bundle().apply {
            putString("label", String(internalLabel).trimEnd('\u0000'))
            putString("externalLabel", String(label).trimEnd('\u0000'))
            putString("externalGid", "1078")
            putString("externalDevice", first.st_dev.toString())
            putString("externalInode", first.st_ino.toString())
            putString("missing", biosMissing().toString())
        }
    }

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
}
