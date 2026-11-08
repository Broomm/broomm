package app.broomm.broomm

import android.content.Context
import android.os.Looper
import android.os.SystemClock
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import org.json.JSONObject
import java.io.File
import java.io.FileOutputStream
import java.security.MessageDigest

/** Development-only app_process fixture; no source/configuration contents are printed. */
fun main(args: Array<String>) {
    try { inspect(args) } catch (e: Throwable) { e.printStackTrace(System.out); kotlin.system.exitProcess(2) }
}

private fun inspect(args: Array<String>) {
    Looper.prepareMainLooper()
    println("FIXTURE pid=${android.os.Process.myPid()}")
    val type = Class.forName("android.app.ActivityThread")
    val thread = type.getMethod("systemMain").invoke(null)
    val system = type.getMethod("getSystemContext").invoke(thread) as Context
    val context = system.createPackageContext("app.broomm.broomm", Context.CONTEXT_IGNORE_SECURITY)
    val pkg = "org.ppsspp.ppsspp"
    val info = context.packageManager.getApplicationInfo(pkg, 0)
    val identity = mapOf<String, Any>("package" to pkg, "user" to 0, "uid" to info.uid, "dataDir" to info.dataDir)
    var deadline = SystemClock.elapsedRealtime() + 30000
    fun live() { check(SystemClock.elapsedRealtime() <= deadline) { "Native PSP fixture expired" } }
    val process = RootPpssppProcess(context, pkg, info.uid, ::live,
        diagnostic = { e -> e.printStackTrace() }, observation = { println("PROCESS $it") })
    val observed = process.observe()
    println(JSONObject().put("state", observed.getString("state")).put("elapsed", observed.getLong("elapsed")))
    require(args.first() in setOf("inspect", "files") && args.size == if (args.first() == "inspect") 1 else 2)
    var failure: String? = null; var refuseWriter = false
    val files = RootPpssppFiles(context, identity, ::live, {
        check(!refuseWriter) { "Controlled writer arrival" }; process.ensureClosed()
    }) { point -> if (point == failure) { failure = null; error("Controlled interruption: $point") } }
    val report = files.report()
    println(JSONObject().apply {
        for (key in report.keySet()) {
            if (key in setOf("config", "controls")) put(key + "Bytes", report.getByteArray(key)!!.size)
            else put(key, report.getString(key))
        }
    })
    if (args.first() == "inspect") return
    val nonce = args[1]; require(Regex("[a-f0-9]{32}").matches(nonce))
    val request = Bundle().apply {
        putString("server", "f".repeat(32)); putString("profile", "e".repeat(32)); putString("ownerNonce", nonce)
        putString("discId", "UCUS98662"); putString("discVersion", "1.00")
        putByteArray("config", "[SystemParam]\nMacAddress = 02:ba:00:00:00:01\n".toByteArray())
        putByteArray("controls", report.getByteArray("controls"))
    }
    fun <T> operation(body: () -> T): T { deadline = SystemClock.elapsedRealtime() + 30000; return body() }
    fun hash(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
    fun rejected(name: String, reason: String? = null, body: () -> Unit) {
        var failed = false
        try { operation(body) } catch (e: Exception) { if (reason != null) check(e.message?.contains(reason) == true) { "Unexpected failure for $name: $e" }; failed = true }
        check(failed) { "Expected refusal: $name" }; println("PASS refusal: $name")
    }
    check(operation { files.initialize(request).getString("status") } == "ready")
    check(operation { files.selection(request).getString("selection") } == "native")
    val local = File("/data/local/tmp/broomm-psp-files-$nonce")
    require(!local.exists()); require(local.mkdir()); Os.chmod(local.path, 448)
    val source = File(local, "source"); source.writeBytes(ByteArray(196608) { (it * 17).toByte() }); Os.chmod(source.path, 384)
    val bytes = source.readBytes(); val expected = hash(bytes)
    val replace = Bundle(request).apply {
        putString("path", "PSP/SAVEDATA/UCUS98662BROOMMTEST/DATA.BIN")
        putString("after", expected); putString("token", "a".repeat(32))
    }
    fun publish(r: Bundle = replace): Bundle = ParcelFileDescriptor.open(source, ParcelFileDescriptor.MODE_READ_ONLY).use {
        operation { files.replace(r, it, 0) }
    }
    failure = "file-stage-bytes"
    rejected("partial private incoming stream", "Controlled interruption: file-stage-bytes") { publish() }
    failure = "file-linked"
    rejected("exclusive link before acknowledgement", "Controlled interruption: file-linked") { publish() }
    val created = publish()
    check(created.getString("sha256") == expected && created.getLong("bytes") == bytes.size.toLong())
    check(created.getString("metadata")!!.split(' ').let { it[0] == info.uid.toString() && it[1] == report.getString("externalGid") && it[2] == "660" && it.last() == "1" })
    println("PASS partial stream and linked publication replay with native owner/mode/label")
    val captured = File(local, "captured")
    val read = Bundle(request).apply {
        putString("path", replace.getString("path")); putString("sha256", expected)
        putString("metadata", created.getString("metadata")); putLong("bytes", created.getLong("bytes"))
    }
    val captureFd = Os.open(captured.path, OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_WRONLY or OsConstants.O_NOFOLLOW, 384)
    val captureDescriptor = try { ParcelFileDescriptor.dup(captureFd) } finally { Os.close(captureFd) }
    captureDescriptor.use {
        operation { files.capture(read, it, 0) }
    }
    check(captured.readBytes().contentEquals(bytes)); println("PASS descriptor-backed capture and readback")
    val pointerOriginal = files.pointerBytes()
    val selection = Bundle(request).apply { putString("selection", "profile"); putString("before", hash(pointerOriginal)); putString("token", "b".repeat(32)) }
    failure = "pointer-published"
    rejected("selection published before acknowledgement", "Controlled interruption: pointer-published") { files.select(selection) }
    operation { files.select(selection) }
    check(operation { files.selection(request).getString("selection") } == "profile")
    val restore = Bundle(request).apply { putString("selection", "native"); putString("before", hash(files.memoryPath(request).toByteArray())); putString("token", "c".repeat(32)) }
    operation { files.select(restore) }
    check(files.pointerBytes().contentEquals(pointerOriginal)); println("PASS lost pointer reply and exact standalone selection restoration")
    val changed = Bundle(replace).apply { putString("before", expected); putString("after", hash(byteArrayOf(9))); putString("metadata", created.getString("metadata")); putString("token", "d".repeat(32)) }
    source.writeBytes(byteArrayOf(9))
    failure = "file-staged"
    rejected("held staged replacement", "Controlled interruption: file-staged") { publish(changed) }
    refuseWriter = true
    rejected("writer arrival before publication") { publish(changed) }
    refuseWriter = false
    check(operation { files.inventory(request).getBundle("files")!!.getBundle(replace.getString("path")!!)!!.getString("sha256") } == expected)
    val updated = publish(changed); check(updated.getString("sha256") == hash(byteArrayOf(9)))
    val unsafe = Bundle(replace).apply { putString("path", "PSP/SAVEDATA/../SYSTEM/ppsspp.ini") }
    rejected("traversal") { publish(unsafe) }
    val foreign = Bundle(replace).apply { putString("path", "PSP/SAVEDATA/ULUS12345/DATA.BIN") }
    rejected("another game") { publish(foreign) }
    val linked = File(files.memoryPath(request).replace("/storage/emulated/0", "/data/media/0"), replace.getString("path")!!)
    val extra = File(linked.parentFile, "BROOMM_EXTRA_LINK"); require(!extra.exists()); Os.link(linked.path, extra.path)
    rejected("extra public link") { files.inventory(request) }
    Os.remove(extra.path)
    val deletion = Bundle(request).apply { putString("path", replace.getString("path")); putString("before", updated.getString("sha256")); putString("metadata", updated.getString("metadata")); putString("token", "e".repeat(32)) }
    rejected("stale metadata after extra-link removal", "Native PSP file identity changed") { files.replace(deletion, null, 0) }
    val fresh = operation { files.inventory(request).getBundle("files")!!.getBundle(replace.getString("path")!!)!! }
    check(fresh.getString("sha256") == updated.getString("sha256"))
    deletion.putString("metadata", fresh.getString("metadata"))
    operation { files.replace(deletion, null, 0) }
    check(operation { files.inventory(request).getBundle("files")!!.isEmpty })
    check(files.pointerBytes().contentEquals(pointerOriginal))
    val memoryPhysical = File(files.memoryPath(request).replace("/storage/emulated/0", "/data/media/0"))
    val bulk = File(memoryPhysical, "PSP/SAVEDATA/UCUS98662BROOMMTEST")
    val nativeLabel = report.getString("externalLabel")!!.toByteArray() + byteArrayOf(0)
    for (i in 0 until 600) {
        val f = File(bulk, "INVENTORY_${i.toString().padStart(4, '0')}_" + "x".repeat(80))
        require(f.createNewFile()); f.writeBytes(byteArrayOf(1)); Os.chown(f.path, info.uid, report.getString("externalGid")!!.toInt()); Os.chmod(f.path, 432); Os.setxattr(f.path, "security.selinux", nativeLabel, 0)
    }
    val found = mutableSetOf<String>(); var pages = 0; var cursor: String? = null
    do {
        val pageRequest = Bundle(request).apply { putString("cursor", cursor) }
        val page = operation { files.profileInventory(pageRequest) }
        val parcel = android.os.Parcel.obtain()
        try { parcel.writeBundle(page); check(parcel.dataSize() <= 256 * 1024) } finally { parcel.recycle() }
        val entries = page.getBundle("files")!!
        check(entries.keySet().all { found.add(it) })
        cursor = page.getString("next"); pages++; check(pages <= 10)
    } while (cursor != null)
    check(found.size == 602 && pages > 1)
    println("PASS complete bounded Binder inventories: ${found.size} files in $pages pages")
    FileOutputStream(source).use { out -> val buffer = ByteArray(65536) { (it * 19).toByte() }; repeat(256) { out.write(buffer) }; out.fd.sync() }
    fun fileHash(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input -> val buffer = ByteArray(65536); while (true) { val n = input.read(buffer); if (n < 0) break; digest.update(buffer, 0, n) } }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    val largeHash = fileHash(source)
    val large = Bundle(request).apply { putString("path", "PSP/PPSSPP_STATE/UCUS98662_1.00_0.ppst"); putString("after", largeHash); putString("token", "f".repeat(32)) }
    val largeEntry = publish(large); check(largeEntry.getLong("bytes") == 16L * 1024 * 1024 && largeEntry.getString("sha256") == largeHash)
    println("PASS streamed 16 MiB state publication without a Binder byte array")
    println(JSONObject().put("result", "passed").put("ownerNonce", nonce).put("memoryStick", files.memoryPath(request)).put("localFixture", local.path))
}
