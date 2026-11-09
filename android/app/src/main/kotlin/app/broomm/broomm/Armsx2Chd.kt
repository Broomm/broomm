package app.broomm.broomm

import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import java.io.File

/** Libchdr is loaded only in the unprivileged method-channel worker. */
internal object Armsx2Chd {
    private val available = runCatching { System.loadLibrary("broomm_ps2_disc") }.isSuccess

    private external fun open(descriptor: Int): Long
    private external fun geometry(handle: Long): LongArray
    private external fun sector(handle: Long, index: Long, offset: Int): ByteArray?
    private external fun close(handle: Long)

    fun disc(file: File, live: () -> Unit): Armsx2Disc =
        ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY).use { descriptor ->
            check(available) { "Broomm’s PS2 CHD reader is unavailable on this installation." }
            live()
            val handle = open(descriptor.fd)
            require(handle != 0L) { "Use a supported, self-contained PS2 CHD image." }
            try {
                val (sectors, stride) = geometry(handle)
                fun read(index: Long, offset: Int) = sector(handle, index, offset)
                    ?: error("The PS2 CHD has an unreadable sector.")
                val offset = listOf(0, 16, 24).filter { it + 2048 <= stride }
                    .singleOrNull { isPrimary(read(16, it)) }
                    ?: error("The PS2 CHD has no supported ISO9660 layout.")
                readArmsx2Iso(sectors, live) { read(it, offset) }
            } finally {
                close(handle)
            }
        }
}

internal fun armsx2MediaStamp(file: File): String {
    val info = Os.lstat(file.path)
    require(OsConstants.S_ISREG(info.st_mode) && info.st_nlink == 1L)
    return "${info.st_dev}:${info.st_ino}:${info.st_size}:${info.st_mtime}"
}
