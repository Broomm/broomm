package app.broomm.broomm

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

/** User-confirmed package removal with fresh package readback. */
internal class EmulatorUninstall(
    private val activity: Activity,
    private val current: (String) -> Map<String, String>?,
) {
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var target: String? = null
    private var nextRequest = 6400
    private var pendingRequest: Int? = null
    private val timeout = Runnable {
        finish(error = "Android uninstall confirmation timed out. Return to Broomm and finish removal.")
    }

    @Suppress("DEPRECATION")
    fun request(packageName: String, build: String, result: MethodChannel.Result) {
        require(pending == null) { "An emulator uninstall is already active." }
        check(nextRequest < 6500) { "Reopen Broomm before starting another uninstall." }
        require(current(packageName)?.get("build") == build) { "The emulator changed. Refresh and retry removal." }
        val request = nextRequest++
        activity.startActivityForResult(Intent(Intent.ACTION_UNINSTALL_PACKAGE,
            Uri.fromParts("package", packageName, null)).apply {
            putExtra(Intent.EXTRA_RETURN_RESULT, true)
        }, request)
        target = packageName
        pendingRequest = request
        pending = result
        main.postDelayed(timeout, 120000)
    }

    fun activityResult(request: Int): Boolean {
        if (request !in 6400 until nextRequest) return false
        if (request != pendingRequest) return true
        val pkg = target ?: return true
        try {
            finish(removed = current(pkg) == null)
        } catch (e: Exception) {
            finish(error = "Android package removal could not be verified. Retry removal.")
        }
        return true
    }

    private fun finish(removed: Boolean = false, error: String? = null) {
        val result = pending ?: return
        pending = null
        target = null
        pendingRequest = null
        main.removeCallbacks(timeout)
        if (error == null) result.success(removed)
        else result.error("android-uninstall", error, null)
    }

    fun close() = finish(error = "Broomm closed during uninstall. Reopen it and finish removal.")

}
