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
        require(pkg in setOf("com.retroarch.aarch64", "com.retroarch", "com.retroarch.ra32"))
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
        if (operation !in setOf("inspect", "mgbasetup", "coresetup")) require(request.getString("label") == String(label).trimEnd('\u0000')) { "Emulator security label changed." }
        val storage = SharedDocumentLock.appDirectory(File(applicationInfo.dataDir, "files"))
        require(storage.canonicalPath == storage.path && storage.isDirectory && Os.lstat(storage.path).st_uid == caller)
        return SharedDocumentLock.acquire(storage).use {
            live()
            val files = RootSaveFiles(root, uid, label, ::live)
            fun ensureClosed() {
                val state = RootRetroArchProcess(this, pkg, uid, ::live).observe(Bundle(), callerPid, caller).getString("state")
                check(state == "idle") { "Quit RetroArch so Broomm can verify it is closed before setting up RetroArch." }
            }
            fun abi() = retroArchFrontendAbi(packageManager.getApplicationInfo(pkg, 0).nativeLibraryDir)
            fun installedApk(): File {
                val apk = File(packageManager.getApplicationInfo(pkg, 0).sourceDir)
                require(apk.canonicalPath == apk.absolutePath && apk.path.startsWith("/data/app/") &&
                    OsConstants.S_ISREG(Os.lstat(apk.path).st_mode)) { "Invalid installed RetroArch APK path." }
                return apk
            }
            val coreName = request.getString("coreName") ?: "mgba"
            RootSaveFiles.corePath(coreName)
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
                        "broomm/android/${coreName}-stage/$stage/${coreName}_libretro_android.so")
                    require(source.canonicalPath == source.absolutePath) { "mGBA staging contains a linked path." }
                    val core = files.installCore(source, caller, request.getString("sha256")!!, abi(), coreName = coreName, ensureClosed = ::ensureClosed)
                    Bundle().apply { putString("core", core) }
                }
                "check" -> Bundle()
                "lifecycle" -> RootRetroArchProcess(this, pkg, uid, ::live).observe(request, callerPid, caller)
                "stagerom" -> {
                    val path = request.getString("path")!!
                    val filesDir = File(applicationInfo.dataDir, "files")
                    val relative = request.getString("libraryRelative") ?: error("Missing GBA library path")
                    val source = gameLibraryFromRelative(filesDir, relative)
                    val rom = files.stageRom(path, source, caller, request.getString("sha256")!!)
                    Bundle().apply { putString("rom", rom.path) }
                }
                "removerom" -> {
                    val hash = request.getString("sha256") ?: error("Missing GBA ROM recovery checksum")
                    files.removeRom(request.getString("path")!!, hash)
                    Bundle()
                }
                "list" -> {
                    val areas = request.getParcelableArrayList<Bundle>("areas") ?: error("Missing root save boundaries")
                    val inventory = files.inventory(areas.map { a -> a.keySet().associateWith { a.getString(it)!! } })
                    Bundle().apply { putBundle("files", Bundle().apply {
                        for ((path, entry) in inventory) putBundle(path, Bundle().apply {
                            putLong("bytes", entry.bytes); putString("sha256", entry.sha256); putString("metadata", entry.metadata)
                        })
                    }) }
                }
                "read" -> {
                    val path = request.getString("path")!!
                    RootSaveFiles.managedPath(path, saveOnly = true)
                    val file = files.path(path)
                    val metadata = files.metadata(file)
                    val bytes = files.bytes(file, RootSaveFiles.limit(path))
                    require(RootSaveFiles.digest(bytes) == request.getString("sha256") &&
                        bytes.size.toLong() == request.getLong("bytes") && metadata == request.getString("metadata")) {
                        "Save changed during capture. Close the emulator and retry."
                    }
                    RootSaveTransfer.write(request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller, bytes, ::live)
                    Bundle()
                }
                "replace" -> {
                    val path = request.getString("path")!!
                    RootSaveFiles.managedPath(path)
                    val payload = request.getParcelable<ParcelFileDescriptor>("transfer")?.let {
                        RootSaveTransfer.read(it, caller, RootSaveFiles.limit(path), ::live)
                    }
                    files.replace(path, request.getString("before"), request.getString("after"),
                        payload, request.getString("metadata"), request.getString("token")!!, request.getString("stateGroup"))
                    Bundle()
                }
                else -> error("Unsupported root file operation")
            }
            require(RootInspection.identity(this, pkg, 0) == before) { "Emulator changed during root operation. Recovery was kept." }
            live(); result
        }
    }
    companion object {
        const val REQUEST = IBinder.FIRST_CALL_TRANSACTION
        const val DESCRIPTOR = "app.broomm.root-save.v1"
        const val MAX_BYTES = 262144 // GBA ordinary saves and the bounded session config only.
    }
}
