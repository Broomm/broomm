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
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
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

/** Lazy root connection owned by the Broomm activity, including emulator handoff. */
class RootSaveAccess(private val activity: Activity) {
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val running = AtomicBoolean(false)
    private var connection: Binding? = null
    private var interrupted: ((String) -> Unit)? = null
    @Volatile private var closed = false
    private var restartRequired = false

    private inner class Binding(private var ready: ((IBinder) -> Unit)?) : ServiceConnection {
        val connected = CountDownLatch(1)
        var binder: IBinder? = null
            private set

        override fun onServiceConnected(name: ComponentName, service: IBinder) {
            connected.countDown()
            if (closed || connection !== this) {
                unbind()
                return
            }
            binder = service
            val dispatch = ready
            ready = null
            dispatch?.invoke(service)
        }

        override fun onServiceDisconnected(name: ComponentName) =
            disconnected("Root service disconnected. Recovery was kept; close the emulator before retrying.")

        override fun onNullBinding(name: ComponentName) =
            disconnected("Root service could not bind. Close and reopen Broomm; recovery was kept.")

        private fun disconnected(message: String) {
            if (connection !== this) return
            connection = null
            binder = null
            ready = null
            connected.countDown()
            interrupted?.invoke(message)
        }

        fun unbind() {
            if (connection === this) connection = null
            binder = null
            ready = null
            connected.countDown()
            RootService.unbind(this)
        }
    }

