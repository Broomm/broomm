package app.broomm.broomm

import android.os.Binder
import android.os.Bundle
import android.os.IBinder
import android.os.Parcel
import android.os.ParcelFileDescriptor
import android.os.Process
import android.os.SystemClock
import android.content.Intent
import android.system.Os
import android.system.OsConstants
import com.topjohnwu.superuser.ipc.RootService
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest

/** Verified package file operations and read-only RetroArch process evidence. */
class RootSaveService : RootService() {
    private val binder = object : Binder() {
        override fun onTransact(code: Int, data: Parcel, reply: Parcel?, flags: Int): Boolean {
            if (code != REQUEST || reply == null) return super.onTransact(code, data, reply, flags)
            data.enforceInterface(DESCRIPTOR)
            val caller = Binder.getCallingUid()
            require(caller == packageManager.getApplicationInfo(packageName, 0).uid)
            val request = data.readBundle(javaClass.classLoader) ?: error("Missing root request")
            val result = try { operation(request, caller, Binder.getCallingPid()) }
            catch (e: Exception) { Bundle().apply { putString("error", e.message?.take(300) ?: "Root file operation failed. Recovery was kept.") } }
            finally { request.getParcelable<ParcelFileDescriptor>("transfer")?.close() }
            reply.writeNoException(); reply.writeBundle(result)
            return true
        }
    }
    override fun onBind(intent: Intent): IBinder = binder

