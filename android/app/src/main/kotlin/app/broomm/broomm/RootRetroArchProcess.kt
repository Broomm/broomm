package app.broomm.broomm

import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.Context
import android.os.Binder
import android.os.Build
import android.os.Bundle
import android.os.SystemClock
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.IOException
import kotlin.math.abs

/** Read-only evidence for the selected user-0 RetroArch package. */
internal class RootRetroArchProcess(
    private val context: Context,
    private val pkg: String,
    private val uid: Int,
    private val live: () -> Unit,
    private val acceptSignaledExit: ((pid: Int, observed: Long, exited: Long) -> Boolean)? = null,
) {
    private fun uidOf(path: File): Int = File(path, "status").useLines { lines ->
        lines.first { it.startsWith("Uid:") }.substringAfter(':').trim()
            .substringBefore('\t').toInt()
    }

    private fun owner(path: File): Int? = try { Os.stat(path.path).st_uid }
    catch (e: ErrnoException) {
        if (e.errno == OsConstants.ENOENT || e.errno == OsConstants.ESRCH) null else throw e
    }

    private fun startTicks(path: File): Long = File(path, "stat").readText()
        .substringAfterLast(") ").split(' ')[19].toLong() // /proc stat field 22.

    private fun ticksPerSecond(): Long = Os.sysconf(OsConstants._SC_CLK_TCK).also {
        check(it in 1..10000)
    }

    private fun writers(): List<File> {
        val names = File("/proc").list() ?: error("RetroArch process list is unavailable.")
        check(names.size <= 16384)
        return names.asSequence().filter { it.toIntOrNull()?.let { pid -> pid > 0 } == true }
            .map { File("/proc", it) }.filter { path ->
                live()
                when (owner(path)) {
                    uid -> true
                    // Linux can report root ownership for a non-dumpable app.
                    0 -> try { uidOf(path) == uid } catch (e: IOException) {
                        if (owner(path) != null) throw e
                        false
                    }
                    else -> false
                }
            }.take(2).toList()
    }

    fun observe(request: Bundle, callerPid: Int, callerUid: Int): Bundle = try {
        check(callerPid > 0 && uidOf(File("/proc", callerPid.toString())) == callerUid)
        val running = writers()
        when {
            running.isNotEmpty() -> state("running").apply {
                val launchedAfter = request.getLong("launchedAfter", -1)
                if (launchedAfter >= 0 && running.size == 1) {
                    val path = running.single()
                    val start = startTicks(path)
                    val name = File(path, "cmdline").inputStream().use { stream ->
                        val bytes = ByteArray(256)
                        val size = stream.read(bytes)
                        if (size < 1) "" else String(bytes, 0, size).substringBefore('\u0000')
                    }
                    val ticks = ticksPerSecond()
                    val elapsed = SystemClock.elapsedRealtime()
                    // Keep the clock-tick rounding on the conservative side.
                    if (name == pkg && uidOf(path) == uid && startTicks(path) == start &&
                        start > launchedAfter * ticks / 1000 && start <= elapsed * ticks / 1000) {
                        putInt("pid", path.name.toInt())
                        putLong("startTicks", start)
                        putLong("observedElapsed", elapsed)
                        putLong("observedWall", System.currentTimeMillis())
                    }
                }
            }
            !request.containsKey("pid") -> state("idle").apply {
                putLong("elapsed", SystemClock.elapsedRealtime())
            }
            Build.VERSION.SDK_INT >= 30 -> exit(request)
            else -> state("unknown")
        }
    } catch (_: Exception) { state("unknown") }

    private fun exit(request: Bundle): Bundle {
        val observed = request.getLong("observedWall")
        val observedElapsed = request.getLong("observedElapsed")
        val elapsed = SystemClock.elapsedRealtime() - observedElapsed
        val now = System.currentTimeMillis()
        if (observed <= 0 || elapsed < 0 || abs(now - observed - elapsed) > 2000 ||
            request.getLong("startTicks") !in 1..(observedElapsed * ticksPerSecond() / 1000))
            return state("unknown")
        // Cross-package exit history needs DUMP. Use the bound service's root
        // identity for this single query, after the outer Binder verified Broomm.
        val identity = Binder.clearCallingIdentity()
        val records = try {
            context.getSystemService(ActivityManager::class.java)
                .getHistoricalProcessExitReasons(pkg, 0, 16)
        } finally { Binder.restoreCallingIdentity(identity) }
        val record = records.filter { it.timestamp >= observed }.singleOrNull()
            ?: return state("unknown")
        if (record.pid != request.getInt("pid") || record.realUid != uid ||
            record.packageUid != uid || record.processName != pkg || record.timestamp > now)
            return state("unknown")
        val closed = record.reason == ApplicationExitInfo.REASON_EXIT_SELF && record.status == 0 ||
            record.reason == ApplicationExitInfo.REASON_SIGNALED && record.status == 9 &&
            acceptSignaledExit?.invoke(record.pid, observed, record.timestamp) == true
        if (writers().isNotEmpty()) return state("running")
        return state(if (closed) "closed" else "interrupted")
    }

    private fun state(value: String) = Bundle().apply { putString("state", value) }
}
