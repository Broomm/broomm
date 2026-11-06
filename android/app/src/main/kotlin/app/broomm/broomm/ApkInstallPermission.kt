package app.broomm.broomm

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.MethodChannel

/** The OS owns the grant. A settings Activity result is not permission evidence. */
class ApkInstallPermission(private val activity: Activity) {
    private val request = 6205
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private val timeout = Runnable {
        val result = pending
        pending = null
        result?.error("install-permission-timeout", "Install permission was not confirmed. Return to Broomm and retry Install.", null)
    }

    // Older Android versions use the package installer's legacy confirmation.
    fun allowed() = Build.VERSION.SDK_INT < 26 || activity.packageManager.canRequestPackageInstalls()

    fun request(result: MethodChannel.Result) {
        require(pending == null) { "An install-permission request is already open." }
        if (allowed()) { result.success(true); return }
        pending = result
        try {
            activity.startActivityForResult(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:${activity.packageName}")), request)
            main.postDelayed(timeout, 120000)
        } catch (e: Exception) { pending = null; throw e }
    }

    fun activityResult(code: Int): Boolean {
        if (code != request) return false
        main.removeCallbacks(timeout)
        val result = pending
        pending = null
        try { result?.success(allowed()) }
        catch (_: Exception) { result?.error("install-permission", "Android install permission could not be checked. Retry Install.", null) }
        return true
    }

    fun close() {
        main.removeCallbacks(timeout)
        pending?.error("install-permission", "Broomm closed before install permission was confirmed. Retry Install.", null)
        pending = null
    }
}
