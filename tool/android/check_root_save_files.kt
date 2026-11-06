package app.broomm.broomm

import android.system.Os
import android.system.OsConstants
import java.io.File
import java.util.concurrent.TimeUnit
import java.util.zip.ZipEntry
import java.util.zip.ZipOutputStream

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

        val rom = File(root, "library/42/content/Minish Cap.gba")
        check(rom.parentFile!!.mkdirs())
        rom.writeBytes(next)
        val romPath = prefix.replace("/saves/", "/rom-${"c".repeat(32)}/") + rom.name
        val staged = files.stageRom(romPath, rom, 0, nextHash)
        check(files.hash(staged) == nextHash && files.metadata(staged).startsWith("2000 2000 400 "))
        failure { files.stageRom(romPath, rom, 0, nextHash) }
        failure { files.removeRom(romPath, oldHash) }
        check(staged.exists() && rom.readBytes().contentEquals(next))
        files.removeRom(romPath, nextHash)
        files.removeRom(romPath, nextHash)
        check(!staged.parentFile!!.exists())
        failure { files.stageRom(romPath, rom, 0, oldHash) }
        check(!staged.exists())
        files.removeRom(romPath, oldHash)
        check(!staged.parentFile!!.exists() && files.hash(target) == oldHash)
        println("PASS: verified GBA ROM staging, existing stage refusal, partial cleanup and save preservation")

        val core = ByteArray(20).apply {
            byteArrayOf(127, 69, 76, 70, 2, 1, 1).copyInto(this)
            this[16] = 3; this[18] = 183.toByte()
        }
        val coreSource = File(root, "reviewed-mgba.so").apply { writeBytes(core) }
        val coreHash = RootSaveFiles.digest(core)
        failure { files.installMgba(coreSource, 0, coreHash, "armeabi-v7a") {} }
        failure { files.installMgba(coreSource, 0, oldHash, "arm64-v8a") {} }
        check(files.mgba() == null)
        val interruptedCore = RootSaveFiles(root, 2000, label, {}, { if (it == "linked") error("Interrupted core publication") })
        failure { interruptedCore.installMgba(coreSource, 0, coreHash, "arm64-v8a") {} }
        check(files.mgba("arm64-v8a", recoverPublication = true) == coreHash)
        val anotherCore = core.copyOf().apply { this[7] = 1 }
        coreSource.writeBytes(anotherCore)
        check(files.installMgba(coreSource, 0, RootSaveFiles.digest(anotherCore), "arm64-v8a") {} == coreHash)
        check(files.mgba("arm64-v8a") == coreHash && files.hash(target) == oldHash)
        println("PASS: mGBA ABI and checksum validation, interrupted install recovery and existing core preservation")

        val profile = "input_device = \"Odin Controller\"\ninput_menu_toggle_btn = \"4\"\n"
        val apk = File(root, "frontend.apk")
        fun profiles(name: String) {
            ZipOutputStream(apk.outputStream()).use { zip ->
                zip.putNextEntry(ZipEntry("assets/autoconfig/android/$name"))
                zip.write(profile.toByteArray()); zip.closeEntry()
                zip.putNextEntry(ZipEntry("assets/autoconfig/linux/ignored.cfg"))
                zip.write(profile.toByteArray()); zip.closeEntry()
            }
        }
        val frontendBuild = "d".repeat(64)
        profiles("../foreign.cfg")
        failure { files.prepareControllerProfiles(apk, frontendBuild) {} }
        check(!files.controllerProfilesReady(frontendBuild))
        profiles("Odin_Controller.cfg")
        val interruptedProfiles = RootSaveFiles(root, 2000, label, {}, { if (it == "staged") error("Interrupted profile publication") })
        failure { interruptedProfiles.prepareControllerProfiles(apk, frontendBuild) {} }
        check(!files.controllerProfilesReady(frontendBuild))
        files.prepareControllerProfiles(apk, frontendBuild) {}
        check(files.controllerProfilesReady(frontendBuild) && files.needsControllerProfiles())
        val managed = files.path("files/Broomm/controller-profiles-$frontendBuild/android/Odin_Controller.cfg")
        check(managed.readText() == profile && files.metadata(managed).startsWith("2000 2000 600 "))
        check(managed.parentFile!!.list()!!.toList() == listOf("Odin_Controller.cfg"))
        check(apk.delete())
        files.prepareControllerProfiles(apk, frontendBuild) {}
        println("PASS: scoped APK controller profiles, interrupted setup recovery, and reuse")

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
