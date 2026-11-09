package app.broomm.broomm

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.File

/** Process absence is separate from Activity focus and emulator pause. */
internal fun requireNoEmulatorProcess(uid: Int, name: String, live: () -> Unit) {
    val processes = File("/proc").list() ?: error("Cannot verify that $name has stopped.")
    require(processes.size <= 16384)
    for (pid in processes) {
        if (pid.toIntOrNull()?.let { it > 0 } != true) continue
        live()
        val owned = try {
            val owner = Os.stat("/proc/$pid").st_uid
            owner == uid || owner == 0 && File("/proc/$pid/status").useLines { lines ->
                lines.take(16).any { line ->
                    line.startsWith("Uid:") && line.substringAfter(':').trim()
                        .split(Regex("\\s+")).any { it == uid.toString() }
                }
            }
        } catch (e: ErrnoException) {
            if (e.errno == OsConstants.ENOENT || e.errno == OsConstants.ESRCH) false else throw e
        } catch (e: java.io.FileNotFoundException) {
            if (!File("/proc/$pid").exists()) false else throw e
        }
        check(!owned) {
            "Save and exit $name. If Android keeps it open, stop $name in Android app settings, then retry in Broomm."
        }
    }
}
