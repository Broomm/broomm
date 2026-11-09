package app.broomm.broomm

import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import java.io.InputStream

/** Bounded app-owned descriptors keep save-state bytes out of Binder parcels. */
internal object RootSaveTransfer {
    fun read(descriptor: ParcelFileDescriptor, owner: Int, limit: Int, live: () -> Unit): ByteArray =
        source(descriptor, owner, limit.toLong()) { input, size -> readExact(input, size.toInt(), live) }

    fun <T> source(descriptor: ParcelFileDescriptor, owner: Int, limit: Long, read: (InputStream, Long) -> T): T = descriptor.use {
        val fd = descriptor.fileDescriptor
        val before = Os.fstat(fd)
        require(OsConstants.S_ISREG(before.st_mode) && before.st_uid == owner && before.st_nlink == 1L &&
            before.st_size in 0..limit) { "Invalid private save transfer source." }
        ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
            val value = read(input, before.st_size)
            val after = Os.fstat(fd)
            require(before.st_size == after.st_size &&
                before.st_mtime == after.st_mtime && before.st_ctime == after.st_ctime)
            value
        }
    }

    fun readExact(input: InputStream, size: Int, live: () -> Unit): ByteArray {
        val bytes = ByteArray(size)
        var offset = 0
        while (offset < size) {
            live()
            val n = input.read(bytes, offset, minOf(65536, size - offset))
            require(n > 0) { "Root file shortened during transfer." }
            offset += n
        }
        live()
        require(input.read() == -1) { "Root file grew during transfer." }
        return bytes
    }

    fun write(descriptor: ParcelFileDescriptor, owner: Int, bytes: ByteArray, live: () -> Unit) = descriptor.use {
        val fd = descriptor.fileDescriptor
        val stat = Os.fstat(fd)
        require(OsConstants.S_ISREG(stat.st_mode) && stat.st_uid == owner && stat.st_nlink == 1L && stat.st_size == 0L) {
            "Invalid private save capture target."
        }
        ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { output ->
            var offset = 0
            while (offset < bytes.size) {
                live()
                val size = minOf(65536, bytes.size - offset)
                output.write(bytes, offset, size)
                offset += size
            }
            output.flush(); Os.fsync(fd)
            require(Os.fstat(fd).st_size == bytes.size.toLong())
        }
    }
}
