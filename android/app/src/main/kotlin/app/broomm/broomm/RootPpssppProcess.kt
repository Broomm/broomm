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
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.IOException
import kotlin.math.abs

/** Pinned PPSSPP can finish native writers while Android keeps its Java PID cached. */
internal class RootPpssppProcess(
    private val context: Context,
    private val pkg: String,
    private val uid: Int,
    private val live: () -> Unit,
    private val diagnostic: (Exception) -> Unit = {},
    private val observation: (String) -> Unit = {},
) {
    private val manager get() = context.getSystemService(ActivityManager::class.java)
    private fun owner(path: File): Int? = try { Os.stat(path.path).st_uid }
    catch (e: ErrnoException) { if (e.errno in setOf(OsConstants.ENOENT, OsConstants.ESRCH)) null else throw e }
    private fun uidOf(path: File): Int = File(path, "status").useLines { rows ->
        rows.first { it.startsWith("Uid:") }.substringAfter(':').trim().split(Regex("\\s+"))[0].toInt()
    }
    private fun ticks(path: File): Long = File(path, "stat").readText().substringAfterLast(") ").split(' ')[19].toLong()
    private fun rate() = Os.sysconf(OsConstants._SC_CLK_TCK).also { check(it in 1..10000) }
    private fun processes(): List<File> {
        val names = File("/proc").list() ?: error("PPSSPP process inspection is unavailable.")
        check(names.size <= 16384)
        return names.asSequence().filter { it.toIntOrNull()?.let { n -> n > 0 } == true }
            .map { File("/proc", it) }.filter { path ->
                live()
                when (owner(path)) {
                    uid -> true
                    0 -> try { uidOf(path) == uid } catch (e: IOException) {
                        if (owner(path) != null) throw e
                        false
                    }
                    else -> false
                }
            }.take(2).toList()
    }

    // Literal arguments only. Both pipes are drained without waiting for a
    // descendant's EOF; the root service's operation deadline remains active.
    private fun command(arguments: List<String>, limit: Int): ByteArray {
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
                    check(exit == 0 && errors.size() == 0) { "PPSSPP lifecycle query failed." }
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

    @Suppress("DEPRECATION")
    private fun activityPresent(): Boolean {
        val identity = Binder.clearCallingIdentity()
        return try {
            val tasks = manager.getRunningTasks(256)
            check(tasks.size < 256) { "PPSSPP activity observation is incomplete." }
            tasks.any { it.numActivities > 0 && (it.baseActivity?.packageName == pkg ||
                it.topActivity?.packageName == pkg || it.baseIntent.component?.packageName == pkg) }
        } finally { Binder.restoreCallingIdentity(identity) }
    }

    fun observe(request: Bundle = Bundle()): Bundle = try {
        check(Build.VERSION.SDK_INT >= 30)
        val elapsed = SystemClock.elapsedRealtime(); val wall = System.currentTimeMillis()
        val launchElapsed = request.getLong("launchElapsed", -1)
        val launchWall = request.getLong("launchWall", -1)
        val session = request.containsKey("pid")
        if (launchElapsed >= 0 || launchWall >= 0) {
            check(launchElapsed in 0..elapsed && launchWall > 0 && abs(wall - launchWall - (elapsed - launchElapsed)) <= 2000)
        }
        val found = processes()
        observation("processes=${found.map { it.name }}")
        if (found.isEmpty()) {
            if (!session) state("idle", elapsed, wall) else exited(request, elapsed, wall)
        } else if (found.size != 1) state("unknown", elapsed, wall)
        else {
            val path = found.single(); val pid = path.name.toInt(); val start = ticks(path)
            val name = File(path, "cmdline").inputStream().use { input ->
                val b = ByteArray(256); val n = input.read(b)
                if (n < 1) "" else String(b, 0, n, Charsets.UTF_8).substringBefore('\u0000')
            }
            check(name == pkg && uidOf(path) == uid && start > 0)
            if (session) check(request.getInt("pid") == pid && request.getLong("startTicks") == start)
            val tasks = activityPresent()
            val status = String(command(listOf("/system/bin/cmd", "activity", "get-uid-state", uid.toString()), 256), Charsets.US_ASCII).trim()
            val cached = Regex("(?:18 \\(CACHED_RECENT\\)|19 \\(CACHED_EMPTY\\))").matches(status)
            val earliest = wall - elapsed + start * 1000 / rate() - 1000
            val log = command(listOf("/system/bin/logcat", "-B", "-b", "main", "-d", "--pid=$pid", "--uid=$uid", "-t", "1000", "-s", "PpssppActivity:I"), PpssppShutdownProof.MAX_BYTES)
            observation("binaryLifecycleBytes=${log.size}")
            val afterWall = System.currentTimeMillis(); val afterElapsed = SystemClock.elapsedRealtime()
            check(abs(afterWall - wall - (afterElapsed - elapsed)) <= 100 &&
                uidOf(path) == uid && ticks(path) == start && processes().single().name == path.name)
            val proof = PpssppShutdownProof.inspect(log, pid, uid, earliest, afterWall)
            val stopped = !tasks && cached && proof.closed != null && !activityPresent()
            observation("pid=$pid start=$start earliest=$earliest latest=$afterWall activities=$tasks cached=$cached created=${proof.created} closed=${proof.closed}")
            val value = when {
                stopped && launchElapsed < 0 && !session -> "idle"
                stopped && proof.closed >= launchWall -> "closed"
                stopped -> "unknown"
                tasks || !cached -> "running"
                else -> "unknown"
            }
            state(value, afterElapsed, afterWall).apply {
                if (launchElapsed >= 0 && proof.created != null && proof.created >= launchWall) {
                    putInt("pid", pid); putLong("startTicks", start)
                    putLong("launchElapsed", launchElapsed); putLong("launchWall", launchWall)
                }
            }
        }
    } catch (e: Exception) { diagnostic(e); state("unknown", SystemClock.elapsedRealtime(), System.currentTimeMillis()) }

    fun ensureClosed() {
        check(observe().getString("state") == "idle") {
            "PPSSPP is running or its native shutdown cannot be verified. Use PPSSPP’s Exit action, then retry. Progress and recovery were kept."
        }
    }

    private fun exited(request: Bundle, elapsed: Long, wall: Long): Bundle {
        val identity = Binder.clearCallingIdentity()
        val records = try { manager.getHistoricalProcessExitReasons(pkg, request.getInt("pid"), 16) }
        finally { Binder.restoreCallingIdentity(identity) }
        val record = records.filter { it.timestamp >= request.getLong("launchWall") }.singleOrNull()
            ?: return state("unknown", elapsed, wall)
        if (record.realUid != uid || record.packageUid != uid || record.processName != pkg ||
            record.pid != request.getInt("pid") || record.timestamp > wall || processes().isNotEmpty())
            return state("unknown", elapsed, wall)
        return state(if (record.reason == ApplicationExitInfo.REASON_EXIT_SELF && record.status == 0) "closed" else "interrupted", elapsed, wall)
    }

    private fun state(value: String, elapsed: Long, wall: Long) = Bundle().apply {
        putString("state", value); putLong("elapsed", elapsed); putLong("wall", wall)
    }
}
