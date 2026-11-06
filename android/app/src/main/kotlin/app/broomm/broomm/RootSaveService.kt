package app.broomm.broomm

import android.os.Binder
import android.os.Bundle
import android.os.IBinder
import android.os.Parcel
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
        if (request.getString("operation") != "inspect") require(request.getString("label") == String(label).trimEnd('\u0000')) { "Emulator security label changed." }
        val storage = SharedDocumentLock.appDirectory(File(applicationInfo.dataDir, "files"))
        require(storage.canonicalPath == storage.path && storage.isDirectory && Os.lstat(storage.path).st_uid == caller)
        return SharedDocumentLock.acquire(storage).use {
            live()
            val files = RootSaveFiles(root, uid, label, ::live)
            val result = when (request.getString("operation")) {
                "inspect" -> {
                    val core = files.existing("cores/mgba_libretro_android.so")
                    val hash = files.hash(core, 32 * 1024 * 1024)
                    val config = File("/storage/emulated/0/Android/data/$pkg/files/retroarch.cfg")
                    require(config.canonicalPath == config.path && OsConstants.S_ISREG(Os.lstat(config.path).st_mode)) { "Open RetroArch, save its configuration and quit before connecting root saves." }
                    val bytes = files.bytes(config, MAX_BYTES)
                    Bundle().apply { putString("core", hash); putByteArray("config", bytes); putString("root", root.path); putString("label", String(label).trimEnd('\u0000')) }
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
                "list", "read" -> {
                    val path = request.getString("path")!!
                    RootSaveFiles.managedPath(path, saveOnly = true)
                    val file = files.path(path)
                    if (!files.present(file)) Bundle().apply { putBoolean("missing", true) }
                    else {
                        val bytes = files.bytes(file, MAX_BYTES)
                        val metadata = files.metadata(file)
                        val hash = RootSaveFiles.digest(bytes)
                        if (request.getString("operation") == "read")
                            require(hash == request.getString("sha256")) { "Save changed during capture. Close the emulator and retry." }
                        Bundle().apply {
                            putLong("bytes", bytes.size.toLong()); putString("sha256", hash)
                            putString("metadata", metadata)
                            if (request.getString("operation") == "read") putByteArray("payload", bytes)
                        }
                    }
                }
                "replace" -> {
                    val path = request.getString("path")!!
                    RootSaveFiles.managedPath(path)
                    files.replace(path, request.getString("before"), request.getString("after"),
                        request.getByteArray("payload"), request.getString("metadata"), request.getString("token")!!)
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
