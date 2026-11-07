package app.broomm.broomm

import android.app.Activity
import android.content.Intent
import android.os.Looper
import io.flutter.plugin.common.MethodChannel

private class RecordingActivity : Activity() {
    var launched: Intent? = null
    var request = -1
    @Suppress("DEPRECATION")
    override fun startActivityForResult(intent: Intent, requestCode: Int) {
        launched = intent
        request = requestCode
    }
}

private class Reply : MethodChannel.Result {
    var completions = 0
    var value: Any? = null
    var failure: String? = null
    override fun success(result: Any?) { completions++; value = result }
    override fun error(code: String, message: String?, details: Any?) { completions++; failure = code }
    override fun notImplemented() = error("unexpected", null, null)
}

fun main() {
    if (Looper.getMainLooper() == null) Looper.prepareMainLooper()
    val activity = RecordingActivity()
    var installed = true
    val uninstall = EmulatorUninstall(activity) {
        if (installed) mapOf("build" to "reviewed") else null
    }
    val cancelled = Reply()
    uninstall.request("com.retroarch.aarch64", "reviewed", cancelled)
    @Suppress("DEPRECATION")
    check(activity.launched?.action == Intent.ACTION_UNINSTALL_PACKAGE)
    check(activity.launched?.data.toString() == "package:com.retroarch.aarch64")
    check(uninstall.activityResult(activity.request))
    check(cancelled.completions == 1 && cancelled.value == false)
    val interrupted = Reply()
    uninstall.request("com.retroarch.aarch64", "reviewed", interrupted)
    val oldRequest = activity.request
    uninstall.close()
    check(interrupted.completions == 1 && interrupted.failure != null)
    val removed = Reply()
    uninstall.request("com.retroarch.aarch64", "reviewed", removed)
    val newRequest = activity.request
    check(uninstall.activityResult(oldRequest))
    check(removed.completions == 0)
    installed = false
    check(uninstall.activityResult(newRequest))
    check(removed.completions == 1 && removed.value == true)
    println("PASS: uninstall intent, cancellation readback, interrupted request and late result isolation")

    val folder = SharedSaveFolder(activity)
    val permission = ApkInstallPermission(activity)
    val picked = Reply()
    folder.pick(picked, "retroarch", "com.retroarch.aarch64")
    val pickerRequest = activity.request
    check(!uninstall.activityResult(pickerRequest))
    check(!permission.activityResult(pickerRequest))
    check(folder.activityResult(pickerRequest, Activity.RESULT_CANCELED, null))
    check(picked.completions == 1 && picked.value == null)
    folder.close()
    permission.close()
    uninstall.close()
    println("PASS: save-folder return reaches its own handler after install-permission and uninstall handlers")
}
