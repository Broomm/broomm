package app.broomm.broomm

import android.content.Context
import android.os.Bundle
import android.os.Looper
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import java.io.File

/** Explicit device fixture; never included in the application. Read-only by
 * default. `dispose` exercises only the fixed reviewed DuckStation idle cache. */
fun main(args: Array<String>) {
    try { inspect(args) } catch (e: Throwable) { e.printStackTrace(System.out); kotlin.system.exitProcess(2) }
}
private fun inspect(args: Array<String>) {
    Looper.prepareMainLooper()
    require(args.size == 2 && args[0] in setOf("inspect", "dispose"))
    val thread = Class.forName("android.app.ActivityThread").getMethod("systemMain").invoke(null)
    val context = thread.javaClass.getMethod("getSystemContext").invoke(thread) as Context
    val pkg = "com.github.stenzek.duckstation"
    val app = context.packageManager.getApplicationInfo(pkg, 0)
    require(app.uid in 10000..99999 && File(args[1]).canonicalPath == args[1] && args[1] == "/data/local/tmp/libbroomm_root_process.so")
    System.load(args[1])
    RootProcessKernel::class.java.getDeclaredField("loaded").apply { isAccessible = true }.setBoolean(null, true)
    val process = RootDuckProcess(context, app.uid, RootDuckImage(File(app.sourceDir)) {}, {}, ::println)
    val before = process.observe()
    val result = if (args[0] == "dispose") process.observe(Bundle().apply {
        putInt("pid", before.getInt("pid")); putLong("startTicks", before.getLong("startTicks"))
        val began=before.getLong("startTicks")*1000/Os.sysconf(OsConstants._SC_CLK_TCK)
        putLong("pauseElapsed",began);putLong("pauseWall",System.currentTimeMillis()-(SystemClock.elapsedRealtime()-began))
    }, dispose = true) else before
    println("state=${result.getString("state")} pid=${result.getInt("pid")} ticks=${result.getLong("startTicks")}")
}
