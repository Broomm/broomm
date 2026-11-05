package app.broomm.broomm

import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.ServiceConnection
import android.os.Bundle
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.Parcel
import android.os.SystemClock
import com.topjohnwu.superuser.Shell
import com.topjohnwu.superuser.ipc.RootService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Short-lived app-bound root connection. No daemon or automatic permission request. */
class RootSaveAccess(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val running = AtomicBoolean(false)
    private var connection: ServiceConnection? = null
    private var closed = false
    fun busy() = running.get()
    fun operation(call: MethodCall, result: MethodChannel.Result) {
        check(!closed && running.compareAndSet(false, true)) { "A root file operation is already running." }
        val done = AtomicBoolean(false)
        fun finish(value: Any? = null, error: String? = null) {
            if (!done.compareAndSet(false, true)) return
            running.set(false)
            if (error == null) result.success(value) else result.error("android-root-save", error, null)
        }
        val timeout = Runnable { finish(error = "Root access timed out. Check Magisk, then retry; recovery was kept.") }
        main.postDelayed(timeout, 35000)
        try {
            val pkg = call.argument<String>("package")!!
            require(pkg in setOf("com.retroarch.aarch64", "com.retroarch", "com.retroarch.ra32"))
            val identity = RootInspection.identity(activity, pkg)
            require(identity["user"] == 0) { "The first GBA root route supports Android user 0." }
            require(identity["build"] == call.argument<String>("build")) { "Refresh the changed emulator before connecting root saves." }
            if (call.method != "rootInspect") for (key in listOf("signer", "uid", "user", "dataDir"))
                require(identity[key].toString() == call.argument<String>(key)) { "The root save connection belongs to a different emulator installation." }
            val storage = File(activity.filesDir.canonicalFile, "broomm/android")
            require(storage.canonicalPath == storage.absolutePath && (storage.isDirectory || storage.mkdirs()))
            val request = Bundle().apply {
                for ((key, value) in identity) putString(key, value.toString())
                putLong("deadline", SystemClock.elapsedRealtime() + 30000)
                putString("operation", call.method.removePrefix("root").lowercase())
                for (key in listOf("path", "before", "after", "sha256", "metadata", "token", "label"))
                    putString(key, call.argument<String>(key))
            }
            var listPath: String? = null
            if (call.method == "rootList") {
                val areas = call.argument<List<Map<String, String>>>("areas")!!
                require(areas.size == 1 && areas.single().keys == setOf("path", "exact"))
                listPath = "${areas.single()["path"]}/${areas.single()["exact"]}"
                request.putString("path", listPath)
            }
            if (call.method == "rootReplace") {
                call.argument<String>("source")?.let { source ->
                    val file = privateFile(source)
                    val bytes = file.inputStream().use { input ->
                        val out = java.io.ByteArrayOutputStream()
                        val block = ByteArray(16384)
                        while (true) {
                            val n = input.read(block); if (n < 0) break
                            require(out.size() + n <= RootSaveService.MAX_BYTES)
                            out.write(block, 0, n)
                        }
                        out.toByteArray()
                    }
                    request.putByteArray("payload", bytes)
                }
            }
            // A custom shell avoids changing the main shell's policy for any
            // other feature. The root service requires the same global mounts
            // already verified by the read-only inspection on the Thor.
            val conn = object : ServiceConnection {
                override fun onServiceConnected(name: ComponentName, binder: IBinder) {
                    if (closed || done.get()) { RootService.unbind(this); return }
                    worker.execute {
                        try {
                            val input = Parcel.obtain(); val output = Parcel.obtain()
                            val answer = try {
                                input.writeInterfaceToken(RootSaveService.DESCRIPTOR); input.writeBundle(request)
                                check(binder.transact(RootSaveService.REQUEST, input, output, 0))
                                output.readException(); output.readBundle(javaClass.classLoader) ?: error("Missing root reply")
                            } finally { input.recycle(); output.recycle() }
                            answer.getString("error")?.let { error(it) }
                            require(RootInspection.identity(activity, pkg) == identity) { "Emulator changed during root access. Recovery was kept." }
                            val mapped = answer.keySet().associateWith { answer.get(it) }.toMutableMap()
                            val value: Any? = when (call.method) {
                                "rootInspect" -> identity.mapValues { it.value.toString() } + mapped
                                "rootList" -> if (answer.getBoolean("missing")) emptyMap<String, Any>() else mapOf(listPath!! to mapped)
                                "rootRead" -> {
                                    require(!answer.getBoolean("missing")) { "A save disappeared during capture." }
                                    val bytes = answer.getByteArray("payload")!!
                                    require(bytes.size.toLong() == (call.argument<Number>("bytes")!!).toLong() && RootSaveFiles.digest(bytes) == call.argument<String>("sha256"))
                                    val target = privateFile(call.argument<String>("target")!!)
                                    require(target.createNewFile()) { "A root recovery target already exists; files were kept." }
                                    FileOutputStream(target).use { it.write(bytes); it.fd.sync() }
                                    null
                                }
                                else -> null
                            }
                            main.post { finish(value) }
                        } catch (e: Exception) { main.post { finish(error = e.message ?: "Root file operation failed. Recovery was kept.") } }
                        finally { main.post { main.removeCallbacks(timeout); RootService.unbind(this); if (connection === this) connection = null } }
                    }
                }
                override fun onServiceDisconnected(name: ComponentName) {
                    finish(error = "Root service disconnected. Recovery was kept; close the emulator before retrying.")
                }
            }
            connection = conn
            val task = RootService.bindOrTask(Intent(activity, RootSaveService::class.java), main::post, conn)
            if (task != null) worker.execute {
                try {
                    Shell.Builder.create().setFlags(Shell.FLAG_MOUNT_MASTER).setTimeout(30).build().use { shell ->
                        check(shell.isRoot) { "Magisk did not grant Broomm root access." }
                        if (!closed && !done.get()) shell.execTask(task)
                    }
                } catch (e: Exception) { main.post { finish(error = e.message ?: "Root service could not start.") } }
            }
        } catch (e: Exception) { main.removeCallbacks(timeout); finish(error = e.message ?: "Root request is invalid.") }
    }
    private fun privateFile(value: String): File {
        val base = File(activity.filesDir.canonicalFile, "broomm/android/shared-session")
        require(base.canonicalPath == base.absolutePath && base.isDirectory)
        val file = File(value)
        val logical = File(activity.filesDir, "broomm/android/shared-session").absolutePath
        require(file.absolutePath.startsWith("$logical/") || file.absolutePath.startsWith("${base.path}/"))
        val relative = if (file.absolutePath.startsWith("$logical/")) file.absolutePath.substring(logical.length + 1) else file.absolutePath.substring(base.path.length + 1)
        require(Regex("[a-f0-9]{32}").matches(relative.substringBefore('/')))
        require(relative.split('/').all { it.isNotEmpty() && it != "." && it != ".." && it.none { c -> c.code < 32 || c == '\\' } })
        var checked = base
        for (part in relative.split('/')) { checked = File(checked, part); require(checked.canonicalPath == checked.absolutePath) }
        require(checked.parentFile!!.isDirectory && !checked.isDirectory)
        return checked
    }
    fun close() {
        closed = true
        connection?.let { RootService.unbind(it) }; connection = null
        worker.shutdown()
    }
}
