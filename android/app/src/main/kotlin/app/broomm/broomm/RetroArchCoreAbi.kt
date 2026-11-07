package app.broomm.broomm

import android.system.Os
import android.system.OsConstants
import java.io.DataInputStream
import java.io.File
import java.io.FileInputStream

internal fun retroArchElfAbi(bytes: ByteArray): String {
    require(bytes.size >= 20 && bytes[0] == 0x7f.toByte() && bytes[1] == 0x45.toByte() &&
        bytes[2] == 0x4c.toByte() && bytes[3] == 0x46.toByte() && bytes[5] == 1.toByte() &&
        bytes[6] == 1.toByte() && bytes[16] == 3.toByte() && bytes[17] == 0.toByte() && bytes[19] == 0.toByte()) {
        "RetroArch core is not a supported Android ELF shared library."
    }
    return when (bytes[4].toInt() to (bytes[18].toInt() and 255)) {
        2 to 183 -> "arm64-v8a"
        1 to 40 -> "armeabi-v7a"
        2 to 62 -> "x86_64"
        1 to 3 -> "x86"
        else -> error("RetroArch's Android ABI is unsupported for automatic mGBA setup.")
    }
}

internal fun retroArchFrontendAbi(libraryDir: String): String {
    val library = File(libraryDir, "libretroarch-activity.so")
    val fd = Os.open(library.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW or OsConstants.O_NONBLOCK, 0)
    return DataInputStream(FileInputStream(fd)).use { input ->
        require(OsConstants.S_ISREG(Os.fstat(fd).st_mode))
        retroArchElfAbi(ByteArray(20).also(input::readFully))
    }
}
