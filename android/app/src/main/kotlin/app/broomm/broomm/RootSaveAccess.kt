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
import android.util.Log
import com.topjohnwu.superuser.Shell
import com.topjohnwu.superuser.ipc.RootService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.Executors
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicReference

/** Short-lived app-bound root connection. No daemon or automatic permission request. */
class RootSaveAccess(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val running = AtomicBoolean(false)
    private var connection: ServiceConnection? = null
    private var closed = false
    private var restartRequired = false
    fun busy() = running.get()
    fun operation(call: MethodCall, result: MethodChannel.Result) {
        check(!closed && running.compareAndSet(false, true)) { "A root file operation is already running." }
        if (restartRequired) {
            running.set(false)
            result.error("android-root-save", "Root service startup failed. Close and reopen Broomm before retrying; recovery was kept.", null)
            return
        }
        val done = AtomicBoolean(false)
        val connected = CountDownLatch(1)
        var registered = false
        val stage = AtomicReference("validating")
        fun phase(value: String) { stage.set(value); Log.i("BroommRoot", "${call.method}: $value") }
        fun finish(value: Any? = null, error: String? = null) {
            if (!done.compareAndSet(false, true)) return
            if (registered && connected.count != 0L) restartRequired = true
            running.set(false)
            Log.i("BroommRoot", "${call.method}: ${if (error == null) "completed" else "failed at ${stage.get()}"}")
            if (error == null) result.success(value) else result.error("android-root-save", error, null)
        }
        val timeout = Runnable { finish(error = "Root access timed out during ${stage.get()}. Close and reopen Broomm before retrying; recovery was kept.") }
        main.postDelayed(timeout, 35000)
        try {
            val pkg = call.argument<String>("package")!!
            require(pkg in setOf("com.retroarch.aarch64", "com.retroarch", "com.retroarch.ra32"))
            val identity = RootInspection.identity(activity, pkg)
            require(identity["user"] == 0) { "The first GBA root route supports Android user 0." }
            require(identity["build"] == call.argument<String>("build")) { "Refresh the changed emulator before connecting root saves." }
            if (call.method != "rootInspect") for (key in listOf("signer", "uid", "user", "dataDir"))
                require(identity[key].toString() == call.argument<String>(key)) { "The root save connection belongs to a different emulator installation." }
            val storage = SharedDocumentLock.appDirectory(activity.filesDir)
            // Create the shared inode as the app, before root can acquire it.
            // The same path also makes a surviving root worker visible to ioBusy.
            SharedDocumentLock.acquire(storage).use { }
            val request = Bundle().apply {
                for ((key, value) in identity) putString(key, value.toString())
                putLong("deadline", SystemClock.elapsedRealtime() + 30000)
                putString("operation", call.method.removePrefix("root").lowercase())
                for (key in listOf("path", "before", "after", "sha256", "metadata", "token", "label"))
                    putString(key, call.argument<String>(key))
            }
            var listPath: String? = null
            if (call.method == "rootStageRom") {
                // The app and root mount namespaces can expose different
                // names for the same framework filesDir.
                val relative = gameLibraryRelative(activity.filesDir, call.argument<String>("source")!!)
                request.putString("libraryRelative", relative)
            }
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
                    connected.countDown()
                    if (closed || done.get()) { RootService.unbind(this); return }
                    phase("file operation")
                    worker.execute {
                        try {
                            val input = Parcel.obtain(); val output = Parcel.obtain()
                            val answer = try {
                                input.writeInterfaceToken(RootSaveService.DESCRIPTOR); input.writeBundle(request)
                                check(binder.transact(RootSaveService.REQUEST, input, output, 0))
                                output.readException(); output.readBundle(javaClass.classLoader) ?: error("Missing root reply")
                            } finally { input.recycle(); output.recycle() }
                            check(!closed && !done.get()) { "Root reply arrived after the request ended. Recovery was kept." }
                            answer.getString("error")?.let { error(it) }
                            require(RootInspection.identity(activity, pkg) == identity) { "Emulator changed during root access. Recovery was kept." }
                            val mapped = answer.keySet().associateWith { answer.get(it) }.toMutableMap()
                            val value: Any? = when (call.method) {
                                "rootInspect" -> identity.mapValues { it.value.toString() } + mapped
                                "rootStageRom" -> answer.getString("rom") ?: error("Missing staged ROM")
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
                override fun onNullBinding(name: ComponentName) {
                    connected.countDown()
                    finish(error = "Root service could not bind. Close and reopen Broomm; recovery was kept.")
                }
            }
            worker.execute {
                try {
                    phase("Magisk permission")
                    // Obtain permission before libsu records a pending binding.
                    // Use the verified global namespace with no isolated fallback.
                    Shell.Builder.create().setCommands("su", "-M").setTimeout(25).build().use { shell ->
                        check(shell.isRoot) { "Magisk did not grant Broomm root access." }
                        if (closed || done.get()) return@use
                        val ready = CountDownLatch(1)
                        val bootstrap = AtomicReference<Shell.Task?>()
                        val failure = AtomicReference<Exception?>()
                        main.post {
                            try {
                                if (!closed && !done.get()) {
                                    phase("service startup")
                                    connection = conn
                                    registered = true
                                    bootstrap.set(RootService.bindOrTask(Intent(activity, RootSaveService::class.java), main::post, conn))
                                }
                            } catch (e: Exception) { failure.set(e) }
                            finally { ready.countDown() }
                        }
                        check(ready.await(5, TimeUnit.SECONDS)) { "Root binding could not reach the app." }
                        failure.get()?.let { throw it }
                        if (closed || done.get()) return@use
                        bootstrap.get()?.let { shell.execTask(it) }
                        // execTask only writes a background launch command. Keep
                        // the shell alive until the service actually connects.
                        val remaining = request.getLong("deadline") - SystemClock.elapsedRealtime()
                        check(remaining > 0 && connected.await(remaining, TimeUnit.MILLISECONDS)) { "Root service did not connect. Close and reopen Broomm before retrying." }
                    }
                } catch (e: Exception) { main.post { finish(error = "${stage.get()}: ${e.message ?: "Root service could not start."}") } }
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
