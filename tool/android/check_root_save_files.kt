package app.broomm.broomm

import android.system.Os
import android.system.OsConstants
import java.io.File
import java.util.concurrent.TimeUnit

fun main(args: Array<String>) {
    require(args.size == 2)
    val root = File(args[1])
    require(Regex("/data/local/tmp/broomm-root-test-[a-f0-9]{32}").matches(root.path))
    if (args[0] == "probe") {
        try { SharedDocumentLock.acquire(File(root, "locks")).use { println("acquired") } }
        catch (_: SharedDocumentBusy) { println("busy") }
        return
    }
    require(args[0] == "run" && !root.exists())
    check(root.mkdir()); Os.chown(root.path, 2000, 2000)
    val label = Os.getxattr(root.path, "security.selinux")
    val files = RootSaveFiles(root, 2000, label, {})
    val token = "a".repeat(32) + "-in"
    val prefix = "files/Broomm/${"b".repeat(32)}/42/saves/"
    val path = prefix + "Minish Cap.srm"
    fun failure(work: () -> Unit) { try { work(); error("Expected refusal") } catch (e: IllegalArgumentException) { } catch (e: IllegalStateException) { check(e.message != "Expected refusal") } }
    try {
        val old = byteArrayOf(1, 2, 3); val next = ByteArray(131072) { 7 }
        val oldHash = RootSaveFiles.digest(old); val nextHash = RootSaveFiles.digest(next)
        files.replace(path, null, oldHash, old, null, token)
        val target = files.path(path)
        Os.chmod(target.path, 416) // 0640, intentionally different from the default.
        val metadata = files.metadata(target)
        files.replace(path, oldHash, nextHash, next, null, token)
        check(files.hash(target) == nextHash && files.metadata(target) == metadata)
        files.replace(path, nextHash, oldHash, old, metadata, token.replace("-in", "-out"))
        check(files.hash(target) == oldHash && files.metadata(target) == metadata)
        failure { files.replace(path, "f".repeat(64), nextHash, next, null, token) }
        check(files.hash(target) == oldHash)
        failure { RootSaveFiles.managedPath("files/Broomm/${"b".repeat(32)}/../other.srm") }
        val linked = File(root, "files/Broomm/${"b".repeat(32)}/43")
        Os.symlink(File(root, "files").path, linked.path)
        failure { files.path("files/Broomm/${"b".repeat(32)}/43/foreign.srm") }
        check(files.hash(target) == oldHash)
        println("PASS: atomic save replacement, UID/GID/mode/label restoration, compare-before-write and linked/path refusal")

        for (point in listOf("staged", "linked")) {
            val relative = prefix + "$point.srm"
            val failing = RootSaveFiles(root, 2000, label, {}, { if (it == point) error("Injected interruption") })
            failure { failing.replace(relative, null, nextHash, next, null, token) }
            files.replace(relative, null, nextHash, next, null, token)
            check(files.hash(files.path(relative)) == nextHash)
            check(Os.lstat(files.path(relative).path).st_nlink == 1L)
        }
        var alive = false
        val expired = RootSaveFiles(root, 2000, label, { check(alive) { "Expired request" } })
        failure { expired.replace(path, oldHash, nextHash, next, null, token) }
        check(files.hash(target) == oldHash)
        println("PASS: interrupted partial stage, interrupted exclusive publication and expired request recovery")

        fun probe(): String {
            val process = ProcessBuilder("/system/bin/app_process", "/system/bin", "app.broomm.broomm.Check_root_save_filesKt", "probe", root.path).start()
            check(process.waitFor(20, TimeUnit.SECONDS))
            val text = process.inputStream.bufferedReader().readText().trim()
            check(process.exitValue() == 0) { process.errorStream.bufferedReader().readText() }
            return text
        }
        SharedDocumentLock.acquire(File(root, "locks")).use { check(probe() == "busy") }
        check(probe() == "acquired")
        println("PASS: held production OS lock excludes a separate Android process and permits it after release")
    } finally {
        // Only this invocation's exclusive disposable root is removed.
        File(root, "files/Broomm/${"b".repeat(32)}/43").delete()
        root.deleteRecursively()
        check(!root.exists())
    }
}
