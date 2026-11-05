package app.broomm.broomm

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.Process
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.security.MessageDigest
import java.util.concurrent.Executors

/** Package inspection only; never registers a save binding or touches progress. */
class RootInspection(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private var channel: MethodChannel? = null
    private var active: Pair<String, RootInspectionCommand>? = null

    fun register(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, "app.broomm/root-inspection").also { c ->
            c.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "cancel" -> {
                            if (active?.first == call.argument<String>("request")) active?.second?.cancel()
                            result.success(null)
                        }
                        "inspect" -> {
                            require(active == null) { "A root inspection is already active." }
                            val request = call.argument<String>("request") ?: error("Missing request identity")
                            require(Regex("[0-9]{1,24}").matches(request))
                            val pkg = call.argument<String>("package") ?: error("Missing package")
                            require(pkg in activities) { "Unsupported emulator package." }
                            val build = call.argument<String>("build") ?: error("Missing build identity")
                            require(Regex("[a-f0-9]{64}").matches(build))
                            val command = RootInspectionCommand()
                            active = request to command
                            worker.execute {
                                try {
                                    val before = identity(pkg)
                                    require(before["build"] == build) { "Emulator changed. Refresh installed apps before inspecting." }
                                    val metadata = command.inspect(pkg, before["uid"] as Int, before["user"] as Int, before["dataDir"] as String)
                                    require(identity(pkg) == before) { "Emulator changed during inspection. Refresh and retry." }
                                    val report = before + metadata + mapOf("device" to "${Build.MANUFACTURER} ${Build.MODEL}",
                                        "android" to Build.VERSION.RELEASE, "sdk" to Build.VERSION.SDK_INT, "abis" to Build.SUPPORTED_ABIS.toList())
                                    main.post { active = null; result.success(report) }
                                } catch (e: Exception) {
                                    main.post { active = null; result.error((e as? RootInspectionFailure)?.code ?: "inspection-failed",
                                        if (e is IllegalArgumentException || e is RootInspectionFailure) e.message else "Root inspection failed. Refresh installed apps and retry.", null) }
                                }
                            }
                        }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) { result.error("inspection-failed", e.message, null) }
            }
        }
    }

    @Suppress("DEPRECATION")
    private fun identity(pkg: String): Map<String, Any> {
        val pm = activity.packageManager
        val info = pm.getPackageInfo(pkg, if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES)
        val app = info.applicationInfo ?: error("Missing emulator identity")
        require(app.enabled && info.sharedUserId == null) { "Disabled or shared-UID emulator packages are unsupported for root inspection." }
        val launcher = pm.getActivityInfo(ComponentName(pkg, activities.getValue(pkg)), 0)
        require(launcher.exported && launcher.enabled && launcher.applicationInfo.uid == app.uid) { "The expected emulator launcher is unavailable." }
        val user = Process.myUid() / 100000
        require(app.uid / 100000 == user) { "Emulator belongs to another Android user." }
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        require(!signatures.isNullOrEmpty()) { "Emulator signing identity is unavailable." }
        val digest = MessageDigest.getInstance("SHA-256")
        for (signature in signatures.sortedBy { it.toCharsString() }) digest.update(signature.toByteArray())
        val signer = digest.digest().hex()
        for (signature in signatures.sortedBy { it.toCharsString() }) digest.update(signature.toByteArray())
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode.toString() else info.versionCode.toString()
        // Same package observation used by the existing launch boundary.
        digest.update(("$pkg:$code:${info.versionName}:${info.lastUpdateTime}:${Build.SUPPORTED_ABIS.joinToString(",")}").toByteArray(Charsets.UTF_8))
        return mapOf("package" to pkg, "version" to (info.versionName ?: code), "build" to digest.digest().hex(),
            "signer" to signer, "user" to user, "uid" to app.uid, "dataDir" to app.dataDir)
    }

    fun close() {
        active?.second?.cancel()
        channel?.setMethodCallHandler(null)
        channel = null
        worker.shutdown()
    }

    companion object {
        private fun ByteArray.hex() = joinToString("") { "%02x".format(it.toInt() and 255) }
        private val activities = mapOf(
            "com.retroarch.aarch64" to "com.retroarch.browser.retroactivity.RetroActivityFuture",
            "com.retroarch" to "com.retroarch.browser.retroactivity.RetroActivityFuture",
            "com.retroarch.ra32" to "com.retroarch.browser.retroactivity.RetroActivityFuture",
            "org.ppsspp.ppsspp" to "org.ppsspp.ppsspp.PpssppActivity",
            "org.ppsspp.ppssppgold" to "org.ppsspp.ppsspp.PpssppActivity",
            "me.magnum.melonds" to "me.magnum.melonds.ui.emulator.EmulatorActivity",
            "org.azahar_emu.azahar" to "org.citra.citra_emu.activities.EmulationActivity",
            "org.citra.emu" to "org.citra.emu.ui.EmulationActivity",
            "com.antutu.ABenchMark" to "org.citra.emu.ui.EmulationActivity",
            "org.dolphinemu.dolphinemu" to "org.dolphinemu.dolphinemu.ui.main.MainActivity",
            "dev.eden.eden_emulator" to "org.yuzu.yuzu_emu.activities.EmulationActivity",
            "com.armsx2" to "com.armsx2.MainActivity",
            "com.armsx2.nightly" to "com.armsx2.MainActivity",
            "com.github.stenzek.duckstation" to "com.github.stenzek.duckstation.EmulationActivity",
        )
    }
}
