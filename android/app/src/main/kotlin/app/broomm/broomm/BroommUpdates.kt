package app.broomm.broomm

import android.content.ClipData
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors

/** Only platform package inspection and user-confirmed OS installation live here. */
class BroommUpdates(private val activity: MainActivity) {
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var grant: String? = null
    private val request = 6301
    private val root get() = File(activity.cacheDir, "application-updates")
    fun register(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "app.broomm/updates").also { c ->
            c.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "cacheDirectory" -> { check(root.isDirectory || root.mkdirs()); result.success(root.absolutePath) }
                        "install" -> {
                            require(grant == null) { "An update installer is already open" }
                            val apk = File(call.argument<String>("path") ?: error("Update path is missing"))
                            require(apk.isFile && apk.canonicalPath == apk.absolutePath &&
                                apk.parentFile?.parentFile?.canonicalFile == root.canonicalFile &&
                                apk.parentFile!!.name.startsWith(".broomm-update-") &&
                                Regex("Broomm-[0-9]+\\.[0-9]+\\.[0-9]+(-rc[0-9]+)?-android-universal\\.apk").matches(apk.name)) { "Invalid update file" }
                            if (Build.VERSION.SDK_INT >= 26 && !activity.packageManager.canRequestPackageInstalls()) {
                                activity.startActivity(Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${activity.packageName}")))
                                result.success(false)
                            } else worker.execute {
                                try {
                                    val pm = activity.packageManager
                                    val info = pm.getPackageArchiveInfo(apk.path, 0) ?: error("Invalid update APK")
                                    val installed = pm.getPackageInfo(activity.packageName, 0)
                                    val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else info.versionCode.toLong()
                                    val old = if (Build.VERSION.SDK_INT >= 28) installed.longVersionCode else installed.versionCode.toLong()
                                    require(info.packageName == activity.packageName && code > old) { "Update package or version does not match Broomm" }
                                    // Android verifies the retained signing key and package identity.
                                    main.post {
                                        try {
                                            require(!activity.isFinishing && !activity.isDestroyed && grant == null)
                                            val token = UUID.randomUUID().toString().replace("-", "")
                                            check(activity.getSharedPreferences("apk-grants", 0).edit().putString(token, apk.path).commit())
                                            grant = token
                                            val uri = Uri.parse("content://${activity.packageName}.apks/$token")
                                            activity.startActivityForResult(Intent(Intent.ACTION_VIEW).apply {
                                                setDataAndType(uri, "application/vnd.android.package-archive")
                                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                                clipData = ClipData.newRawUri("Broomm update", uri)
                                                putExtra(Intent.EXTRA_RETURN_RESULT, true)
                                            }, request)
                                            result.success(true)
                                        } catch (e: Exception) { clearGrant(); result.error("update-install", e.message, null) }
                                    }
                                } catch (e: Exception) { main.post { result.error("update-install", e.message, null) } }
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("update-install", e.message, null) }
            }
        }
    }
    fun activityResult(code: Int): Boolean {
        if (code != request) return false
        clearGrant()
        channel?.invokeMethod("installerReturned", null)
        return true
    }
    private fun clearGrant() {
        grant?.let { activity.getSharedPreferences("apk-grants", 0).edit().remove(it).commit() }
        grant = null
    }
    fun close() { channel?.setMethodCallHandler(null); channel = null; worker.shutdown() }
}
