package app.broomm.broomm

import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants

/** Bounded app-owned descriptors keep save-state bytes out of Binder parcels. */
internal object RootSaveTransfer {
    fun read(descriptor: ParcelFileDescriptor, owner: Int, limit: Int, live: () -> Unit): ByteArray = descriptor.use {
        val fd = descriptor.fileDescriptor
        val before = Os.fstat(fd)
        require(OsConstants.S_ISREG(before.st_mode) && before.st_uid == owner && before.st_nlink == 1L &&
            before.st_size in 0..limit.toLong()) { "Invalid private save transfer source." }
        ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
            val output = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(65536)
            while (true) {
                live()
                val n = input.read(buffer)
                if (n < 0) break
                require(output.size() + n <= limit)
                output.write(buffer, 0, n)
            }
            val after = Os.fstat(fd)
            require(output.size().toLong() == before.st_size && before.st_size == after.st_size &&
                before.st_mtime == after.st_mtime && before.st_ctime == after.st_ctime)
            output.toByteArray()
        }
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
