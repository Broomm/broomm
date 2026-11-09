package app.broomm.broomm

import android.content.Context
import android.os.Bundle
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.system.Os
import android.system.OsConstants
import android.system.ErrnoException
import java.io.File
import java.security.MessageDigest

/** Explicit root fixture, never shipped. Only its fresh nonce/workspace is
 * writable. Original settings, BIOS, cards and states are read-only. */
fun main(args: Array<String>) {
    try { checkDuckFiles(args) } catch (e: Throwable) { e.printStackTrace(System.out); kotlin.system.exitProcess(2) }
}
private fun checkDuckFiles(args: Array<String>) {
    require(args.size == 1 && Regex("[a-f0-9]{32}").matches(args[0]))
    val probe=File("/data/local/tmp/broomm-duck-label-${args[0]}");require(!probe.exists())
    try {duckStorageLabel(probe.path);error("Missing initialization accepted")}
    catch(e:IllegalStateException) {require((e.cause as? ErrnoException)?.errno==OsConstants.ENOENT && e.message!!.contains("Open DuckStation once"))}
    require(probe.createNewFile());val probeIdentity=Os.lstat(probe.path)
    try {
        require(duckStorageLabel(probe.path).contentEquals(Os.getxattr(probe.path,"security.selinux")))
        try {duckStorageLabel(File(probe,"child").path);error("Non-directory accepted")}
        catch(e:ErrnoException) {require(e.errno==OsConstants.ENOTDIR)}
    } finally {require(Os.lstat(probe.path).let {it.st_ino==probeIdentity.st_ino && it.st_dev==probeIdentity.st_dev && it.st_size==0L && it.st_nlink==1L});require(probe.delete())}
    println("PASS missing initialization guidance and distinct native filesystem errors")
    Looper.prepareMainLooper()
    val type = Class.forName("android.app.ActivityThread")
    val thread = type.getMethod("systemMain").invoke(null)
    val context = type.getMethod("getSystemContext").invoke(thread) as Context
    val pkg = "com.github.stenzek.duckstation"; val app = context.packageManager.getApplicationInfo(pkg, 0)
    val identity = mapOf<String, Any>("package" to pkg, "user" to 0, "uid" to app.uid, "dataDir" to app.dataDir)
    val end = SystemClock.elapsedRealtime() + 30000
    fun live() { check(SystemClock.elapsedRealtime() <= end) }
    val image = RootDuckImage(File(app.sourceDir), ::live)
    val process = RootDuckProcess(context, app.uid, image, ::live)
    process.absent()
    var failure: String? = null; var writer = false
    val files = RootDuckFiles(context, identity, ::live, { check(!writer) { "Controlled writer arrival" }; process.absent() }) { point ->
        if (point == failure) { failure = null; error("Controlled interruption: $point") }
    }
    val before = files.report().getBundle("settings")!!
    val request = Bundle().apply {
        putString("server", "f".repeat(32)); putString("profile", "e".repeat(32)); putString("ownerNonce", args[0])
        putString("game", "42"); putString("stateGroup", "states-0123456789abcdef-android")
        putByteArray("config", "[GPU]\nResolutionScale = 2\n".toByteArray())
    }
    val profile = File("/data/media/0/Android/data/$pkg/files/Broomm-PS1-${"f".repeat(32)}-${"e".repeat(32)}-${args[0]}")
    val local = File("/data/local/tmp/broomm-duck-files-${args[0]}")
    require(!profile.exists() && !local.exists())
    check(files.initialize(request).getString("status") == "ready"); files.prepareGame(request)
    require(local.mkdir()); Os.chmod(local.path, 448)
    fun hash(b: ByteArray) = MessageDigest.getInstance("SHA-256").digest(b).joinToString("") { "%02x".format(it.toInt() and 255) }
    val source = File(local, "source"); val bytes = ByteArray(131072) { (it * 17).toByte() }.apply { this[0] = 77; this[1] = 67 }
    source.writeBytes(bytes); Os.chmod(source.path, 384)
    val replace = Bundle(request).apply { putString("path", "games/42/cards/card1.mcd"); putString("after", hash(bytes)); putString("token", "a".repeat(32)) }
    fun publish(r: Bundle = replace): Bundle = ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY).use { files.replace(r, it, 0) }
    fun refused(name: String, reason: String? = null, body: () -> Unit) {
        var failed = false
        try { body() } catch (e: Exception) { if (reason != null) check(e.message?.contains(reason) == true) { "Wrong refusal for $name: $e" }; failed = true }
        check(failed) { "Expected refusal: $name" }; println("PASS $name")
    }
    failure = "file-stage-bytes"; refused("interrupted incoming stream", "Controlled interruption: file-stage-bytes") { publish() }
    failure = "file-linked"; refused("exclusive publication before acknowledgement", "Controlled interruption: file-linked") { publish() }
    val created = publish()
    check(created.getString("sha256") == hash(bytes) && created.getLong("bytes") == 131072L)
    check(created.getString("metadata")!!.split(' ').let { it[0] == app.uid.toString() && it[2] == "660" && it.last() == "1" })
    val capture = File(local, "captured")
    val read = Bundle(request).apply {
        putString("path", replace.getString("path")); putString("sha256", created.getString("sha256")); putString("metadata", created.getString("metadata")); putLong("bytes", created.getLong("bytes"))
    }
    ParcelFileDescriptor.open(capture, ParcelFileDescriptor.MODE_CREATE or ParcelFileDescriptor.MODE_WRITE_ONLY).use { files.capture(read, it, 0) }
    check(capture.readBytes().contentEquals(bytes)); println("PASS native ownership/label and descriptor capture/readback")
    val changed = Bundle(replace).apply {
        putString("before", hash(bytes)); putString("metadata", created.getString("metadata")); putString("after", hash(byteArrayOf(9))); putString("token", "b".repeat(32))
    }
    source.writeBytes(byteArrayOf(9))
    failure = "file-staged"; refused("durable staged replacement", "Controlled interruption: file-staged") { publish(changed) }
    writer = true; refused("writer arrival before publication", "Controlled writer arrival") { publish(changed) }; writer = false
    check(files.inventory(request).getBundle("files")!!.getBundle("games/42/cards/card1.mcd")!!.getString("sha256") == hash(bytes))
    check(publish(changed).getString("sha256") == hash(byteArrayOf(9)))
    refused("foreign game path") { publish(Bundle(replace).apply { putString("path", "games/43/cards/card1.mcd") }) }
    refused("foreign state build") { publish(Bundle(replace).apply { putString("path", "games/42/states-${"1".repeat(16)}-android/SLUS-00561_1.sav") }) }
    refused("traversal into original settings") { publish(Bundle(replace).apply { putString("path", "../settings.ini") }) }
    refused("original BIOS mutation", "read-only") { files.replace(Bundle(request).apply { putString("path", "@bios/ps-22a.bin") }, null, 0, profileData = true) }
    check(files.report().getBundle("settings")!!.getString("sha256") == before.getString("sha256"))
    process.absent()
    val allowed = setOf("owner", "profile.ini", "games/42/cards/card1.mcd")
    profile.walkTopDown().forEach { f ->
        require(f.canonicalPath == f.path)
        val s = Os.lstat(f.path)
        require(OsConstants.S_ISDIR(s.st_mode) || OsConstants.S_ISREG(s.st_mode) && s.st_uid == app.uid && s.st_nlink == 1L && f.path.removePrefix(profile.path + "/") in allowed)
    }
    require(local.listFiles()!!.all { f -> f.name in setOf("source", "captured") && f.canonicalPath == f.path && Os.lstat(f.path).let { it.st_uid == 0 && it.st_nlink == 1L && OsConstants.S_ISREG(it.st_mode) } })
    check(profile.deleteRecursively()); check(local.deleteRecursively())
    println("PASS original settings preserved; only the disposable fixture workspace cleaned")
}
