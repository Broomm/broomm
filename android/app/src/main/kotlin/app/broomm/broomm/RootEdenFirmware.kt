package app.broomm.broomm

import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileOutputStream
import java.security.DigestInputStream
import java.security.MessageDigest
import java.util.zip.ZipInputStream

private const val FIRMWARE_TOTAL = 2L * 1024 * 1024 * 1024
private const val FIRMWARE_NCA = 512L * 1024 * 1024
private val ncaName = Regex("([a-fA-F0-9]{32})(?:\\.cnmt)?\\.nca")

/** Installs one complete, verified firmware tree in Eden's registered directory. */
internal fun installEdenFirmware(
    destination: File,
    source: ParcelFileDescriptor,
    caller: Int,
    expected: String,
    uid: Int,
    label: ByteArray,
    live: () -> Unit,
    verifyClosedStorage: () -> Unit,
) {
    require(Regex("[a-f0-9]{64}").matches(expected))
    val parent = destination.parentFile!!
    val stage = File(parent, ".broomm-firmware-${expected.take(32)}")
    fun flush(directory: File) {
        val fd = Os.open(directory.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        try { require(OsConstants.S_ISDIR(Os.fstat(fd).st_mode)); Os.fsync(fd) } finally { Os.close(fd) }
    }
    fun listStage(): Array<File> {
        val info = Os.lstat(stage.path)
        require(OsConstants.S_ISDIR(info.st_mode) && info.st_uid in setOf(0, uid) && stage.canonicalPath == stage.path)
        val entries = stage.listFiles() ?: error("Eden firmware stage cannot be inspected.")
        require(entries.size <= 4096)
        for (file in entries) {
            val stat = Os.lstat(file.path)
            require(ncaName.matches(file.name) && OsConstants.S_ISREG(stat.st_mode) &&
                stat.st_nlink == 1L && stat.st_uid in setOf(0, uid))
        }
        return entries
    }
    verifyClosedStorage()
    if (stage.exists()) {
        for (file in listStage()) Os.remove(file.path)
        Os.remove(stage.path)
    }
    Os.mkdir(stage.path, 448)
    var moved = false
    try {
        val digest = MessageDigest.getInstance("SHA-256")
        RootSaveTransfer.source(source, caller, FIRMWARE_TOTAL) { input, _ ->
            val raw = DigestInputStream(input, digest)
            val archive = ZipInputStream(raw)
            val names = mutableSetOf<String>()
            val buffer = ByteArray(65536)
            var total = 0L
            var entries = 0
            while (true) {
                live()
                val entry = archive.nextEntry ?: break
                require(++entries <= 8192 && entry.name.length in 1..1024)
                val parts = entry.name.removeSuffix("/").split('/')
                require(parts.all { it.isNotEmpty() && it != "." && it != ".." &&
                    it.none { c -> c.code < 32 || c == '\\' || c == ':' } })
                if (entry.isDirectory) { require(archive.read() == -1); continue }
                val name = if (parts.last() == "00" && parts.size >= 2) parts[parts.size - 2] else parts.last()
                val nca = ncaName.matchEntire(name)?.groupValues?.get(1)?.lowercase() ?: error("Invalid Switch firmware entry.")
                require(names.add(nca) && names.size <= 4096)
                val file = File(stage, "$nca.nca")
                val fd = Os.open(file.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW, 384)
                FileOutputStream(fd).use { output ->
                    var size = 0L
                    while (true) {
                        live()
                        val count = archive.read(buffer)
                        if (count < 0) break
                        size += count
                        total += count
                        require(size <= FIRMWARE_NCA && total <= FIRMWARE_TOTAL) { "Switch firmware exceeds its size limits." }
                        output.write(buffer, 0, count)
                    }
                    require(size >= 0xc00)
                    output.flush()
                    Os.fchown(fd, uid, 1078)
                    Os.setxattr(file.path, "security.selinux", label, 0)
                    Os.fsync(fd)
                }
            }
            require(names.isNotEmpty())
            // ZipInputStream has already hashed buffered central-directory bytes.
            // Read the remaining raw archive to verify the entire RomM payload.
            while (true) { live(); if (raw.read(buffer) < 0) break }
            require(digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) } == expected) {
                "Switch firmware changed during installation."
            }
        }
        Os.chown(stage.path, uid, 1078)
        Os.chmod(stage.path, 1528)
        Os.setxattr(stage.path, "security.selinux", label, 0)
        flush(stage)
        verifyClosedStorage()
        if (destination.exists()) Os.remove(destination.path)
        // Reserve the empty destination exclusively. A concurrent new folder
        // makes mkdir fail, and a populated directory cannot be overwritten.
        Os.mkdir(destination.path, 448)
        Os.chown(destination.path, uid, 1078)
        Os.chmod(destination.path, 1528)
        Os.setxattr(destination.path, "security.selinux", label, 0)
        val reserved = Os.lstat(destination.path)
        verifyClosedStorage()
        val current = Os.lstat(destination.path)
        require(reserved.st_dev == current.st_dev && reserved.st_ino == current.st_ino && destination.list()?.isEmpty() == true)
        Os.rename(stage.path, destination.path)
        moved = true
        flush(parent)
    } finally {
        if (!moved && stage.exists()) {
            for (file in listStage()) Os.remove(file.path)
            Os.remove(stage.path)
        }
    }
}
