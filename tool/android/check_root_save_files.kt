package app.broomm.broomm

import android.system.Os
import android.os.Bundle
import android.os.Parcel
import android.os.ParcelFileDescriptor
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
    require(args[0] in setOf("run", "core-memory") && !root.exists())
    check(root.mkdir()); Os.chown(root.path, 2000, 2000)
    val label = Os.getxattr(root.path, "security.selinux")
    val files = RootSaveFiles(root, 2000, label, {})
    val token = "a".repeat(32) + "-in"
    val prefix = "files/Broomm/${"b".repeat(32)}/42/saves/"
    val path = prefix + "Minish Cap.srm"
    fun failure(work: () -> Unit) { try { work(); error("Expected refusal") } catch (e: IllegalArgumentException) { } catch (e: IllegalStateException) { check(e.message != "Expected refusal") } }
    try {
        if (args[0] == "core-memory") {
            check(Runtime.getRuntime().maxMemory() == 32L * 1024 * 1024) { "Run core-memory directly through dalvikvm with -Xmx32m -Xms8m." }
            checkLargeCoreStorage(root, label)
            return
        }
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

        val statePath = prefix.replace("/saves/", "/states/states-${"d".repeat(16)}-android/") + "Minish Cap.state2"
        RootSaveFiles.managedPath(statePath, saveOnly = true)
        val largeState = ByteArray(2 * 1024 * 1024 + 31) { (it % 251).toByte() }
        val stateHash = RootSaveFiles.digest(largeState)
        files.replace(statePath, null, stateHash, largeState, null, token)
        check(files.hash(files.path(statePath), RootSaveFiles.MAX_STATE_BYTES) == stateHash)
        failure { files.replace(path, oldHash, stateHash, largeState, null, token) }
        failure { RootSaveFiles.managedPath(statePath.replace("states-" + "d".repeat(16) + "-android/", "")) }
        val stateDir = statePath.substringBeforeLast('/')
        val selected = listOf(mapOf("path" to prefix.removeSuffix("/"), "exact" to "Minish Cap.srm"),
            mapOf("path" to stateDir, "prefix" to "Minish Cap", "pattern" to "bounded-by-native-selector"))
        val foreign = statePath.replace("Minish Cap.state2", "Minish Cap Extra.state2")
        files.replace(foreign, null, oldHash, old, null, token)
        val inventory = files.inventory(selected)
        check(inventory.keys == setOf(path, statePath) && inventory.getValue(statePath).sha256 == stateHash)
        val transferSource = File(root, "transfer-source").apply { writeBytes(largeState) }
        val parcel = Parcel.obtain()
        val inputFd = ParcelFileDescriptor.open(transferSource, ParcelFileDescriptor.MODE_READ_ONLY)
        val transferred = try {
            parcel.writeBundle(Bundle().apply { putParcelable("transfer", inputFd) })
            check(parcel.dataSize() < 4096) // State bytes never occupy a Binder transaction.
            parcel.setDataPosition(0)
            parcel.readBundle(RootSaveFiles::class.java.classLoader)!!.getParcelable<ParcelFileDescriptor>("transfer")!!
        } finally { inputFd.close(); parcel.recycle() }
        check(RootSaveTransfer.read(transferred, 0, RootSaveFiles.MAX_STATE_BYTES) {}.contentEquals(largeState))
        failure { RootSaveTransfer.read(ParcelFileDescriptor.open(transferSource, ParcelFileDescriptor.MODE_READ_ONLY), 0, 262144) {} }
        val destination = File(root, "transfer-target").apply { check(createNewFile()) }
        RootSaveTransfer.write(ParcelFileDescriptor.open(destination, ParcelFileDescriptor.MODE_WRITE_ONLY), 0, largeState) {}
        check(destination.readBytes().contentEquals(largeState))
        failure { RootSaveTransfer.write(ParcelFileDescriptor.open(destination, ParcelFileDescriptor.MODE_WRITE_ONLY), 0, old) {} }
        val interruptedState = RootSaveFiles(root, 2000, label, {}, { if (it == "linked") error("Interrupted state publication") })
        val interruptedPath = statePath.replace(".state2", ".state3")
        failure { interruptedState.replace(interruptedPath, null, stateHash, largeState, null, token) }
        files.replace(interruptedPath, null, stateHash, largeState, null, token)
        check(files.hash(files.path(interruptedPath), RootSaveFiles.MAX_STATE_BYTES) == stateHash)
        check(Os.lstat(files.path(interruptedPath).path).st_nlink == 1L)
        println("PASS: large state descriptors, bounded parcels, strict inventory, group isolation and interrupted state publication")

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

        val gameboyBase = "files/Broomm/${"b".repeat(32)}/44/"
        val gameboySave = gameboyBase + "saves/Pokemon.srm"
        val gameboyClock = gameboyBase + "saves/Pokemon.rtc"
        files.replace(gameboySave, null, oldHash, old, null, token)
        files.replace(gameboyClock, null, nextHash, next, null, token)
        val unrelatedClock = gameboyBase + "saves/Pokemon Extra.rtc"
        files.replace(unrelatedClock, null, oldHash, old, null, token)
        val gameboyInventory = files.inventory(listOf(mapOf(
            "path" to gameboyBase + "saves", "prefix" to "Pokemon", "pattern" to "bounded-by-native-selector")))
        check(gameboyInventory.keys == setOf(gameboySave, gameboyClock))
        check(gameboyInventory.getValue(gameboyClock).sha256 == nextHash)
        files.replace(gameboyClock, nextHash, oldHash, old, files.metadata(files.path(gameboyClock)), token)
        check(files.hash(files.path(gameboyClock)) == oldHash && files.hash(files.path(unrelatedClock)) == oldHash)
        val gameboyRom = File(root, "library/44/content/Pokemon.gbc")
        check(gameboyRom.parentFile!!.mkdirs()); gameboyRom.writeBytes(next)
        val gameboyRomPath = gameboyBase + "rom-${"c".repeat(32)}/Pokemon.gbc"
        val stagedGameboy = files.stageRom(gameboyRomPath, gameboyRom, 0, nextHash)
        check(files.hash(stagedGameboy) == nextHash)
        files.removeRom(gameboyRomPath, nextHash)
        check(!stagedGameboy.exists() && files.hash(files.path(gameboySave)) == oldHash)
        println("PASS: Game Boy SRAM/RTC selectors, unrelated-clock preservation and GBC ROM staging")

        for (extension in listOf("a26", "bin", "pce")) {
            val cartridgeSource = File(root, "library/44/content/Cartridge.$extension")
            check(cartridgeSource.parentFile!!.exists() || cartridgeSource.parentFile!!.mkdirs())
            cartridgeSource.writeBytes(next)
            val cartridgePath = "files/Broomm/${"b".repeat(32)}/44/rom-${"c".repeat(32)}/Cartridge.$extension"
            val copy = files.stageRom(cartridgePath, cartridgeSource, 0, nextHash)
            check(files.hash(copy) == nextHash)
            files.removeRom(cartridgePath, nextHash)
            check(!copy.exists() && cartridgeSource.readBytes().contentEquals(next))
        }
        failure { RootSaveFiles.romPath("files/Broomm/${"b".repeat(32)}/44/rom-${"c".repeat(32)}/Disc.chd") }
        println("PASS: Atari/PCE cartridge staging, source preservation and unsupported disc refusal")

        val core = ByteArray(20).apply {
            byteArrayOf(127, 69, 76, 70, 2, 1, 1).copyInto(this)
            this[16] = 3; this[18] = 183.toByte()
        }
        val coreSource = File(root, "reviewed-mgba.so").apply { writeBytes(core) }
        val coreHash = RootSaveFiles.digest(core)
        failure { files.installCore(coreSource, 0, coreHash, "armeabi-v7a") {} }
        failure { files.installCore(coreSource, 0, oldHash, "arm64-v8a") {} }
        check(files.core() == null)
        val interruptedCore = RootSaveFiles(root, 2000, label, {}, { if (it == "linked") error("Interrupted core publication") })
        failure { interruptedCore.installCore(coreSource, 0, coreHash, "arm64-v8a") {} }
        check(files.core("arm64-v8a", recoverPublication = true) == coreHash)
        val anotherCore = core.copyOf().apply { this[7] = 1 }
        coreSource.writeBytes(anotherCore)
        check(files.installCore(coreSource, 0, RootSaveFiles.digest(anotherCore), "arm64-v8a") {} == coreHash)
        check(files.core("arm64-v8a") == coreHash && files.hash(target) == oldHash)
        coreSource.writeBytes(core)
        check(files.installCore(coreSource, 0, coreHash, "arm64-v8a", coreName = "snes9x") {} == coreHash)
        check(files.core("arm64-v8a", coreName = "snes9x") == coreHash && files.core("arm64-v8a") == coreHash)
        for (name in listOf("gambatte", "stella", "mednafen_pce_fast")) {
            check(files.installCore(coreSource, 0, coreHash, "arm64-v8a", coreName = name) {} == coreHash)
            check(files.core("arm64-v8a", coreName = name) == coreHash)
        }
        failure { RootSaveFiles.corePath("unknown") }
        println("PASS: reviewed core ABIs and checksums, interrupted install recovery and existing core preservation")

        checkLargeCoreStorage(root, label)

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

        val menuFiles = listOf("assets/ozone/regular.ttf", "assets/ozone/bold.ttf",
            "assets/ozone/png/icons/settings.png")
        profiles("Odin_Controller.cfg")
        check(!files.needsFrontendAssets { apk })
        ZipOutputStream(apk.outputStream()).use { zip ->
            for (name in menuFiles) {
                zip.putNextEntry(ZipEntry("assets/$name"))
                zip.write(1); zip.closeEntry()
            }
        }
        check(files.needsFrontendAssets { apk })
        for (name in menuFiles.dropLast(1)) {
            File(root, name).apply { parentFile!!.mkdirs(); writeText("font") }
        }
        check(files.needsFrontendAssets { apk })
        val icon = File(root, menuFiles.last())
        icon.parentFile!!.mkdirs()
        check(icon.createNewFile())
        check(files.needsFrontendAssets { apk })
        icon.writeText("icon")
        check(!files.needsFrontendAssets { error("A complete install needs no APK read") })
        println("PASS: stock menu resources, incomplete extraction, and alternate APK layouts")

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

/** Real descriptors and publications; the 80 MiB payload is never allocated as an array. */
private fun checkLargeCoreStorage(parent: File, label: ByteArray) {
    val root = File(parent, "streaming-core").apply { check(mkdir()); Os.chown(path, 2000, 2000) }
    val files = RootSaveFiles(root, 2000, label, {})
    fun failure(work: () -> Unit) { try { work(); error("Expected refusal") } catch (e: IllegalArgumentException) { } catch (e: IllegalStateException) { check(e.message != "Expected refusal") } }
    val source = File(root, "reviewed-large-core.so")
    val block = ByteArray(65536) { 7 }
    val header = byteArrayOf(127, 69, 76, 70, 2, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 3, 0, 183.toByte(), 0)
    val hash = java.security.MessageDigest.getInstance("SHA-256")
    val chunks = 80 * 1024 * 1024 / block.size
    source.outputStream().use { out ->
        repeat(chunks) { index ->
            if (index == 0) header.copyInto(block) else block.fill(7)
            out.write(block); hash.update(block)
        }
    }
    val expected = hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    val target = files.path(RootSaveFiles.corePath("mgba"))
    val stage = File(target.parentFile, ".${target.name}.broomm-${expected.take(32)}-in")
    var readChunks = 0
    val cancelled = RootSaveFiles(root, 2000, label, {}, {
        if (it == "core-chunk" && ++readChunks == chunks + 3) error("Cancelled during core copy")
    })
    failure { cancelled.installCore(source, 0, expected, "arm64-v8a") {} }
    check(files.core() == null && stage.isFile && stage.length() < source.length())

    // A retry reclaims only its deterministic stage. A new writer still prevents publication.
    var closedChecks = 0
    failure { files.installCore(source, 0, expected, "arm64-v8a") {
        if (++closedChecks == 2) error("Writer started before publication")
    } }
    check(files.core() == null && stage.length() == source.length())
    check(files.installCore(source, 0, expected, "arm64-v8a") {} == expected)
    check(files.core("arm64-v8a") == expected && !stage.exists() && source.length() == 80L * 1024 * 1024)

    // Replace the source name during an open read, with a forced mtime tie.
    Os.remove(target.path)
    val tiedTime = 1700000000000L
    check(source.setLastModified(tiedTime))
    val retained = File(root, "retained-source.so")
    var swapped = false
    val changed = RootSaveFiles(root, 2000, label, {}, {
        if (it == "core-chunk" && !swapped) {
            swapped = true
            check(source.renameTo(retained))
            source.writeBytes(header)
            check(source.setLastModified(tiedTime))
        }
    })
    failure { changed.installCore(source, 0, expected, "arm64-v8a") {} }
    check(swapped && files.core() == null && !stage.exists())
    check(source.delete() && retained.renameTo(source))

    // An independent destination appearing after staging is retained, never replaced.
    val other = File(root, "small-core.so").apply { writeBytes(header) }
    val otherHash = RootSaveFiles.digest(header)
    files.installCore(other, 0, otherHash, "arm64-v8a", coreName = "snes9x") {}
    val existing = files.path(RootSaveFiles.corePath("snes9x"))
    closedChecks = 0
    failure { files.installCore(source, 0, expected, "arm64-v8a") {
        if (++closedChecks == 2) Os.link(existing.path, target.path)
    } }
    check(files.hash(target) == otherHash && files.hash(existing) == otherHash)
    Os.remove(target.path)
    check(files.core("arm64-v8a", coreName = "snes9x") == otherHash)
    println("PASS: 80 MiB streamed core install/inspection, cancelled-copy retry, live-writer refusal, tied-time source swap and exclusive destination preservation")
}