    private fun operation(request: Bundle, caller: Int, callerPid: Int): Bundle {
        require(Process.myUid() == 0 && caller / 100000 == 0) { "The first root save route requires Android user 0." }
        val deadline = request.getLong("deadline")
        fun live() { check(SystemClock.elapsedRealtime() <= deadline) { "Root operation expired. Recovery was kept." } }
        live()
        val pkg = request.getString("package")!!
        val psp = request.getString("operation")?.startsWith("psp") == true
        val duck = request.getString("operation")?.startsWith("duck") == true
        val melon = request.getString("operation")?.startsWith("melon") == true
        require(if (melon) pkg == MELON_PACKAGE else if (duck) pkg == "com.github.stenzek.duckstation" else if (psp) pkg == "org.ppsspp.ppsspp" else pkg in setOf("com.retroarch.aarch64", "com.retroarch", "com.retroarch.ra32"))
        val before = RootInspection.identity(this, pkg, 0)
        for (key in listOf("build", "signer", "uid", "user", "dataDir"))
            require(before[key].toString() == request.getString(key)) { "Emulator identity changed. Reconnect after finishing recovery." }
        val root = File(before["dataDir"] as String).canonicalFile
        require(root.path == "/data/user/0/$pkg" || root.path == "/data/data/$pkg")
        val uid = before["uid"] as Int
        val info = Os.lstat(root.path)
        require(info.st_uid == uid && OsConstants.S_ISDIR(info.st_mode))
        val label = Os.getxattr(root.path, "security.selinux")
        require(String(label).trimEnd('\u0000').startsWith("u:object_r:app_data_file:s0"))
        val operation = request.getString("operation")
        if (operation !in setOf("inspect", "mgbasetup", "coresetup", "pspinspect", "duckinspect", "ducklifecycle", "duckstop", "meloninspect")) require(request.getString("label") == String(label).trimEnd('\u0000')) { "Emulator security label changed." }
        val storage = SharedDocumentLock.appDirectory(File(applicationInfo.dataDir, "files"))
        require(storage.canonicalPath == storage.path && storage.isDirectory && Os.lstat(storage.path).st_uid == caller)
        if (melon) return SharedDocumentLock.acquire(storage).use {
            require(android.os.Build.VERSION.SDK_INT >= 30) { "Root melonDS requires Android 11 or newer." }
            val app = packageManager.getApplicationInfo(pkg, 0)
            require(app.splitSourceDirs.isNullOrEmpty() && File(app.nativeLibraryDir).name == "arm64" &&
                packageManager.getPackageInfo(pkg, 0).longVersionCode == 40L &&
                before["signer"] == MELON_SIGNER && before["version"] == MELON_VERSION) {
                "Root melonDS supports the reviewed ARM64 release. Use shared-folder setup on other builds."
            }
            val files = RootMelonFiles(before, ::live)
            val result = if (operation == "meloninspect") files.report() else {
                gameLibraryFromRelative(File(applicationInfo.dataDir, "files"), request.getString("libraryRelative")!!)
                files.operation(request, caller)
            }
            require(RootInspection.identity(this, pkg, 0) == before) { "melonDS changed during root access. Recovery was kept." }
            live()
            result
        }
        if (duck) return SharedDocumentLock.acquire(storage).use {
            require(android.os.Build.VERSION.SDK_INT >= 30) { "Root DuckStation saves require Android 11 or newer." }
            val app = packageManager.getApplicationInfo(pkg, 0)
            require(app.splitSourceDirs.isNullOrEmpty() && File(app.nativeLibraryDir).name == "arm64") {
                "Root DuckStation saves currently require the reviewed ARM64 beta. Use shared-folder setup on other builds."
            }
            val image = RootDuckImage(File(app.sourceDir), ::live)
            val process = RootDuckProcess(this, uid, image, ::live)
            val result = if (operation in setOf("ducklifecycle", "duckstop")) process.observe(request, dispose = operation == "duckstop") else {
                val files = RootDuckFiles(this, before, ::live, process::absent)
                if (operation != "duckinspect") files.validate(request)
                when (operation) {
                    "duckinspect" -> files.report()
                    "duckprofile" -> files.initialize(request)
                    "duckgame" -> files.prepareGame(request)
                    "ducklist" -> files.inventory(request)
                    "duckprofilelist" -> files.inventory(request, profileData = true)
                    "duckread" -> files.capture(request, request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller)
                    "duckprofileread" -> files.capture(request, request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller, profileData = true)
                    "duckreplace" -> files.replace(request, request.getParcelable<ParcelFileDescriptor>("transfer"), caller)
                    "duckprofilereplace" -> files.replace(request, request.getParcelable<ParcelFileDescriptor>("transfer"), caller, profileData = true)
                    else -> error("Unsupported DuckStation root operation")
                }
            }
            require(RootInspection.identity(this, pkg, 0) == before) { "DuckStation changed during root access. Recovery was kept." }
            live(); result
        }
        if (psp) return SharedDocumentLock.acquire(storage).use {
            live()
            val process = RootPpssppProcess(this, pkg, uid, ::live)
            val files = RootPpssppFiles(this, before, ::live, process::ensureClosed)
            if (operation != "pspinspect") files.validate(request)
            val result = when (operation) {
                "pspinspect" -> files.report()
                "psplifecycle" -> process.observe(request)
                "pspprofile" -> files.initialize(request)
                "pspselection" -> files.selection(request)
                "pspselect" -> files.select(request)
                "psplist" -> files.inventory(request)
                "pspprofilelist" -> files.profileInventory(request)
                "pspread" -> files.capture(request, request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller)
                "pspprofileread" -> files.capture(request, request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller, profileData = true)
                "pspreplace" -> files.replace(request, request.getParcelable<ParcelFileDescriptor>("transfer"), caller)
                "pspprofilereplace" -> files.replace(request, request.getParcelable<ParcelFileDescriptor>("transfer"), caller, profileData = true)
                else -> error("Unsupported PPSSPP root operation")
            }
            require(RootInspection.identity(this, pkg, 0) == before) { "PPSSPP changed during root access. Recovery was kept." }
            live(); result
        }
        return SharedDocumentLock.acquire(storage).use {
            live()
            val coreName = request.getString("coreName") ?: "mgba"
            RootSaveFiles.corePath(coreName)
            fun ensureClosed() {
                val state = RootRetroArchProcess(this, pkg, uid, ::live).observe(Bundle(), callerPid, caller).getString("state")
                check(state == "idle") { "Quit RetroArch so Broomm can verify it is closed before setting up RetroArch." }
            }
            val progressOperation = operation in setOf("check", "list", "read", "replace", "stagerom", "removerom",
                "flycastlist", "flycastread", "flycastreplace")
            val files = RootSaveFiles(root, uid, label, ::live, coreName = coreName,
                writerClosed = { if (progressOperation) ensureClosed() })
            if (progressOperation) ensureClosed()
            fun abi() = retroArchFrontendAbi(packageManager.getApplicationInfo(pkg, 0).nativeLibraryDir)
            fun installedApk(): File {
                val apk = File(packageManager.getApplicationInfo(pkg, 0).sourceDir)
                require(apk.canonicalPath == apk.absolutePath && apk.path.startsWith("/data/app/") &&
                    OsConstants.S_ISREG(Os.lstat(apk.path).st_mode)) { "Invalid installed RetroArch APK path." }
                return apk
            }
            val result = when (operation) {
                "inspect" -> {
                    val hash = files.core(abi(), coreName = coreName) ?: error("Set up $coreName in Broomm’s RetroArch settings first.")
                    val config = File("/storage/emulated/0/Android/data/$pkg/files/retroarch.cfg")
                    val bytes = if (files.present(config)) {
                        require(config.canonicalPath == config.path && OsConstants.S_ISREG(Os.lstat(config.path).st_mode)) { "RetroArch’s saved configuration is linked or invalid." }
                        files.bytes(config, MAX_BYTES)
                    } else ByteArray(0)
                    Bundle().apply {
                        putString("abi", abi()); putString("core", hash); putByteArray("config", bytes); putString("root", root.path)
                        putString("label", String(label).trimEnd('\u0000'))
                        putBoolean("frontendAssetsPending", files.needsFrontendAssets(::installedApk))
                        if (files.needsControllerProfiles()) {
                            putBoolean("bundledControllerProfiles", true)
                            putBoolean("controllerProfilesReady", files.controllerProfilesReady(before["build"] as String))
                        }
                    }
                }
                "controllerprofiles" -> {
                    files.prepareControllerProfiles(installedApk(), before["build"] as String, ::ensureClosed)
                    Bundle()
                }
                "mgbasetup", "coresetup" -> {
                    ensureClosed()
                    val abi = abi()
                    val core = files.core(abi, recoverPublication = true, coreName = coreName)
                    Bundle().apply {
                        putString("abi", abi); putString("core", core)
                        putString("label", String(label).trimEnd('\u0000'))
                    }
                }
                "installmgba", "installcore" -> {
                    val stage = request.getString("stage") ?: error("Missing mGBA staging identity")
                    require(Regex("[a-f0-9]{32}").matches(stage))
                    val source = File(File(applicationInfo.dataDir, "files").canonicalFile,
                        "broomm/android/${coreName}-stage/$stage/${RootSaveFiles.corePath(coreName).substringAfter('/')}")
                    require(source.canonicalPath == source.absolutePath) { "mGBA staging contains a linked path." }
                    val core = files.installCore(source, caller, request.getString("sha256")!!, abi(), coreName = coreName, ensureClosed = ::ensureClosed)
                    Bundle().apply { putString("core", core) }
                }
                "check" -> Bundle()
                "options" -> {
                    require(coreName in setOf("opera", "mednafen_saturn", "flycast"))
                    ensureClosed()
                    val requested = request.getString("path")!!
                    val path = if (requested.startsWith("/data/data/$pkg/"))
                        root.path + "/" + requested.removePrefix("/data/data/$pkg/") else requested
                    val bytes = files.options(path, listOf(
                        root, File("/storage/emulated/0/Android/data/$pkg/files"),
                        File("/storage/emulated/0/RetroArch/config")))
                    Bundle().apply { putByteArray("bytes", bytes) }
                }
                "lifecycle" -> RootRetroArchProcess(this, pkg, uid, ::live).observe(request, callerPid, caller)
                "stagerom" -> {
                    val path = request.getString("path")!!
                    val filesDir = File(applicationInfo.dataDir, "files")
                    val prepared = request.getString("preparedRelative")
                    val source = if (prepared != null) {
                        require(request.getString("libraryRelative") == null)
                        val parts = RootSaveFiles.romPath(path)
                        preparedCartridgeFromRelative(filesDir, prepared, parts[2].removePrefix("rom-"), parts[3])
                    } else gameLibraryFromRelative(filesDir,
                        request.getString("libraryRelative") ?: error("Missing cartridge library path"))
                    val rom = files.stageRom(path, source, caller, request.getString("sha256")!!, prepared = prepared != null)
                    Bundle().apply { putString("rom", rom.path) }
                }
                "removerom" -> {
                    val hash = request.getString("sha256") ?: error("Missing GBA ROM recovery checksum")
                    files.removeRom(request.getString("path")!!, hash)
                    Bundle()
                }
                "list", "flycastlist" -> {
                    val inventory = if (operation == "flycastlist") files.flycastResources(request.getString("configPath")!!)
                        else {
                            val areas = request.getParcelableArrayList<Bundle>("areas") ?: error("Missing root save boundaries")
                            files.inventory(areas.map { a -> a.keySet().associateWith { a.getString(it)!! } })
                        }
                    Bundle().apply { putBundle("files", Bundle().apply {
                        for ((path, entry) in inventory) putBundle(path, Bundle().apply {
                            putLong("bytes", entry.bytes); putString("sha256", entry.sha256); putString("metadata", entry.metadata)
                        })
                    }) }
                }
                "read", "flycastread" -> {
                    val path = request.getString("path")!!
                    val limit = if (operation == "flycastread") files.flycastResourceLimit(path, request.getString("configPath")!!)
                        else {
                            RootSaveFiles.managedPath(path, saveOnly = true, core = coreName)
                            files.progressLimit(path)
                        }
                    val file = files.path(path)
                    val metadata = files.metadata(file)
                    val bytes = files.bytes(file, limit)
                    require(RootSaveFiles.digest(bytes) == request.getString("sha256") &&
                        bytes.size.toLong() == request.getLong("bytes") && metadata == request.getString("metadata")) {
                        "Save changed during capture. Close the emulator and retry."
                    }
                    RootSaveTransfer.write(request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller, bytes, ::live)
                    Bundle()
                }
                "lynxfirmware" -> {
                    val payload = request.getParcelable<ParcelFileDescriptor>("transfer")?.let {
                        RootSaveTransfer.read(it, caller, 512, ::live)
                    }
                    files.lynxFirmware(request.getString("path")!!, request.getString("configPath")!!,
                        request.getString("before"), request.getString("after"), payload,
                        request.getString("token")!!, ::ensureClosed)
                    Bundle()
                }
                "operafirmware" -> {
                    val payload = request.getParcelable<ParcelFileDescriptor>("transfer")?.let {
                        RootSaveTransfer.read(it, caller, 1024 * 1024, ::live)
                    }
                    files.operaFirmware(request.getString("path")!!, request.getString("configPath")!!,
                        request.getString("before"), request.getString("after"), payload,
                        request.getString("token")!!, ::ensureClosed)
                    Bundle()
                }
                "saturnfirmware" -> {
                    val payload = request.getParcelable<ParcelFileDescriptor>("transfer")?.let {
                        RootSaveTransfer.read(it, caller, 2 * 1024 * 1024, ::live)
                    }
                    files.saturnFirmware(request.getString("path")!!, request.getString("configPath")!!,
                        request.getString("before"), request.getString("after"), payload,
                        request.getString("token")!!, ::ensureClosed)
                    Bundle()
                }
                "flycastreplace" -> {
                    val payload = request.getParcelable<ParcelFileDescriptor>("transfer")?.let {
                        RootSaveTransfer.read(it, caller, 2 * 1024 * 1024, ::live)
                    }
                    files.flycastResource(request.getString("path")!!, request.getString("configPath")!!,
                        request.getString("before"), request.getString("after"), payload,
                        request.getString("token")!!, ::ensureClosed)
                    Bundle()
                }
                "replace" -> {
                    val path = request.getString("path")!!
                    RootSaveFiles.managedPath(path, core = coreName)
                    val payload = request.getParcelable<ParcelFileDescriptor>("transfer")?.let {
                        RootSaveTransfer.read(it, caller, files.progressLimit(path), ::live)
                    }
                    files.replace(path, request.getString("before"), request.getString("after"),
                        payload, request.getString("metadata"), request.getString("token")!!, request.getString("stateGroup"))
                    Bundle()
                }
                else -> error("Unsupported root file operation")
            }
            require(RootInspection.identity(this, pkg, 0) == before) { "Emulator changed during root operation. Recovery was kept." }
            if (progressOperation) ensureClosed()
            live(); result
        }
    }
    companion object {
        const val REQUEST = IBinder.FIRST_CALL_TRANSACTION
        const val DESCRIPTOR = "app.broomm.root-save.v1"
        const val MAX_BYTES = 262144 // GBA ordinary saves and the bounded session config only.
    }
}
