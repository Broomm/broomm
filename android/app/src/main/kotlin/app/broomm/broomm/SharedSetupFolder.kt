package app.broomm.broomm

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.File

internal fun defaultSharedSetupFolder(pkg: String?): String? = when (pkg) {
    "org.azahar_emu.azahar", "io.github.lime3ds.android" -> "Broomm/Azahar"
    "org.citra.emu", "com.antutu.ABenchMark" -> "citra-emu"
    "org.ppsspp.ppsspp", "org.ppsspp.ppssppgold" -> "Broomm/PPSSPP"
    else -> null
}

/** Create only a fixed primary-storage directory. Existing folders and their
 * contents are user-owned and keep their original metadata. */
internal fun prepareSharedSetupFolder(pkg: String) {
    val path = requireNotNull(defaultSharedSetupFolder(pkg))
    var logical = File("/storage/emulated/0")
    var physical = File("/data/media/0")
    for (name in path.split('/')) {
        require(logical.canonicalPath == logical.path && physical.canonicalPath == physical.path)
        logical = File(logical, name)
        physical = File(physical, name)
        try {
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
}
