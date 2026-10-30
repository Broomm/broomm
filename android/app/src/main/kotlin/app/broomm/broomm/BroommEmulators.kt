package app.broomm.broomm

import android.app.Activity
import android.content.ClipData
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.DocumentsContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.security.MessageDigest
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicReference
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor

/** Android mechanisms only. Emulator selection and session/save rules live in Dart. */
class BroommEmulators(private val activity: Activity) {
    private val channelName = "app.broomm/emulators"
    private var channel: MethodChannel? = null
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var pending: MethodChannel.Result? = null
    private var apkPackages: List<String>? = null
    private var apkActivity: String? = null
    private val apkPicker = 6202
    private val gameRequest = 6203
    private val installRequest = 6204
    private var installingApk: Pair<String, File>? = null
    private val sharedFolder = SharedSaveFolder(activity)
    fun register(engine: FlutterEngine) {
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, channelName).also { c ->
            c.setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "aesEcb" -> background(result) {
                            val bytes = call.argument<ByteArray>("bytes")!!; val key = call.argument<ByteArray>("key")!!
                            require(key.size == 16 && bytes.isNotEmpty() && bytes.size % 16 == 0 && bytes.size <= 65536)
                            val cipher = javax.crypto.Cipher.getInstance("AES/ECB/NoPadding")
                            cipher.init(if (call.argument<Boolean>("decrypt") == true) javax.crypto.Cipher.DECRYPT_MODE else javax.crypto.Cipher.ENCRYPT_MODE,
                                javax.crypto.spec.SecretKeySpec(key, "AES"))
                            cipher.doFinal(bytes)
                        }
                        "device" -> result.success(mapOf("abis" to Build.SUPPORTED_ABIS.toList(), "sdk" to Build.VERSION.SDK_INT))
                        "installDownloadedApk" -> {
                            val expected = packages(call.argument<List<String>>("packages"))
                            val apk = File(call.argument<String>("path") ?: error("Missing downloaded APK"))
                            val base = File(activity.filesDir, "android/apks")
                            require(apk.parentFile?.canonicalFile == base.canonicalFile && apk.canonicalPath == apk.absolutePath &&
                                Regex("[a-f0-9]{32}\\.apk").matches(apk.name) && apk.isFile && apk.length() in 1..1024L*1024*1024) { "Invalid downloaded APK" }
                            openInstaller(apk, expected, call.argument<String>("requiredActivity"), result)
                        }
                        "installed" -> background(result) {
                            val required = call.argument<Map<String, String>>("requiredActivities") ?: emptyMap()
                            packages(call.argument<List<String>>("packages")).mapNotNull { pkg ->
                                val expected = required[pkg]
                                val matches = expected == null || try {
                                    activity.packageManager.getActivityInfo(ComponentName(pkg, expected), PackageManager.MATCH_DISABLED_COMPONENTS).exported
                                } catch (_: PackageManager.NameNotFoundException) { false }
                                if (matches) app(pkg) else null
                            }
                        }
                        "installPage" -> {
                            val url = Uri.parse(call.argument<String>("url")!!)
                            require(url.scheme == "https" && url.host in setOf("www.ppsspp.org", "github.com", "azahar-emu.org", "dolphin-emu.org", "git.eden-emu.dev", "www.retroarch.com", "play.google.com"))
                            activity.startActivity(Intent(Intent.ACTION_VIEW, url))
                            result.success(null)
                        }
                        "installApk" -> {
                            require(pending == null) { "A file picker is already open" }
                            apkPackages = packages(call.argument<List<String>>("packages"))
                            apkActivity = call.argument<String>("requiredActivity")
                            pending = result
                            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/vnd.android.package-archive"
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }, apkPicker)
                        }
                        "open" -> {
                            val pkg = packageName(call.argument<String>("package"))
                            val intent = activity.packageManager.getLaunchIntentForPackage(pkg)
                                ?: throw IllegalStateException("Emulator is unavailable. Refresh installation status.")
                            activity.startActivity(intent)
                            result.success(null)
                        }
                        "dataRoot" -> {
                            val profile = call.argument<String>("profile")!!
                            val emulator = call.argument<String>("emulator")!!
                            require(Regex("[a-f0-9]{32}").matches(profile) && emulator in setOf("ppsspp", "melonds", "azahar"))
                            val root = File(activity.filesDir, "profiles/$profile/emulators/$emulator/user")
                            require(root.canonicalPath == root.absolutePath && root.isDirectory)
                            val label = call.argument<String>("label")!!
                            require(label.length in 1..160 && label.none { it.code < 32 })
                            val id = "$profile:$emulator"
                            check(activity.getSharedPreferences("emulator-roots", 0).edit().putString(id,
                                JSONObject().put("path", root.path).put("label", label).toString()).commit())
                            val uri = DocumentsContract.buildTreeDocumentUri("${activity.packageName}.emulator-data", id)
                            activity.contentResolver.notifyChange(DocumentsContract.buildRootsUri("${activity.packageName}.emulator-data"), null)
                            result.success(uri.toString())
                        }
                        "fingerprint" -> background(result) {
                            val pkg = packageName(call.argument<String>("package"))
                            val before = app(pkg) ?: error("Emulator is no longer installed")
                            val info = activity.packageManager.getApplicationInfo(pkg, 0)
                            val digest = MessageDigest.getInstance("SHA-256")
                            // Installation time invalidates the cache/launch observation,
                            // but must not fork state compatibility for identical APKs on
                            // two devices (or an unchanged reinstall).
                            digest.update("$pkg:${Build.SUPPORTED_ABIS.firstOrNull() ?: "unknown"}".toByteArray(Charsets.UTF_8))
                            var total = 0L
                            for (path in listOf(info.sourceDir) + (info.splitSourceDirs?.sorted() ?: emptyList())) {
                                File(path).inputStream().use { input ->
                                    val bytes = ByteArray(131072)
                                    while (true) { val n = input.read(bytes); if (n < 0) break
                                        total += n; require(total <= 2L * 1024 * 1024 * 1024); digest.update(bytes, 0, n) }
                                }
                            }
                            require(app(pkg) == before) { "Emulator changed while checking its build" }
                            digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
                        }
                        "launch" -> {
                            val pkg = packageName(call.argument<String>("package"))
                            val currentApp = app(pkg)
                            require(currentApp?.get("build") == call.argument<String>("build") && currentApp?.get("enabled") == "true") { "Emulator changed or is disabled. Refresh status before launching." }
                            val files = call.argument<List<String>>("files") ?: error("Missing game manifest")
                            val selected = call.argument<String>("selected") ?: error("Missing game selection")
                            require(files.size in 1..10000 && files.toSet().size == files.size && files.contains(selected))
                            val base = File(activity.filesDir, "library").canonicalPath + File.separator
                            for (path in files) {
                                val f = File(path)
                                require(f.isFile && f.canonicalPath == f.absolutePath && f.canonicalPath.startsWith(base)) { "Game file is missing or outside the library" }
                            }
                            val content = Regex("^" + Regex.escape(base) + "[a-f0-9]{32}/[1-9][0-9]*/content/").find(selected)?.value?.removeSuffix("/")
                                ?: error("Game has no owned content directory")
                            require(files.all { it.startsWith("$content/") }) { "Game files belong to different installations" }
                            val token = UUID.randomUUID().toString().replace("-", "")
                            val activeRoot = call.argument<String>("root")
                            require(activeRoot == null || Regex("[a-f0-9]{32}:(ppsspp|melonds|azahar)").matches(activeRoot))
                            check(activity.getSharedPreferences("game-grants", 0).edit()
                                .putString(token, JSONObject().put("files", JSONArray(files)).put("base", content).toString())
                                .putString("active-root", activeRoot).commit())
                            val uris = files.map { path -> Uri.Builder().scheme("content").authority("${activity.packageName}.games")
                                .appendPath("game").appendPath(token).also { builder ->
                                    for (part in path.removePrefix("$content/").split('/')) builder.appendPath(part)
                                }.build() }
                            val uri = uris[files.indexOf(selected)]
                            val target = call.argument<String>("activity") ?: error("Missing emulator activity")
                            require(Regex("[A-Za-z][A-Za-z0-9_.]+[A-Za-z0-9]").matches(target))
                            val action = call.argument<String>("action") ?: error("Missing emulator action")
                            require(action in setOf(Intent.ACTION_VIEW, Intent.ACTION_MAIN, "me.magnum.melonds.LAUNCH_ROM"))
                            val intent = Intent(action).apply {
                                component = ComponentName(pkg, target)
                                setDataAndType(uri, "application/octet-stream")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                // Dolphin treats every ClipData item as a disc.
                                // Related files get separate grants, not fake discs.
                                clipData = ClipData.newRawUri("Game", uri)
                                when (call.argument<String>("emulator")) {
                                    "melonds" -> putExtra("uri", uri)
                                    "azahar" -> { putExtra("SelectedGame", uri.toString()); putExtra("launchedFromShortcut", true) }
                                    "citra-mmj" -> putExtra("GamePath", uri.toString())
                                    "dolphin" -> putExtra("AutoStartFile", uri.toString())
                                    "duckstation" -> { putExtra("bootPath", uri.toString()); putExtra("resumeState", false) }
                                    "retroarch" -> {
                                        val core = call.argument<String>("core") ?: error("Select a RetroArch core first")
                                        require(Regex("[a-z][a-z0-9_]{0,63}").matches(core))
                                        val nativeData = activity.packageManager.getApplicationInfo(pkg, 0).dataDir
                                        putExtra("ROM", uri.toString())
                                        putExtra("LIBRETRO", "$nativeData/cores/${core}_libretro_android.so")
                                        call.argument<String>("configuration")?.let { config ->
                                            val allowed = listOf("$nativeData/files/Broomm/", "/data/data/$pkg/files/Broomm/")
                                            require(allowed.any { config.startsWith(it) } && config.endsWith(".cfg") &&
                                                config.split('/').none { it == "." || it == ".." || '\\' in it || '\u0000' in it }) { "Invalid RetroArch session configuration" }
                                            putExtra("CONFIGFILE", config)
                                        }
                                    }
                                }
                            }
                            try {
                                val info = activity.packageManager.getActivityInfo(intent.component!!, 0)
                                require(info.exported && info.enabled) { "This emulator version does not export its game launcher" }
                                for (other in uris) activity.grantUriPermission(pkg, other, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                activity.startActivityForResult(intent, gameRequest)
                            } catch (e: Exception) {
                                for (other in uris) activity.revokeUriPermission(other, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                                activity.getSharedPreferences("game-grants", 0).edit().remove(token).commit()
                                throw e
                            }
                            result.success(token)
                        }
                        "releaseGrants" -> {
                            val prefs = activity.getSharedPreferences("game-grants", 0)
                            for (token in prefs.all.keys) {
                                if (!Regex("[a-f0-9]{32}").matches(token)) continue
                                val root = Uri.parse("content://${activity.packageName}.games/game/$token")
                                activity.revokeUriPermission(root, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            check(prefs.edit().clear().commit())
                            result.success(null)
                        }
                        "writers" -> result.success(EmulatorDocumentsProvider.writers.get() + if (sharedFolder.busy()) 1 else 0)
                        "ioBusy" -> result.success(sharedFolder.busy())
                        "sharedPick" -> sharedFolder.pick(result, call.argument<String>("emulator"), call.argument<String>("package"))
                        "sharedCheck", "sharedList", "sharedRead", "sharedReplace", "sharedBytes", "sharedChildren", "sharedStat" ->
                            background(result) { sharedFolder.operation(call) }
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    if (pending === result) { pending = null; apkPackages = null; apkActivity = null }
                    result.error("android-emulator", e.message ?: "Android operation failed", null)
                }
            }
        }
    }
    private fun packageName(value: String?): String {
        require(value != null && value.length < 160 && Regex("[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+").matches(value))
        return value
    }
    private fun packages(values: List<String>?): List<String> {
        require(values != null && values.size in 1..32)
        return values.map { packageName(it) }.distinct()
    }
    private fun openInstaller(apk: File, expected: List<String>, expectedActivity: String?, result: MethodChannel.Result) {
        require(installingApk == null) { "An Android package installer is already active" }
        val info = activity.packageManager.getPackageArchiveInfo(apk.path, PackageManager.GET_ACTIVITIES) ?: error("Invalid emulator APK")
        require(info.packageName in expected) { "The APK is for a different emulator" }
        require(expectedActivity == null || info.activities?.any { it.name == expectedActivity && it.exported } == true) { "The APK does not export the emulator launcher" }
        if (Build.VERSION.SDK_INT >= 24) require(info.applicationInfo?.minSdkVersion?.let { it <= Build.VERSION.SDK_INT } == true) { "This emulator APK requires a newer Android version" }
        // Upgrades must retain their signing identity; Android verifies APK signatures
        // and asks for permission/confirmation. Never uninstall to bypass rejection.
        val token = UUID.randomUUID().toString().replace("-", "")
        check(activity.getSharedPreferences("apk-grants", 0).edit().putString(token, apk.path).commit())
        val grant = Uri.parse("content://${activity.packageName}.apks/$token")
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(grant, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                clipData = ClipData.newRawUri("Emulator APK", grant)
                putExtra(Intent.EXTRA_RETURN_RESULT, true)
            }, installRequest)
            installingApk = token to apk
            result.success(null)
        } catch (e: Exception) {
            activity.getSharedPreferences("apk-grants", 0).edit().remove(token).commit()
            throw e
        }
    }
    @Suppress("DEPRECATION")
    private fun app(pkg: String): Map<String, String>? {
        val info = try {
            activity.packageManager.getPackageInfo(pkg, if (Build.VERSION.SDK_INT >= 28) PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES)
        } catch (_: PackageManager.NameNotFoundException) { return null }
        val enabled = info.applicationInfo?.enabled ?: error("Android did not provide emulator application status")
        val signatures = if (Build.VERSION.SDK_INT >= 28) info.signingInfo?.apkContentsSigners else info.signatures
        require(!signatures.isNullOrEmpty()) { "Emulator signing identity is unavailable" }
        val digest = MessageDigest.getInstance("SHA-256")
        for (s in signatures.sortedBy { it.toCharsString() }) digest.update(s.toByteArray())
        val code = if (Build.VERSION.SDK_INT >= 28) info.longVersionCode.toString() else info.versionCode.toString()
        digest.update(("$pkg:$code:${info.versionName}:${info.lastUpdateTime}:${Build.SUPPORTED_ABIS.joinToString(",")}").toByteArray(Charsets.UTF_8))
        return mapOf("package" to pkg, "version" to (info.versionName ?: code), "enabled" to enabled.toString(),
            "build" to digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) })
    }
    private fun background(result: MethodChannel.Result, work: () -> Any?) {
        worker.execute { try {
            val value = work(); main.post { result.success(value) }
        } catch (e: Exception) { main.post { result.error("android-emulator", e.message ?: "Android operation failed", null) } } }
    }
    @Suppress("DEPRECATION")
    fun activityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (sharedFolder.activityResult(request, code, data)) return true
        if (request == gameRequest) {
            // Activity return is deliberately not called "game stopped": some
            // emulator launchers bounce immediately or keep background writers.
            channel?.invokeMethod("returned", null)
            return true
        }
        if (request == installRequest) {
            installingApk?.let { (token, file) ->
                activity.revokeUriPermission(Uri.parse("content://${activity.packageName}.apks/$token"), Intent.FLAG_GRANT_READ_URI_PERMISSION)
                activity.getSharedPreferences("apk-grants", 0).edit().remove(token).commit()
                file.delete()
            }
            installingApk = null
            channel?.invokeMethod("installationChanged", mapOf("installed" to (code == Activity.RESULT_OK)))
            return true
        }
        if (request != apkPicker) return false
        val result = pending ?: return true
        pending = null
        val expected = apkPackages; apkPackages = null
        val expectedActivity = apkActivity; apkActivity = null
        if (code != Activity.RESULT_OK || data?.data == null) { result.success(null); return true }
        val uri = data.data!!
        // The system installer performs signature/permission confirmation.
        // Broomm never installs packages silently or modifies other apps.
        worker.execute {
            try {
                val dir = File(activity.cacheDir, "install-apk").apply { mkdirs() }
                val cached = dir.listFiles() ?: error("Installer cache cannot be read")
                require(cached.size < 16 && cached.sumOf { it.length() } < 1024L * 1024 * 1024) { "Installer cache is full. Clear Broomm's cache in Android storage settings." }
                val apk = File.createTempFile("emulator-", ".apk", dir)
                try {
                    val cancel = CancellationSignal()
                    val descriptor = AtomicReference<ParcelFileDescriptor?>()
                    val timeout = Runnable { cancel.cancel(); try { descriptor.get()?.close() } catch (_: Exception) {} }
                    main.postDelayed(timeout, 60000)
                    var total = 0L
                    try {
                    val fd = activity.contentResolver.openFileDescriptor(uri, "r", cancel) ?: error("APK cannot be opened")
                    descriptor.set(fd)
                    ParcelFileDescriptor.AutoCloseInputStream(fd).use { input -> apk.outputStream().use { out ->
                        val bytes = ByteArray(131072)
                        while (true) { val n = input.read(bytes); if (n < 0) break
                            total += n; require(total <= 1024L * 1024 * 1024) { "APK exceeds the installation size limit" }; out.write(bytes, 0, n) }
                        out.fd.sync()
                    } }
                    cancel.throwIfCanceled()
                    } finally { main.removeCallbacks(timeout); descriptor.getAndSet(null)?.close() }
                    val info = activity.packageManager.getPackageArchiveInfo(apk.path, PackageManager.GET_ACTIVITIES) ?: error("Invalid APK")
                    require(expectedActivity == null || info.activities?.any { it.name == expectedActivity && it.exported } == true) { "This APK does not contain the selected emulator's launch activity" }
                    require(expected != null && info.packageName in expected) { "APK is for a different emulator" }
                    // Give the system installer a one-file, read-only capability.
                    val token = UUID.randomUUID().toString().replace("-", "")
                    // Installer grants have a separate provider namespace.
                    check(activity.getSharedPreferences("apk-grants", 0).edit().putString(token, apk.path).commit())
                    val grant = Uri.parse("content://${activity.packageName}.apks/$token")
                    main.post { try {
                        require(!activity.isFinishing && !activity.isDestroyed) { "Android activity was closed. Retry installation." }
                        require(installingApk == null) { "An Android package installer is already active" }
                        activity.startActivityForResult(Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(grant, "application/vnd.android.package-archive")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            clipData = ClipData.newRawUri("Emulator APK", grant)
                            putExtra(Intent.EXTRA_RETURN_RESULT, true)
                        }, installRequest)
                        installingApk = token to apk
                        result.success(null)
                    } catch (e: Exception) {
                        activity.getSharedPreferences("apk-grants", 0).edit().remove(token).commit()
                        apk.delete()
                        result.error("android-install", e.message ?: "Android could not open the package installer", null)
                    } }
                } catch (e: Exception) { apk.delete(); throw e }
            } catch (e: Exception) { main.post { result.error("android-install", e.message ?: "APK could not be read", null) } }
        }
        return true
    }
    fun close() {
        sharedFolder.close()
        pending?.error("android-activity", "The Android activity was closed. Retry the operation.", null)
        pending = null; channel?.setMethodCallHandler(null); channel = null; worker.shutdown()
    }
}
