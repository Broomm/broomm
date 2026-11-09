package app.broomm.broomm

import android.app.ActivityManager
import android.content.Context
import android.os.Binder
import android.os.Bundle
import android.os.SystemClock
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.RandomAccessFile
import java.security.MessageDigest
import java.util.zip.ZipFile
import kotlin.math.abs

/** Exact reviewed native layout. No address, opcode or guard comes from Dart.
 * Only status bytes are read; neither heap contents nor native code is copied. */
internal class RootDuckImage(private val apk: File, private val live: () -> Unit) {
    val offset: Long
    init {
        require(apk.canonicalPath == apk.path && apk.path.startsWith("/data/app/"))
        val s = Os.lstat(apk.path)
        require(OsConstants.S_ISREG(s.st_mode) && s.st_size == 112478343L) {
            "Root saves require official DuckStation beta 12126 (ARM64). Install it from the official download page, or choose shared-folder setup. Existing progress was kept."
        }
        val key = "${apk.path}:${s.st_dev}:${s.st_ino}:${s.st_size}:${s.st_mtim}:${s.st_ctim}"
        synchronized(LOCK) {
            if (verified != key) {
                val hash = MessageDigest.getInstance("SHA-256")
                apk.inputStream().use { input -> val b = ByteArray(65536); var count = 0L
                    while (true) { live(); val n = input.read(b); if (n < 0) break
                        count += n; require(count <= s.st_size); hash.update(b, 0, n) }
                    require(count == s.st_size) }
                require(hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) } == APK) {
                    "Root DuckStation saves require the reviewed Android beta 12126. Existing progress was kept."
                }
                val after = Os.lstat(apk.path)
                require(s.st_dev == after.st_dev && s.st_ino == after.st_ino && s.st_size == after.st_size &&
                    s.st_mtim == after.st_mtim && s.st_ctim == after.st_ctim)
                // The verified ZIP stores its ELF uncompressed and page-aligned.
                ZipFile(apk).use { z -> require(z.getEntry("lib/arm64-v8a/libduckstation.so").method == 0) }
                RandomAccessFile(apk, "r").use { input ->
                    var position = 0L; var found: Long? = null
                    while (position < s.st_size && found == null) {
                        input.seek(position); val h = ByteArray(30); input.readFully(h)
                        fun u16(at: Int) = (h[at].toInt() and 255) or ((h[at + 1].toInt() and 255) shl 8)
                        fun u32(at: Int) = (0..3).fold(0L) { v, i -> v or ((h[at + i].toLong() and 255) shl (8 * i)) }
                        require(u32(0) == 0x04034b50L && u16(6) and 8 == 0)
                        val name = ByteArray(u16(26)); input.readFully(name)
                        val data = position + 30 + name.size + u16(28)
                        if (String(name, Charsets.UTF_8) == "lib/arm64-v8a/libduckstation.so") {
                            require(u16(8) == 0 && u32(18) == 7577016L && data % 4096 == 0L); found = data
                        }
                        require(data + u32(18) > position && data + u32(18) <= s.st_size)
                        position = data + u32(18)
                    }
                    libraryOffset = found ?: error("Reviewed DuckStation ELF is absent.")
                }
                verified = key
            }
            offset = libraryOffset
        }
    }
    data class Snapshot(val state: Int, val pending: Long, val cards: Boolean, val addresses: LongArray, val maps: Array<String>)
    fun snapshot(pid: Int): Snapshot {
        val text = bounded(File("/proc/$pid/maps"), 1024 * 1024)
        data class Mapping(val line: String, val first: Long, val last: Long, val mode: String, val offset: Long, val path: String)
        val maps = text.lineSequence().filter { it.isNotEmpty() }.map { line ->
            val f = line.trim().split(Regex("\\s+"), limit = 6); require(f.size >= 5)
            val span = f[0].split('-'); Mapping(line, span[0].toLong(16), span[1].toLong(16), f[1], f[2].toLong(16), f.getOrElse(5) { "" })
        }.toList()
        val executable = maps.single { it.path == apk.path && it.offset == offset && it.mode == "r-xp" }
        val base = executable.first
        val addresses = longArrayOf(base + 0xa28651, base + 0xa28980, base + 0x9a5f80)
        val lengths = intArrayOf(1, 4, 64)
        val covering = addresses.indices.map { i -> maps.single {
            it.first <= addresses[i] && addresses[i] + lengths[i] <= it.last && it.mode == "rw-p"
        }.line }.plus(executable.line).distinct().toTypedArray()
        val values = RandomAccessFile("/proc/$pid/mem", "r").use { input -> addresses.indices.map { i ->
            live(); input.seek(addresses[i]); ByteArray(lengths[i]).also(input::readFully)
        } }
        val pending = (0..3).fold(0L) { n, i -> n or ((values[1][i].toLong() and 255) shl (8 * i)) }
        return Snapshot(values[0][0].toInt() and 255, pending, values[2].any { it != 0.toByte() }, addresses, covering)
    }
    companion object {
        const val APK = "3e944243fa6d201d2c2c935f1a1b104fe7e2696c6f2a6b3d719fa212660d73f7"
        private val LOCK = Any(); private var verified: String? = null; private var libraryOffset = 0L
        fun bounded(file: File, limit: Int): String = file.inputStream().use { input ->
            val bytes = ByteArrayOutputStream(); val b = ByteArray(8192)
            while (true) { val n = input.read(b); if (n < 0) break; require(bytes.size() + n <= limit); bytes.write(b, 0, n) }
            String(bytes.toByteArray(), Charsets.UTF_8)
        }
    }
}