    fun busy() = running.get()
    fun operation(call: MethodCall, result: MethodChannel.Result) {
        check(!closed && running.compareAndSet(false, true)) { "A root file operation is already running." }
        if (restartRequired) {
            running.set(false)
            result.error("android-root-save", "Root service startup failed. Close and reopen Broomm before retrying; recovery was kept.", null)
            return
        }
        val done = AtomicBoolean(false)
        var starting: Binding? = null
        val stage = AtomicReference("validating")
        fun phase(value: String) { stage.set(value); Log.i("BroommRoot", "${call.method}: $value") }
        fun finish(value: Any? = null, error: String? = null) {
            if (!done.compareAndSet(false, true)) return
            main.removeCallbacksAndMessages(done)
            // libsu retains a pending bootstrap until it receives its reply.
            starting?.let {
                if (it.connected.count != 0L) {
                    restartRequired = true
                    it.unbind()
                }
            }
            interrupted = null
            running.set(false)
            Log.i("BroommRoot", "${call.method}: ${if (error == null) "completed" else "failed at ${stage.get()}"}")
            if (error == null) result.success(value) else result.error("android-root-save", error, null)
        }
        val timeout = Runnable { finish(error = "Root access timed out during ${stage.get()}. Close and reopen Broomm before retrying; recovery was kept.") }
        main.postAtTime(timeout, done, SystemClock.uptimeMillis() + 35000)
        interrupted = { finish(error = it) }
        try {
            val pkg = call.argument<String>("package")!!
            require(pkg in setOf("com.retroarch.aarch64", "com.retroarch", "com.retroarch.ra32"))
            val identity = RootInspection.identity(activity, pkg)
            require(identity["user"] == 0) { "The first GBA root route supports Android user 0." }
            require(identity["build"] == call.argument<String>("build")) { "Refresh the changed emulator before connecting root saves." }
            if (call.method !in setOf("rootInspect", "rootMgbaSetup", "rootCoreSetup")) for (key in listOf("signer", "uid", "user", "dataDir"))
                require(identity[key].toString() == call.argument<String>(key)) { "The root save connection belongs to a different emulator installation." }
            val storage = SharedDocumentLock.appDirectory(activity.filesDir)
            // Create the shared inode as the app, before root can acquire it.
            // The same path also makes a surviving root worker visible to ioBusy.
            SharedDocumentLock.acquire(storage).use { }
            val request = Bundle().apply {
                for ((key, value) in identity) putString(key, value.toString())
                putLong("deadline", SystemClock.elapsedRealtime() + 30000)
                putString("operation", call.method.removePrefix("root").lowercase())
                for (key in listOf("path", "before", "after", "sha256", "metadata", "token", "label", "stage", "coreName", "stateGroup", "configPath"))
                    putString(key, call.argument<String>(key))
            }
            if (call.method == "rootLifecycle") {
                call.argument<Number>("launchedAfter")?.toLong()?.let {
                    require(it in 0..SystemClock.elapsedRealtime())
                    request.putLong("launchedAfter", it)
                }
                call.argument<Map<String, Number>>("process")?.let {
                    require(it.keys == setOf("pid", "startTicks", "observedElapsed", "observedWall"))
                    val pid = it.getValue("pid").toLong()
                    require(pid in 1..Int.MAX_VALUE.toLong() && it.values.all { n -> n.toLong() > 0 })
                    request.putInt("pid", pid.toInt())
                    for (key in listOf("startTicks", "observedElapsed", "observedWall"))
                        request.putLong(key, it.getValue(key).toLong())
                }
            }
            if (call.method == "rootStageRom") {
                // The app and root mount namespaces can expose different
                // names for the same framework filesDir.
                val source = call.argument<String>("source")!!
                if (call.argument<Boolean>("preparedCartridge") == true) {
                    val parts = RootSaveFiles.romPath(call.argument<String>("path")!!)
                    request.putString("preparedRelative", preparedCartridgeRelative(
                        activity.filesDir, source, parts[2].removePrefix("rom-"), parts[3]))
                } else request.putString("libraryRelative", gameLibraryRelative(activity.filesDir, source))
            }
            if (call.method == "rootList") {
                val areas = call.argument<List<Map<String, String>>>("areas")!!
                require(areas.size in 1..2 && areas.all { a -> a.size <= 3 && a.values.all { it.length <= 1024 } })
                request.putParcelableArrayList("areas", ArrayList(areas.map { area -> Bundle().apply {
                    for ((key, value) in area) putString(key, value)
                } }))
            }
            if (call.method == "rootRead") request.putLong("bytes", call.argument<Number>("bytes")!!.toLong())
            fun dispatch(binder: IBinder) {
                phase("file operation")
                worker.execute {
                    try {
                        check(!closed && !done.get()) { "Root request already ended. Recovery was kept." }
                        val input = Parcel.obtain(); val output = Parcel.obtain()
                        var descriptor: ParcelFileDescriptor? = null
                        val answer = try {
                            val source = if (call.method in setOf("rootReplace", "rootLynxFirmware")) call.argument<String>("source") else null
                            val target = if (call.method == "rootRead") call.argument<String>("target") else null
                            if (source != null || target != null) {
                                val file = privateFile(source ?: target!!)
                                val flags = if (source != null) OsConstants.O_RDONLY else
                                    OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL
                                val fd = Os.open(file.path, flags or OsConstants.O_NOFOLLOW or OsConstants.O_NONBLOCK, 384)
                                descriptor = try { ParcelFileDescriptor.dup(fd) } finally { Os.close(fd) }
                                request.putParcelable("transfer", descriptor)
                            }
                            input.writeInterfaceToken(RootSaveService.DESCRIPTOR); input.writeBundle(request)
                            check(binder.transact(RootSaveService.REQUEST, input, output, 0))
                            output.readException(); output.readBundle(javaClass.classLoader) ?: error("Missing root reply")
                        } finally { descriptor?.close(); input.recycle(); output.recycle() }
                        check(!closed && !done.get()) { "Root reply arrived after the request ended. Recovery was kept." }
                        answer.getString("error")?.let { error(it) }
                        require(RootInspection.identity(activity, pkg) == identity) { "Emulator changed during root access. Recovery was kept." }
                        val mapped = answer.keySet().associateWith { answer.get(it) }.toMutableMap()
                        val value: Any? = when (call.method) {
                            "rootInspect", "rootMgbaSetup", "rootCoreSetup" -> identity.mapValues { it.value.toString() } + mapped
                            "rootLifecycle" -> mapped
                            "rootStageRom" -> answer.getString("rom") ?: error("Missing staged ROM")
                            "rootInstallMgba", "rootInstallCore" -> answer.getString("core") ?: error("Missing installed mGBA checksum")
                            "rootList" -> {
                                val entries = answer.getBundle("files") ?: error("Missing root inventory")
                                entries.keySet().associateWith { key ->
                                    val entry = entries.getBundle(key)!!
                                    entry.keySet().associateWith { entry.get(it) }
                                }
                            }
                            "rootRead" -> null
                            else -> null
                        }
                        main.post { finish(value) }
                    } catch (e: Exception) {
                        main.post {
                            if (!binder.isBinderAlive) connection?.takeIf { it.binder === binder }?.unbind()
                            finish(error = e.message ?: "Root file operation failed. Recovery was kept.")
                        }
                    }
                }
            }
            val bound = connection?.binder
            if (bound?.isBinderAlive == true) {
                phase("reusing root service")
                dispatch(bound)
                return
            }
            connection?.unbind()
            val conn = Binding(::dispatch)
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
                                    starting = conn
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
                        check(remaining > 0 && conn.connected.await(remaining, TimeUnit.MILLISECONDS)) { "Root service did not connect. Close and reopen Broomm before retrying." }
                    }
                } catch (e: Exception) { main.post { finish(error = "${stage.get()}: ${e.message ?: "Root service could not start."}") } }
            }
        } catch (e: Exception) { finish(error = e.message ?: "Root request is invalid.") }
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
        interrupted?.invoke("Broomm closed during root access. Recovery was kept.")
        connection?.unbind()
        worker.shutdown()
    }
}
