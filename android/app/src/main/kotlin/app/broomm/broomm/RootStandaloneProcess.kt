package app.broomm.broomm

import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import android.os.SystemClock

/** Process absence is separate from Activity focus and emulator pause. */
internal fun requireNoEmulatorProcess(uid: Int, name: String, live: () -> Unit) {
    check(!emulatorProcessPresent(uid, live)) {
        "Save and exit $name. If Android keeps it open, force-close it after saving, then retry."
    }
}

private fun emulatorProcessPresent(uid: Int, live: () -> Unit): Boolean {
    val processes = File("/proc").list() ?: error("Cannot verify that the emulator has stopped.")
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
        if (owned) return true
    }
    return false
}

/** Explicit package stop, serialized with root file access. Android owns the
 * process signal and stopped state for the verified user and application. */
internal fun forceStopEmulator(pkg: String, uid: Int, live: () -> Unit) {
    live()
    val child = ProcessBuilder("/system/bin/am", "force-stop", "--user", "0", pkg)
        .redirectErrorStream(true).redirectOutput(File("/dev/null")).start()
    try {
        child.outputStream.close()
        val deadline = android.os.SystemClock.elapsedRealtime() + 3000
        while (true) {
            live()
            check(android.os.SystemClock.elapsedRealtime() < deadline) {
                "Android did not finish stopping the emulator. Recovery was kept."
            }
            val exit = try { child.exitValue() } catch (_: IllegalThreadStateException) { null }
            if (exit != null) {
                check(exit == 0) { "Android could not force-close the emulator. Recovery was kept." }
                break
            }
            Thread.sleep(25)
        }
    } finally { child.destroy() }
    val deadline = android.os.SystemClock.elapsedRealtime() + 1000
    while (emulatorProcessPresent(uid, live)) {
        check(android.os.SystemClock.elapsedRealtime() < deadline) {
            "The emulator still has a process. Recovery was kept."
        }
        Thread.sleep(25)
    }
}

// Literal arguments only. Both pipes are drained without waiting for a
// descendant's EOF; the root service's operation deadline remains active.
internal fun rootLifecycleCommand(arguments: List<String>, limit: Int, live: () -> Unit): ByteArray {
    val process = ProcessBuilder(arguments).start()
    val output = ByteArrayOutputStream(); val errors = ByteArrayOutputStream()
    val deadline = SystemClock.elapsedRealtime() + 3000
    fun drain(stream: java.io.InputStream, target: ByteArrayOutputStream) {
        val b = ByteArray(4096)
        while (stream.available() > 0) {
            live(); check(SystemClock.elapsedRealtime() < deadline)
            val n = stream.read(b, 0, minOf(b.size, stream.available()))
            if (n <= 0) break
            check(output.size() + errors.size() + n <= limit)
            target.write(b, 0, n)
        }
    }
    try {
        process.outputStream.close()
        while (true) {
            live(); check(SystemClock.elapsedRealtime() < deadline)
            drain(process.inputStream, output); drain(process.errorStream, errors)
            val exit = try { process.exitValue() } catch (_: IllegalThreadStateException) { null }
            if (exit != null) {
                drain(process.inputStream, output); drain(process.errorStream, errors)
                check(exit == 0 && errors.size() == 0) { "Emulator lifecycle query failed." }
                return output.toByteArray()
            }
            Thread.sleep(5)
        }
    } finally {
        process.destroy()
        for (s in listOf(process.inputStream, process.errorStream, process.outputStream))
            try { s.close() } catch (_: IOException) { }
    }
}