/** Retained Java/native caches are disposed only after a frozen, exact-build
 * check of shutdown, async state completion, detached cards and writable FDs. */
internal class RootDuckProcess(private val context: Context, private val uid: Int, private val image: RootDuckImage,
    private val live: () -> Unit, private val observation: (String) -> Unit = {}) {
    private val pkg = "com.github.stenzek.duckstation"
    private fun processes(): List<Int> {
        val names = File("/proc").list() ?: error("DuckStation process inspection failed."); require(names.size <= 16384)
        return names.mapNotNull { it.toIntOrNull()?.takeIf { n -> n > 0 } }.filter { pid ->
            live()
            try {
                val owner = Os.stat("/proc/$pid").st_uid
                if (owner != uid && owner != 0) false else
                    Regex("(?m)^Uid:\\s+$uid\\s+$uid\\s+$uid\\s+$uid\\s*$").containsMatchIn(RootDuckImage.bounded(File("/proc/$pid/status"), 8192))
            } catch (e: ErrnoException) { if (e.errno in setOf(OsConstants.ENOENT, OsConstants.ESRCH)) false else throw e }
        }.also { require(it.size <= 1) { "Multiple DuckStation processes are present. Progress was kept." } }
    }
    private fun ticks(pid: Int) = RootDuckImage.bounded(File("/proc/$pid/stat"), 4096).substringAfterLast(") ").split(' ')[19].toLong()
    private fun verify(pid: Int, start: Long) {
        val name = RootDuckImage.bounded(File("/proc/$pid/cmdline"), 256).trimEnd('\u0000')
        require(name == pkg && ticks(pid) == start && processes() == listOf(pid)) { "DuckStation process identity changed. Recovery was kept." }
    }
    /** Raise only the game task of the generation Broomm launched. The
     * launcher can start a new emulation activity during recovery. */
    @Suppress("DEPRECATION")
    fun resume(request: Bundle) {
        val pid = request.getInt("pid")
        val start = request.getLong("startTicks")
        require(pid > 0 && start > 0) { "DuckStation’s game process is unavailable." }
        live(); verify(pid, start)
        val identity = Binder.clearCallingIdentity()
        try {
            val manager = context.getSystemService(ActivityManager::class.java)
            val tasks = manager.getRunningTasks(256)
            require(tasks.size < 256)
            val task = tasks.singleOrNull {
                val top = it.topActivity
                // Android reserves task IDs 0–99999 for user 0.
                it.isRunning && it.taskId in 1 until 100000 &&
                    top?.packageName == pkg && top.className == "$pkg.EmulationActivity"
            } ?: error("DuckStation’s game is no longer open. Check for exit to finish the session.")
            live(); verify(pid, start)
            manager.moveTaskToFront(task.taskId, 0)
        } finally { Binder.restoreCallingIdentity(identity) }
    }

    @Suppress("DEPRECATION") private fun emulating(): Boolean {
        val token = Binder.clearCallingIdentity()
        return try {
            val tasks = context.getSystemService(ActivityManager::class.java).getRunningTasks(256)
            require(tasks.size < 256)
            tasks.any { task -> listOf(task.baseActivity, task.topActivity, task.baseIntent.component).any {
                it?.packageName == pkg && it.className == "$pkg.EmulationActivity"
            } }
        } finally { Binder.restoreCallingIdentity(token) }
    }
    private fun command(arguments: List<String>, limit: Int): ByteArray {
        val p = ProcessBuilder(arguments).redirectErrorStream(true).start()
        try {
            p.outputStream.close(); val bytes = ByteArrayOutputStream(); val end = SystemClock.elapsedRealtime() + 1000
            while (true) {
                live(); check(SystemClock.elapsedRealtime() < end)
                while (p.inputStream.available() > 0) {
                    val b=ByteArray(minOf(8192,p.inputStream.available()));val n=p.inputStream.read(b);if(n<=0)break
                    require(bytes.size()+n<=limit);bytes.write(b,0,n)
                }
                val exit = try { p.exitValue() } catch (_: IllegalThreadStateException) { null }
                if (exit != null) {require(exit==0);return bytes.toByteArray()}
                Thread.sleep(2)
            }
        } finally { p.destroy(); p.inputStream.close() }
    }
    private fun uidState() = String(command(listOf("/system/bin/cmd","activity","get-uid-state",uid.toString()),256),Charsets.US_ASCII).trim()
    private fun background(state:String) = state in setOf("15 (LAST_ACTIVITY)","16 (CACHED_ACTIVITY)","17 (CACHED_ACTIVITY_CLIENT)","18 (CACHED_RECENT)","19 (CACHED_EMPTY)")
    private fun paused(request:Bundle,pid:Int,start:Long):Boolean {
        val elapsed=SystemClock.elapsedRealtime();val wall=System.currentTimeMillis()
        val after=request.getLong("pauseWall",-1);val since=request.getLong("pauseElapsed",-1)
        if (after<=0 || since<=0) return false
        require(since<=elapsed && after<=wall && abs(wall-after-(elapsed-since))<=100)
        val bytes=command(listOf("/system/bin/logcat","-B","-b","events","-d","--pid=$pid","--uid=$uid","-t","1000"),DuckPauseProof.MAX_BYTES)
        val now=System.currentTimeMillis();val tick=SystemClock.elapsedRealtime()
        require(abs(now-wall-(tick-elapsed))<=100);verify(pid,start)
        return DuckPauseProof.completed(bytes,pid,uid,after,now)
    }
    fun absent() { check(processes().isEmpty()) { "DuckStation is still present. Close its game and return to Broomm before retrying." } }
    fun observe(request: Bundle = Bundle(), dispose: Boolean = false): Bundle {
        live(); val found = processes()
        fun result(state: String) = Bundle().apply { putString("state", state); putLong("elapsed", SystemClock.elapsedRealtime()); putLong("wall", System.currentTimeMillis()) }
        if (found.isEmpty()) return result(if (request.containsKey("pid")) "interrupted" else "idle")
        val pid = found.single(); val start = ticks(pid); verify(pid, start)
        if (!request.containsKey("pid") && request.containsKey("launchElapsed")) {
            val launched = request.getLong("launchElapsed"); val rate = Os.sysconf(OsConstants._SC_CLK_TCK)
            require(rate in 1..10000 && launched in 1..SystemClock.elapsedRealtime())
            if (start * 1000 / rate + 100 < launched) return result("unknown")
        }
        if (request.containsKey("pid") && (request.getInt("pid") != pid || request.getLong("startTicks") != start))
            return result("unknown")
        val status = image.snapshot(pid)
        verify(pid, start)
        observation("state=${status.state} pending=${status.pending} cards=${status.cards}")
        fun identified(state: String) = result(state).apply { putInt("pid", pid); putLong("startTicks", start) }
        if (status.state in 2..3) return identified("running")
        // A return to Broomm can precede teardown or Android's task/UID update.
        // This is only a wait hint for the exact launched generation.
        val expected = request.containsKey("pid") && !dispose
        if (expected && (status.state == 4 || status.state == 0 && status.pending != 0L))
            return identified("settling")
        if (status.state != 0 || status.pending != 0L || status.cards) return result("unknown")
        val activity = emulating(); val androidState = uidState()
        val background = background(androidState)
        observation("emulationActivity=$activity cached=$background")
        if (activity || !background) return when {
            !activity && androidState == "2 (TOP)" -> identified("menu")
            expected -> identified("settling")
            else -> result("unknown")
        }
        if (!dispose) return result("quiescent").apply { putInt("pid", pid); putLong("startTicks", start); putBoolean("paused",paused(request,pid,start)) }
        require(request.containsKey("pid")) { "Verify DuckStation’s cached process before closing it." }
        verify(pid, start); RootProcessKernel.load(context)
        val stopped = RootProcessKernel.stopIdle(pid, start, status.addresses, intArrayOf(1, 4, 64), status.maps,
            arrayOf("/data/media/0/Android/data/$pkg/", "/storage/emulated/0/Android/data/$pkg/",
                "/data/user/0/$pkg/files/", "/data/data/$pkg/files/"), RootProcessGuard {
                    live(); verify(pid,start)
                    background(uidState()) && !emulating() && paused(request,pid,start)
                })
        require(stopped == 0) { "DuckStation has an active writer or its shutdown could not be verified (native $stopped). Progress was kept." }
        absent()
        return result(if (request.containsKey("pid")) "closed" else "idle")
    }
    fun ensureClosed() = absent()
}
