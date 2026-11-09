package app.broomm.broomm

import android.system.Os
import android.os.Bundle
import android.os.Parcel
import android.os.ParcelFileDescriptor
import android.system.OsConstants
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.ByteBuffer
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
        val cube = File(root, "cube.rvz")
        cube.writeBytes(ByteArray(0x58 + 128).also { header ->
            ByteBuffer.wrap(header).putInt(0x52565a01).putInt(0x58 + 0x1c, 0xc2339f3d.toInt())
            "GLME01".toByteArray().copyInto(header, 0x58)
            header[0x58 + 7] = 2
        })
        check(readDolphinDisc(cube, "ngc") == DolphinDisc("GLME01", 2))
        failure { readDolphinDisc(cube, "wii") }
        val wii = File(root, "wii.wbfs")
        val block = 1 shl 21
        val partition = ByteArray(block + 128).also { header ->
            ByteBuffer.wrap(header).putInt(0x57424653).putInt(512 + 0x18, 0x5d1c9ea3)
                .putShort(512 + 256, 1)
            header[8] = 9; header[9] = 21; header[12] = 1
            "RSPE01".toByteArray().copyInto(header, 512)
            header.copyInto(header, block, 512, 512 + 128)
        }
        wii.writeBytes(partition)
        check(readDolphinDisc(wii, "wii") == DolphinDisc("RSPE01", 0))
        partition[13] = 2
        wii.writeBytes(partition)
        failure { readDolphinDisc(wii, "wii") }
        partition[13] = 0
        partition[block + 3] = 'J'.code.toByte()
        wii.writeBytes(partition)
        failure { readDolphinDisc(wii, "wii") }
        check(RootSaveTransfer.readExact(ByteArrayInputStream(next), next.size) {}.contentEquals(next))
        failure { RootSaveTransfer.readExact(ByteArrayInputStream(old), old.size + 1) {} }
        failure { RootSaveTransfer.readExact(ByteArrayInputStream(old), old.size - 1) {} }
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
        checkProgressWriterClosure(root, label)
        checkFlycastStorage(root, label)
        checkResourceInterruptedCleanup(root, label)
        checkFlycastLargeProgress(root, label)

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
        val cartridgeTransaction = "e".repeat(32)
        val preparedRom = File(root, "android/shared-session/$cartridgeTransaction/cartridge-Abc123/Sonic.md")
        check(preparedRom.parentFile!!.mkdirs()); preparedRom.writeBytes(next)
        val preparedRomPath = prefix.replace("/saves/", "/rom-$cartridgeTransaction/") + preparedRom.name
        failure { files.stageRom(preparedRomPath, preparedRom, 0, nextHash) }
        failure { files.stageRom(preparedRomPath.replace(cartridgeTransaction, "f".repeat(32)), preparedRom, 0, nextHash, prepared = true) }
        val preparedCopy = files.stageRom(preparedRomPath, preparedRom, 0, nextHash, prepared = true)
        check(files.hash(preparedCopy) == nextHash && preparedRom.readBytes().contentEquals(next))
        files.removeRom(preparedRomPath, nextHash)
        check(!preparedCopy.exists() && preparedRom.exists())
        check(!staged.exists())
        files.removeRom(romPath, oldHash)
        check(!staged.parentFile!!.exists() && files.hash(target) == oldHash)
        println("PASS: verified GBA ROM staging, existing stage refusal, partial cleanup and save preservation")

        val launchData = "/data/user/0/com.retroarch.aarch64"
        val launchBase = "$launchData/files/Broomm/${"b".repeat(32)}/42"
        val launchConfig = "$launchBase/config-${"a".repeat(32)}.cfg"
        val launchContent = "/data/user/0/app.broomm.broomm/files/broomm/library/${"d".repeat(32)}/42/content"
        fun launch(core: String, name: String, selected: String, config: String? = launchConfig, content: String = launchContent) =
            validateRootRetroArchLaunch(core, "com.retroarch.aarch64", launchData,
                "$launchBase/rom-${"c".repeat(32)}/$name", config, content, "$content/$selected")
        for ((core, name) in listOf("mgba" to "Game.gba", "snes9x" to "Game.sfc", "gambatte" to "Game.gbc",
            "stella" to "Game.a26", "mednafen_pce_fast" to "Game.pce", "genesis_plus_gx" to "Game.md",
            "genesis_plus_gx" to "Game.sms", "genesis_plus_gx" to "Game.gg", "picodrive" to "Game.32x",
            "mupen64plus_next" to "Game.z64", "mupen64plus_next" to "Game.v64", "mupen64plus_next" to "Game.n64",
            "mesen" to "Game.nes", "mesen" to "Game.unf", "mesen" to "Game.unif",
            "virtualjaguar" to "Game.j64", "virtualjaguar" to "Game.jag", "virtualjaguar" to "Game.rom",
            "virtualjaguar" to "Game.abs", "virtualjaguar" to "Game.cof", "virtualjaguar" to "Game.bin", "virtualjaguar" to "Game.prg",
            "mednafen_lynx" to "Game.lnx", "mednafen_lynx" to "Game.lyx", "mednafen_lynx" to "Game.bll", "mednafen_lynx" to "Game.o")) {
            launch(core, name, name)
            launch(core, name, "Game.ZIP")
            failure { launch(core, name, "Other.zip") }
        }
        failure { launch("genesis_plus_gx", "Game.md", "Game.gen") }
        failure { launch("genesis_plus_gx", "Game.md", "Game.zip", content = launchContent.replace("/42/", "/43/")) }
        failure { launch("genesis_plus_gx", "Game.md", "Game.zip", config = launchConfig.replace("b".repeat(32), "f".repeat(32))) }
        failure { launch("genesis_plus_gx", "Game.md", "Game.zip", config = null) }
        failure { launch("mupen64plus_next", "Game.gba", "Game.zip") }
        failure { launch("mesen", "Game.fds", "Game.zip") }
        failure { launch("mgba", "Game.nes", "Game.zip") }
        failure { launch("virtualjaguar", "Game.chd", "Game.zip") }
        failure { launch("virtualjaguar", "Game.cue", "Game.zip") }
        failure { launch("mgba", "Game.md", "Game.zip") }
        failure { launch("mednafen_lynx", "Game.gba", "Game.zip") }
        failure { launch("mgba", "Game.lnx", "Game.zip") }
        launch("mednafen_saturn", "Disc.chd", "Disc.chd")
        failure { launch("mednafen_saturn", "Disc.iso", "Disc.iso") }
        failure { launch("mednafen_saturn", "Disc.chd", "Other.chd") }
        launch("fbneo", "simpsons2p.zip", "simpsons2p.zip")
        launch("fbneo", "SIMPSONS2P.ZIP", "SIMPSONS2P.ZIP")
        failure { launch("fbneo", "simpsons2p.zip", "other.zip") }
        failure { launch("fbneo", "Game Name.zip", "Game Name.zip") }
        failure { launch("fbneo", "simpsons2p.7z", "simpsons2p.7z") }
        failure { launch("mgba", "simpsons2p.zip", "simpsons2p.zip") }
        println("PASS: rooted launch validation accepts prepared ZIP stems and preserves core, original filename, game and configuration identity")

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

        for (extension in listOf("a26", "bin", "pce", "md", "gen", "smd", "sms", "sg", "gg", "32x", "nes", "unf", "unif", "j64", "jag", "rom", "abs", "cof", "prg", "lnx", "lyx", "bll", "o")) {
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
        failure { RootSaveFiles.romPath("files/Broomm/${"b".repeat(32)}/44/rom-${"c".repeat(32)}/Disk.fds") }
        println("PASS: Atari/PCE/Sega/NES/Jaguar/Lynx cartridge staging, source preservation and unsupported disc/FDS refusal")
        checkN64Storage(root, label)
        checkLynxFirmware(root, label)
        checkFbneoStorage(root, label)
        checkOperaStorage(root, label)
        checkSaturnStorage(root, label)

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
        for (name in listOf("gambatte", "stella", "mednafen_pce_fast", "genesis_plus_gx", "picodrive", "mupen64plus_next", "mesen", "virtualjaguar", "mednafen_saturn")) {
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

private fun checkProgressWriterClosure(root: File, label: ByteArray) {
    fun refused(work: () -> Unit) {
        try { work(); error("Expected writer refusal") }
        catch (e: IllegalStateException) { check(e.message != "Expected writer refusal") }
    }
    val relative = "files/Broomm/${"9".repeat(32)}/52/saves/Closure.srm"
    val token = "8".repeat(32) + "-in"
    val old = byteArrayOf(10, 20, 30)
    val next = ByteArray(131072) { 42 }
    val oldHash = RootSaveFiles.digest(old)
    val nextHash = RootSaveFiles.digest(next)
    val plain = RootSaveFiles(root, 2000, label, {})
    plain.replace(relative, null, oldHash, old, null, token)
    var writer = true
    val guarded = RootSaveFiles(root, 2000, label, {},
        writerClosed = { check(!writer) { "Writer is active" } })
    refused { guarded.replace(relative, oldHash, nextHash, next, null, token) }
    refused { guarded.replace(relative, null, oldHash, old, null, token) }
    check(plain.hash(plain.path(relative)) == oldHash)
    check(!File(plain.path(relative).parentFile, ".Closure.srm.broomm-$token").exists())

    writer = false
    val arriving = RootSaveFiles(root, 2000, label, {},
        checkpoint = { if (it == "staged") writer = true },
        writerClosed = { check(!writer) { "Writer arrived during staging" } })
    refused { arriving.replace(relative, oldHash, nextHash, next, null, token) }
    check(plain.hash(plain.path(relative)) == oldHash)
    check(File(plain.path(relative).parentFile, ".Closure.srm.broomm-$token").exists())
    writer = false
    guarded.replace(relative, oldHash, nextHash, next, null, token)
    check(plain.hash(plain.path(relative)) == nextHash)
    writer = true
    refused { guarded.replace(relative, nextHash, null, null, null, token.replace("-in", "-out")) }
    check(plain.hash(plain.path(relative)) == nextHash)
    println("PASS: native writer blocks save replacement, idempotent replay and removal; writer arrival before publication retains old save and retry stage")

    writer = false
    val source = File(root, "library/52/content/Closure.gba")
    check(source.parentFile!!.mkdirs()); source.writeBytes(next)
    val romPath = relative.substringBefore("/saves/") + "/rom-${"7".repeat(32)}/Closure.gba"
    val romArrival = RootSaveFiles(root, 2000, label, {},
        checkpoint = { if (it == "rom-staged") writer = true },
        writerClosed = { check(!writer) { "Writer arrived during ROM staging" } })
    refused { romArrival.stageRom(romPath, source, 0, nextHash) }
    val target = plain.path(romPath)
    check(!target.exists() && File(target.parentFile, ".pending").exists())
    refused { guarded.removeRom(romPath, nextHash) }
    check(File(target.parentFile, ".pending").exists() && source.readBytes().contentEquals(next))
    writer = false
    guarded.removeRom(romPath, nextHash)
    guarded.stageRom(romPath, source, 0, nextHash)
    writer = true
    refused { guarded.removeRom(romPath, nextHash) }
    check(target.exists() && plain.hash(target) == nextHash)
    writer = false
    guarded.removeRom(romPath, nextHash)
    check(!target.parentFile!!.exists() && source.readBytes().contentEquals(next))
    println("PASS: native writer arrival blocks ROM publication and pending/published cleanup; closed retry preserves library source")
}

private fun checkOperaStorage(root: File, label: ByteArray) {
    fun refused(work: () -> Unit) {
        try { work(); error("Expected Opera refusal") }
        catch (_: IllegalArgumentException) { }
        catch (e: IllegalStateException) { check(e.message != "Expected Opera refusal") }
    }
    val files = RootSaveFiles(root, 2000, label, {}, coreName = "opera")
    val base = "files/Broomm/${"b".repeat(32)}/48"
    val token = "9".repeat(32) + "-in"
    val nvram = ByteArray(32768) { 17 }
    val hash = RootSaveFiles.digest(nvram)
    val selected = listOf("opera/per_game/Disc.0.srm", "opera/per_game/Disc.7.srm", "opera/shared/nvram.4.srm")
    for (name in selected + "opera/per_game/Foreign.1.srm")
        files.replace("$base/saves/$name", null, hash, nvram, null, token)
    val areas = listOf(mapOf("path" to "$base/saves", "operaStem" to "Disc"))
    check(files.inventory(areas).keys == selected.map { "$base/saves/$it" }.toSet())
    refused { files.replace("$base/saves/opera/per_game/Disc.1.srm", null,
        RootSaveFiles.digest(byteArrayOf(1)), byteArrayOf(1), null, token) }
    val short = files.path("$base/saves/opera/per_game/Disc.0.srm")
    short.writeBytes(byteArrayOf(1))
    refused { files.inventory(areas) }
    short.writeBytes(nvram)
    refused { RootSaveFiles(root, 2000, label, {}).inventory(areas) }
    refused { files.inventory(listOf(mapOf("path" to "$base/saves", "operaStem" to "../Disc"))) }
    refused { RootSaveFiles.managedPath("$base/saves/opera/per_game/Disc.0.srm") }
    refused { RootSaveFiles.managedPath("$base/saves/opera/per_game/Disc.10.srm", core = "opera") }
    refused { RootSaveFiles.managedPath("$base/saves/opera/per_game/Disc.0.srm.tmp", core = "opera") }
    val config = "$base/config-${"8".repeat(32)}.cfg"
    val firmware = "$base/system-${"8".repeat(32)}/panafz10.bin"
    val payload = ByteArray(1048576) { 29 }
    val biosHash = RootSaveFiles.digest(payload)
    refused { files.operaFirmware(firmware, config, null, biosHash, byteArrayOf(1), token) {} }
    refused { RootSaveFiles(root, 2000, label, {}).operaFirmware(firmware, config, null, biosHash, payload, token) {} }
    refused { files.operaFirmware(firmware.replace("system-8", "system-7"), config, null, biosHash, payload, token) {} }
    val lost = RootSaveFiles(root, 2000, label, {}, { if (it == "linked") error("Lost Opera BIOS reply") }, "opera")
    refused { lost.operaFirmware(firmware, config, null, biosHash, payload, token) {} }
    files.operaFirmware(firmware, config, null, biosHash, payload, token) {}
    check(files.hash(files.path(firmware), 1048576) == biosHash)
    refused { files.operaFirmware(firmware, config, biosHash, null, null, token.replace("-in", "-out")) { error("Writer alive") } }
    files.path(firmware).writeBytes(ByteArray(1048576) { 30 })
    refused { files.operaFirmware(firmware, config, biosHash, null, null, token.replace("-in", "-out")) {} }
    check(files.path(firmware).exists() && files.inventory(areas).size == 3)
    files.path(firmware).writeBytes(payload)
    repeat(2) { files.operaFirmware(firmware, config, biosHash, null, null, token.replace("-in", "-out")) {} }
    check(!files.path(firmware).exists() && files.inventory(areas).size == 3)
    val optionRoot = File(root, "options").apply { check(mkdir()); Os.chown(path, 2000, 2000) }
    val optionFile = File(optionRoot, "Opera.opt").apply { writeText("opera_nvram_version = \"7\"\n"); Os.chown(path,2000,2000);Os.chmod(path,384) }
    check(String(files.options(optionFile.path,listOf(optionRoot))!!) == optionFile.readText())
    check(files.options(File(optionRoot,"absent.opt").path,listOf(optionRoot)) == null)
    check(files.options(File(optionRoot,"missing/Opera.opt").path,listOf(optionRoot)) == null)
    refused { files.options(File(optionFile,"child.opt").path,listOf(optionRoot)) }
    val linkedDirectory = File(optionRoot,"linked-directory")
    Os.symlink(optionRoot.path,linkedDirectory.path)
    refused { files.options(File(linkedDirectory,"Opera.opt").path,listOf(optionRoot)) }
    Os.remove(linkedDirectory.path)
    refused { files.options(optionFile.path,listOf(File(root,"foreign"))) }
    val link = File(optionRoot,"linked.opt");Os.symlink(optionFile.path,link.path)
    refused { files.options(link.path,listOf(optionRoot)) };Os.remove(link.path)
    java.io.RandomAccessFile(optionFile,"rw").use { it.setLength(262145) }
    refused { files.options(optionFile.path,listOf(optionRoot)) }
    println("PASS: Opera native NVRAM versions/modes, truncated-save refusal, scoped options, exact selected BIOS, interrupted publication, writer/edited-resource preservation and idempotent cleanup")

    val source = File(root,"library/48/content/Disc.iso").apply { check(parentFile!!.mkdirs()) }
    java.io.RandomAccessFile(source,"rw").use { it.setLength(1024L * 1024 * 1024) }
    fun streamedHash(file:File):String {
        val d=java.security.MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input -> val buffer=ByteArray(65536);while(true){val n=input.read(buffer);if(n<0)break;d.update(buffer,0,n)} }
        return d.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    val discHash=streamedHash(source)
    val discPath="$base/rom-${"7".repeat(32)}/Disc.iso"
    var deadline=android.os.SystemClock.elapsedRealtime()+30000
    val bounded=RootSaveFiles(root,2000,label,{ check(android.os.SystemClock.elapsedRealtime()<=deadline){"Opera operation exceeded the unchanged native deadline"} },coreName="opera")
    val started=android.os.SystemClock.elapsedRealtime()
    val copy=bounded.stageRom(discPath,source,0,discHash)
    val stageMillis=android.os.SystemClock.elapsedRealtime()-started
    check(copy.length()==1024L*1024*1024)
    deadline=android.os.SystemClock.elapsedRealtime()+30000
    bounded.removeRom(discPath,discHash)
    check(!copy.exists() && source.length()==1024L*1024*1024)
    java.io.RandomAccessFile(source,"rw").use { it.setLength(1024L*1024*1024+1) }
    refused { files.stageRom(discPath,source,0,discHash) }
    files.removeRom(discPath,discHash)
    refused { RootSaveFiles(root,2000,label,{}).stageRom(discPath,source,0,discHash) }
    refused { RootSaveFiles(root,2000,label,{}).removeRom(discPath,discHash) }
    println("PASS: exact 1 GiB streamed Opera disc in ${stageMillis}ms, unchanged 30s deadline, oversized refusal, cleanup and earlier core limits")
}

private fun checkFbneoStorage(root: File, label: ByteArray) {
    fun refused(work: () -> Unit) {
        try { work(); error("Expected FBNeo refusal") }
        catch (_: IllegalArgumentException) { }
        catch (e: IllegalStateException) { check(e.message != "Expected FBNeo refusal") }
    }
    val files = RootSaveFiles(root, 2000, label, {}, coreName = "fbneo")
    val base = "files/Broomm/${"b".repeat(32)}/47"
    val token = "e".repeat(32) + "-in"
    val old = byteArrayOf(1, 2, 3)
    val next = byteArrayOf(4, 5)
    val a = RootSaveFiles.digest(old); val b = RootSaveFiles.digest(next)
    val names = listOf("simpsons2p.fs", "simpsons2p.nv", "simpsons2p.hi", "simpsons2p.memcard", "shared.memcard")
    for (name in names + listOf("another.fs", "simpsons2p.fs.tmp"))
        files.replace("$base/saves/fbneo/$name", null, a, old, null, token)
    val selector = listOf(mapOf("path" to "$base/saves", "driver" to "simpsons2p"))
    val inventory = files.inventory(selector)
    check(inventory.keys == names.map { "$base/saves/fbneo/$it" }.toSet())
    check(inventory.values.all { it.sha256 == a })
    refused { files.inventory(listOf(mapOf("path" to "$base/saves", "driver" to "../another"))) }
    refused { RootSaveFiles(root, 2000, label, {}).inventory(selector) }
    refused { RootSaveFiles.managedPath("$base/saves/fbneo/simpsons2p.fs", saveOnly = true) }
    RootSaveFiles.managedPath("$base/saves/fbneo/simpsons2p.fs", saveOnly = true, core = "fbneo")
    refused { RootSaveFiles.managedPath("$base/saves/fbneo/other/subdir.fs", core = "fbneo") }
    refused { RootSaveFiles.managedPath("$base/saves/fbneo/simpsons2p.fs.tmp", core = "fbneo") }
    val selected = "$base/saves/fbneo/simpsons2p.fs"
    val metadata = files.metadata(files.path(selected))
    files.replace(selected, a, null, null, null, token.replace("-in", "-out"))
    val interrupted = RootSaveFiles(root, 2000, label, {}, { if (it == "linked") error("Lost FBNeo publication reply") }, "fbneo")
    refused { interrupted.replace(selected, null, b, next, metadata, token) }
    files.replace(selected, null, b, next, metadata, token)
    check(files.hash(files.path(selected)) == b)
    files.replace(selected, b, a, old, metadata, token.replace("-in", "-out"))
    check(files.metadata(files.path(selected)) == metadata && files.hash(files.path(selected)) == a)
    check(files.hash(files.path("$base/saves/fbneo/another.fs")) == a)

    val source = File(root, "library/47/content/simpsons2p.zip")
    check(source.parentFile!!.mkdirs())
    java.io.RandomAccessFile(source, "rw").use { it.setLength(128L * 1024 * 1024) }
    fun streamedHash(file: File): String {
        val digest = java.security.MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) { val count = input.read(buffer); if (count < 0) break; digest.update(buffer, 0, count) }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    val hash = streamedHash(source)
    val path = "$base/rom-${"f".repeat(32)}/simpsons2p.zip"
    val copy = files.stageRom(path, source, 0, hash)
    check(copy.length() == 128L * 1024 * 1024 && streamedHash(copy) == hash)
    files.removeRom(path, hash)
    java.io.RandomAccessFile(source, "rw").use { it.setLength(128L * 1024 * 1024 + 1) }
    refused { files.stageRom(path, source, 0, hash) }
    refused { RootSaveFiles(root, 2000, label, {}).stageRom(path.replace("f".repeat(32), "d".repeat(32)), source, 0, hash) }
    check(source.exists() && !copy.exists())
    println("PASS: FBNeo nested NVRAM/cards, foreign-file/core refusal, lost-reply restoration and exact 128 MiB opaque ROMset staging")
}

private fun checkLynxFirmware(root: File, label: ByteArray) {
    fun refused(work: () -> Unit) {
        try { work(); error("Expected Lynx refusal") }
        catch (_: IllegalArgumentException) { }
        catch (e: IllegalStateException) { check(e.message != "Expected Lynx refusal") }
    }
    val files = RootSaveFiles(root, 2000, label, {}, coreName = "mednafen_lynx")
    val base = "files/Broomm/${"b".repeat(32)}/46"
    val nonce = "d".repeat(32)
    val config = "$base/config-$nonce.cfg"
    val path = "$base/system-$nonce/lynxboot.img"
    val token = "c".repeat(32) + "-in"
    val bytes = ByteArray(512) { (it % 251).toByte() }
    val hash = RootSaveFiles.digest(bytes)
    refused { RootSaveFiles.managedPath(path) }
    refused { RootSaveFiles(root, 2000, label, {}).lynxFirmware(path, config, null, hash, bytes, token, {}) }
    refused { files.lynxFirmware(path, config.replace("/46/", "/47/"), null, hash, bytes, token, {}) }
    refused { files.lynxFirmware(path, config.replace(nonce, "e".repeat(32)), null, hash, bytes, token, {}) }
    refused { files.lynxFirmware(path.replace("lynxboot.img", "other.img"), config, null, hash, bytes, token, {}) }
    for (size in listOf(511, 513)) {
        val bad = ByteArray(size)
        refused { files.lynxFirmware(path, config, null, RootSaveFiles.digest(bad), bad, token, {}) }
    }
    val interrupted = RootSaveFiles(root, 2000, label, {}, { if (it == "linked") error("Lost Lynx publication reply") }, "mednafen_lynx")
    refused { interrupted.lynxFirmware(path, config, null, hash, bytes, token, {}) }
    files.lynxFirmware(path, config, null, hash, bytes, token, {})
    check(files.hash(files.path(path), 512) == hash && Os.lstat(files.path(path).path).st_nlink == 1L)
    check(files.inventory(listOf(mapOf("path" to "$base/saves", "exact" to "Game.srm"))).isEmpty())
    refused { files.lynxFirmware(path, config, "f".repeat(64), null, null, token.replace("-in", "-out"), {}) }
    check(files.hash(files.path(path), 512) == hash)
    files.lynxFirmware(path, config, hash, null, null, token.replace("-in", "-out"), {})
    files.lynxFirmware(path, config, hash, null, null, token.replace("-in", "-out"), {})
    check(!files.present(files.path(path).parentFile!!))
    var observations = 0
    refused { files.lynxFirmware(path, config, null, hash, bytes, token, {
        observations++; check(observations < 2) { "Writer arrived before Lynx publication" }
    }) }
    check(!files.present(files.path(path)))
    files.lynxFirmware(path, config, hash, null, null, token.replace("-in", "-out"), {})
    check(!files.present(files.path(path).parentFile!!))
    val foreign = bytes.copyOf().also { it[0] = 99 }
    val raced = RootSaveFiles(root, 2000, label, {}, { if (it == "staged") {
        val target = files.path(path); target.writeBytes(foreign)
        Os.chown(target.path, 2000, 2000); Os.chmod(target.path, 384)
        Os.setxattr(target.path, "security.selinux", label, 0)
    } }, "mednafen_lynx")
    refused { raced.lynxFirmware(path, config, null, hash, bytes, token, {}) }
    check(files.path(path).readBytes().contentEquals(foreign))
    refused { files.lynxFirmware(path, config, hash, null, null, token.replace("-in", "-out"), {}) }
    check(files.path(path).readBytes().contentEquals(foreign))
    println("PASS: exact Lynx BIOS size/core/session boundary, lost reply, writer arrival, exclusive race, foreign-byte preservation and idempotent cleanup")
}

private fun checkN64Storage(root: File, label: ByteArray) {
    fun refused(work: () -> Unit) {
        try { work(); error("Expected N64 refusal") }
        catch (_: IllegalArgumentException) { }
        catch (e: IllegalStateException) { check(e.message != "Expected N64 refusal") }
    }
    val ordinary = RootSaveFiles(root, 2000, label, {})
    val n64 = RootSaveFiles(root, 2000, label, {}, coreName = "mupen64plus_next")
    check(RootSaveFiles.corePath("mupen64plus_next") == "cores/mupen64plus_next_gles3_libretro_android.so")
    val base = "files/Broomm/${"b".repeat(32)}/45"
    val token = "a".repeat(32) + "-in"
    val save = "$base/saves/N64.srm"
    val ram = ByteArray(296960) { (it % 251).toByte() }
    val ramHash = RootSaveFiles.digest(ram)
    n64.replace(save, null, ramHash, ram, null, token)
    val areas = listOf(mapOf("path" to "$base/saves", "exact" to "N64.srm"))
    check(n64.inventory(areas).getValue(save).sha256 == ramHash)
    refused { ordinary.inventory(areas) }
    refused { n64.replace(save, ramHash, RootSaveFiles.digest(ByteArray(296961)), ByteArray(296961), null, token) }
    val state = "$base/states/states-${"a".repeat(16)}-android/N64.state"
    val stateBytes = ByteArray(16793412) { (it % 239).toByte() }
    val stateHash = RootSaveFiles.digest(stateBytes)
    val interrupted = RootSaveFiles(root, 2000, label, {}, { if (it == "linked") error("Interrupted N64 state") }, "mupen64plus_next")
    refused { interrupted.replace(state, null, stateHash, stateBytes, null, token) }
    n64.replace(state, null, stateHash, stateBytes, null, token)
    check(n64.hash(n64.path(state), n64.progressLimit(state)) == stateHash)
    check(Os.lstat(n64.path(state).path).st_nlink == 1L)
    refused { ordinary.bytes(n64.path(state), ordinary.progressLimit(state)) }
    check(n64.progressLimit(state) == 32 * 1024 * 1024)
    check(n64.progressLimit("$base/config-${"a".repeat(32)}.cfg") == 262144)
    val source = File(root, "library/45/content/Large.z64")
    check(source.parentFile!!.mkdirs())
    java.io.RandomAccessFile(source, "rw").use { it.setLength(64L * 1024 * 1024) }
    val romHash = java.security.MessageDigest.getInstance("SHA-256").also { hash ->
        source.inputStream().use { input ->
            val buffer = ByteArray(65536)
            while (true) { val count = input.read(buffer); if (count < 0) break; hash.update(buffer, 0, count) }
        }
    }.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    val romPath = "$base/rom-${"1".repeat(32)}/Large.z64"
    val rom = n64.stageRom(romPath, source, 0, romHash)
    check(rom.length() == 64L * 1024 * 1024 && source.length() == rom.length())
    n64.removeRom(romPath, romHash)
    refused { ordinary.stageRom(romPath, source, 0, romHash) }
    ordinary.removeRom(romPath, romHash)
    java.io.RandomAccessFile(source, "rw").use { it.setLength(64L * 1024 * 1024 + 1) }
    refused { n64.stageRom(romPath, source, 0, romHash) }
    n64.removeRom(romPath, romHash)
    println("PASS: N64 full SRAM, large interrupted state recovery, exact 64 MiB cartridge, oversized refusal and unchanged earlier limits")
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

private fun checkSaturnStorage(root: File, label: ByteArray) {
    fun refused(work: () -> Unit) {
        try { work(); error("Expected Saturn refusal") }
        catch (_: IllegalArgumentException) { }
        catch (e: IllegalStateException) { check(e.message != "Expected Saturn refusal") }
    }
    val files = RootSaveFiles(root, 2000, label, {}, coreName = "mednafen_saturn")
    val base = "files/Broomm/${"b".repeat(32)}/84"
    val nonce = "9".repeat(32)
    val token = nonce + "-in"
    val sizes = linkedMapOf("Disc.srm" to 32768, "Disc.bkr" to 32768, "Disc.smpc" to 12,
        "Disc.bcr" to 524288, "Disc.4mb.bcr" to 4194304)
    for ((name, size) in sizes) {
        val bytes = ByteArray(size) { 17 }
        files.replace("$base/saves/$name", null, RootSaveFiles.digest(bytes), bytes, null, token)
    }
    val other = ByteArray(12) { 5 }
    files.replace("$base/saves/Other.smpc", null, RootSaveFiles.digest(other), other, null, token)
    val areas = listOf(mapOf("path" to "$base/saves", "saturnStem" to "Disc"))
    val actual = files.inventory(areas)
    check(actual.keys == sizes.keys.map { "$base/saves/$it" }.toSet())
    for ((name, size) in sizes) check(actual.getValue("$base/saves/$name").bytes == size.toLong())
    refused { files.replace("$base/saves/Disc.bkr", actual.getValue("$base/saves/Disc.bkr").sha256,
        RootSaveFiles.digest(other), other, null, token) }
    val cart = files.path("$base/saves/Disc.4mb.bcr")
    val cartHash = actual.getValue("$base/saves/Disc.4mb.bcr").sha256
    cart.writeBytes(other)
    refused { files.inventory(areas) }
    cart.writeBytes(ByteArray(4194304) { 17 })
    check(files.inventory(areas).getValue("$base/saves/Disc.4mb.bcr").sha256 == cartHash)
    refused { files.inventory(listOf(mapOf("path" to "$base/saves", "saturnStem" to "../Disc"))) }
    refused { RootSaveFiles.managedPath("$base/saves/Disc.4mb.bcr") }
    refused { RootSaveFiles.managedPath("$base/saves/Disc.bcr.tmp", core = "mednafen_saturn") }
    check(files.hash(files.path("$base/saves/Other.smpc")) == RootSaveFiles.digest(other))
    println("PASS: Saturn exact internal/cart/settings boundaries, 4 MiB cartridge capture, truncation/path refusal and foreign-file preservation")

    val config = "$base/config-$nonce.cfg"
    val bios = "$base/system-$nonce/sega_101.bin"
    val payload = ByteArray(524288) { 23 }; val biosHash = RootSaveFiles.digest(payload)
    refused { files.saturnFirmware(bios, config, null, biosHash, other, token) {} }
    refused { RootSaveFiles(root,2000,label,{}).saturnFirmware(bios,config,null,biosHash,payload,token) {} }
    refused { files.saturnFirmware(bios.replace("system-9","system-8"),config,null,biosHash,payload,token) {} }
    val lost = RootSaveFiles(root,2000,label,{}, { if(it=="linked") error("Lost Saturn BIOS reply") },"mednafen_saturn")
    refused { lost.saturnFirmware(bios,config,null,biosHash,payload,token) {} }
    files.saturnFirmware(bios,config,null,biosHash,payload,token) {}
    check(files.hash(files.path(bios),524288) == biosHash)
    refused { files.saturnFirmware(bios,config,biosHash,null,null,token.replace("-in","-out")) { error("Writer alive") } }
    files.path(bios).writeBytes(ByteArray(524288) { 24 })
    refused { files.saturnFirmware(bios,config,biosHash,null,null,token.replace("-in","-out")) {} }
    files.path(bios).writeBytes(payload)
    repeat(2) { files.saturnFirmware(bios,config,biosHash,null,null,token.replace("-in","-out")) {} }
    check(!files.path(bios).exists())
    val optionRoot = File(root,"saturn-options").apply { check(mkdir()) }
    val options = File(optionRoot,"Beetle Saturn.opt").apply { writeText("beetle_saturn_save_method = \"mednafen\"\n");Os.chown(path,2000,2000);Os.chmod(path,384) }
    check(files.options(options.path,listOf(optionRoot))!!.contentEquals(options.readBytes()))
    val source = File(root,"library/84/content/Disc.chd").apply { check(parentFile!!.mkdirs());writeBytes(ByteArray(128){1}) }
    val hash = RootSaveFiles.digest(source.readBytes());val relative = "$base/rom-$nonce/Disc.chd"
    val staged = files.stageRom(relative,source,0,hash)
    check(files.hash(staged) == hash)
    refused { RootSaveFiles.romPath(relative) }
    refused { RootSaveFiles.romPath(relative.replace(".chd",".iso"),"mednafen_saturn") }
    files.removeRom(relative,hash)
    check(!staged.exists() && source.exists())
    println("PASS: Saturn scoped options, BIOS transaction/core/size guards, interrupted publication, writer/edited-resource refusal, idempotent cleanup and bound CHD staging")
}

private fun checkFlycastStorage(root: File, label: ByteArray) {
    fun refused(work: () -> Unit) {
        try { work(); error("Expected Dreamcast refusal") }
        catch (_: IllegalArgumentException) { }
        catch (e: IllegalStateException) { check(e.message != "Expected Dreamcast refusal") }
    }
    val files = RootSaveFiles(root, 2000, label, {}, coreName = "flycast")
    val plain = RootSaveFiles(root, 2000, label, {})
    val base = "files/Broomm/${"6".repeat(32)}/86"
    val nonce = "5".repeat(32)
    val token = "$nonce-in"
    val card = ByteArray(131072) { (it % 251).toByte() }
    val cardHash = RootSaveFiles.digest(card)
    val vmus = ('A'..'D').flatMap { p -> (1..2).map { "$p$it" } }
    for (port in vmus) for (name in listOf("MK-51000", "Legacy Disc"))
        files.replace("$base/saves/$name.$port.bin", null, cardHash, card, null, token)
    val foreign = "$base/saves/unrelated.bin"
    plain.replace(foreign, null, cardHash, card, null, token)
    val selector = listOf(mapOf("path" to "$base/saves", "flycastVmus" to "true"))
    check(files.inventory(selector).size == 16 && files.hash(files.path(foreign)) == cardHash)
    refused { files.replace("$base/saves/Broken.A1.bin", null, "a".repeat(64), byteArrayOf(1), null, token) }
    refused { RootSaveFiles.managedPath("$base/saves/dc_nvmem.bin", core = "flycast") }
    refused { RootSaveFiles.managedPath("$base/saves/vmu_save_A1.bin", core = "flycast") }
    refused { RootSaveFiles(root, 2000, label, {}).inventory(selector) }
    val state = "$base/states/states-${"4".repeat(16)}-android/Disc.state"
    val large = ByteArray(17 * 1024 * 1024) { 7 }
    val stateHash = RootSaveFiles.digest(large)
    files.replace(state, null, stateHash, large, null, token)
    check(files.hash(files.path(state), files.progressLimit(state)) == stateHash)
    check(files.progressLimit(state) == 64 * 1024 * 1024 && plain.progressLimit(state) == 16 * 1024 * 1024)
    println("PASS: Dreamcast eight native/eight legacy exact VMUs, unrelated-file retention, console/fallback exclusion, large matched state and unchanged earlier limits")

    val config = "$base/config-$nonce.cfg"
    val bios = "$base/system-$nonce/dc/dc_boot.bin"
    val flash = "$base/system-$nonce/dc/dc_nvmem.bin"
    val options = "$base/options-$nonce.opt"
    val biosBytes = ByteArray(2097152) { 13 }; val biosHash = RootSaveFiles.digest(biosBytes)
    val optionBytes = "flycast_per_content_vmus = \"All VMUs\"\n".toByteArray(); val optionHash = RootSaveFiles.digest(optionBytes)
    files.flycastResource(bios, config, null, biosHash, biosBytes, token) {}
    files.flycastResource(flash, config, null, cardHash, card, token) {}
    files.flycastResource(options, config, null, optionHash, optionBytes, token) {}
    check(files.flycastResources(config).keys == setOf(bios, flash, options))
    refused { files.flycastResource(bios, config.replace(nonce, "3".repeat(32)), null, biosHash, biosBytes, token) {} }
    refused { files.flycastResource(bios, config, biosHash, null, null, "$nonce-out") { error("Writer active") } }
    val fallback = "$base/system-$nonce/dc/vmu_save_A1.bin"
    plain.replace(fallback, null, cardHash, card, null, token)
    check(files.flycastResources(config).containsKey(fallback))
    refused { files.flycastResource(fallback, config, cardHash, null, null, "$nonce-out") {} }
    check(files.hash(files.path(fallback)) == cardHash)
    // Simulate the core changing its mutable flash/preferences, preserving metadata.
    files.path(flash).writeBytes(ByteArray(131072) { 14 })
    val captured = files.flycastResources(config)
    check(captured.getValue(flash).sha256 != cardHash)
    for (path in listOf(bios, flash, options)) repeat(2) {
        files.flycastResource(path, config, captured.getValue(path).sha256, null, null, "$nonce-out") {}
    }
    check(files.path(fallback).exists() && !files.path(flash).exists())
    println("PASS: Dreamcast exact transaction resources, changed console capture, read-only fallback VMUs, writer/path refusal and idempotent cleanup preserving unrecognized data")

    val lostNonce = "2".repeat(32)
    val lostConfig = "$base/config-$lostNonce.cfg"
    val lostBios = "$base/system-$lostNonce/dc/dc_boot.bin"
    val interrupted = RootSaveFiles(root, 2000, label, {}, { if (it == "linked") error("Lost publication reply") }, coreName = "flycast")
    refused { interrupted.flycastResource(lostBios, lostConfig, null, biosHash, biosBytes, "$lostNonce-in") {} }
    check(Os.lstat(files.path(lostBios).path).st_nlink == 2L)
    repeat(2) { files.flycastResource(lostBios, lostConfig, biosHash, null, null, "$lostNonce-out") {} }
    check(!files.path(lostBios).exists())
    println("PASS: Dreamcast direct interrupted-link resource cleanup without source/cache or reinstallation")
}

private fun checkResourceInterruptedCleanup(root: File, label: ByteArray) {
    fun refused(work: () -> Unit) {
        try { work(); error("Expected linked-resource refusal") }
        catch (_: IllegalArgumentException) { }
        catch (e: IllegalStateException) { check(e.message != "Expected linked-resource refusal") }
    }
    val nonce = "1".repeat(32)
    for ((core, name, size) in listOf(Triple("mednafen_lynx","lynxboot.img",512), Triple("opera","panafz10.bin",1048576), Triple("mednafen_saturn","sega_101.bin",524288))) {
        val base = "files/Broomm/${"1".repeat(32)}/${if (core == "opera") 88 else if (core == "mednafen_lynx") 89 else 90}"
        val config = "$base/config-$nonce.cfg"
        val path = "$base/system-$nonce/$name"
        val bytes = ByteArray(size) { 33 }; val hash = RootSaveFiles.digest(bytes)
        val interrupted = RootSaveFiles(root,2000,label,{}, { if (it == "linked") error("Lost install reply") },coreName=core)
        val files = RootSaveFiles(root,2000,label,{},coreName=core)
        fun effect(f: RootSaveFiles, before: String?, after: String?, payload: ByteArray?, token: String, closed: () -> Unit = {}) {
            when (core) {
                "mednafen_lynx" -> f.lynxFirmware(path,config,before,after,payload,token,closed)
                "opera" -> f.operaFirmware(path,config,before,after,payload,token,closed)
                else -> f.saturnFirmware(path,config,before,after,payload,token,closed)
            }
        }
        refused { effect(interrupted,null,hash,bytes,"$nonce-in") }
        val target = files.path(path)
        check(Os.lstat(target.path).st_nlink == 2L)
        val foreign = File(root,"foreign-resource-$core")
        Os.link(target.path,foreign.path)
        refused { effect(files,hash,null,null,"$nonce-out") }
        check(Os.lstat(target.path).st_nlink == 3L && foreign.exists())
        Os.remove(foreign.path)
        refused { effect(files,hash,null,null,"$nonce-out") { error("Writer arrived") } }
        check(Os.lstat(target.path).st_nlink == 2L)
        refused { effect(files,"f".repeat(64),null,null,"$nonce-out") }
        check(target.exists())
        repeat(2) { effect(files,hash,null,null,"$nonce-out") }
        check(!target.exists())
    }
    println("PASS: direct interrupted Lynx/Opera/Saturn resource cleanup without source, strict extra-link/checksum/writer refusal and idempotent closed recovery")
}

private fun checkFlycastLargeProgress(root: File, label: ByteArray) {
    fun refused(work: () -> Unit) {
        try { work(); error("Expected Dreamcast size refusal") }
        catch (_: IllegalArgumentException) { }
        catch (e: IllegalStateException) { check(e.message != "Expected Dreamcast size refusal") }
    }
    val files = RootSaveFiles(root,2000,label,{},coreName="flycast")
    val base = "files/Broomm/${"0".repeat(32)}/87"
    val token = "0".repeat(32) + "-in"
    val state = "$base/states/states-${"0".repeat(16)}-android/Disc.state"
    val payload = ByteArray(64 * 1024 * 1024) { (it % 251).toByte() }
    val stateHash = RootSaveFiles.digest(payload)
    files.replace(state,null,stateHash,payload,null,token)
    val area = listOf(mapOf("path" to state.substringBeforeLast('/'), "prefix" to "Disc", "pattern" to "native-selector"))
    check(files.inventory(area).getValue(state).sha256 == stateHash)
    java.io.RandomAccessFile(files.path(state),"rw").use { it.setLength(64L * 1024 * 1024 + 1) }
    refused { files.inventory(area) }
    java.io.RandomAccessFile(files.path(state),"rw").use { it.setLength(64L * 1024 * 1024) }
    check(files.hash(files.path(state),files.progressLimit(state)) == stateHash)
    val source = File(root,"library/87/content/Disc.chd").apply { check(parentFile!!.mkdirs()) }
    java.io.RandomAccessFile(source,"rw").use { it.setLength(2L * 1024 * 1024 * 1024) }
    val digest = java.security.MessageDigest.getInstance("SHA-256")
    source.inputStream().use { input ->
        val block = ByteArray(65536)
        while (true) { val n = input.read(block); if (n < 0) break; digest.update(block,0,n) }
    }
    val hash = digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    val rom = "$base/rom-${"0".repeat(32)}/Disc.chd"
    val started = System.nanoTime()
    val staged = files.stageRom(rom,source,0,hash)
    val elapsed = TimeUnit.NANOSECONDS.toMillis(System.nanoTime()-started)
    check(elapsed < 30000 && staged.length() == source.length())
    files.removeRom(rom,hash)
    java.io.RandomAccessFile(source,"rw").use { it.setLength(2L * 1024 * 1024 * 1024 + 1) }
    refused { files.stageRom(rom,source,0,hash) }
    files.removeRom(rom,hash)
    refused { RootSaveFiles.romPath(rom,"mgba") }
    refused { RootSaveFiles.romPath(rom.replace(".chd",".gdi"),"flycast") }
    val nativeRoot = "/data/user/0/com.retroarch.aarch64"
    val content = "/data/user/0/app.broomm.broomm/files/broomm/library/${"0".repeat(32)}/87/content"
    validateRootRetroArchLaunch("flycast","com.retroarch.aarch64",nativeRoot,"$nativeRoot/$rom",
        "$nativeRoot/$base/config-${"0".repeat(32)}.cfg",content,"$content/Disc.chd")
    check(source.exists() && !staged.parentFile!!.exists())
    println("PASS: exact 64 MiB Dreamcast state inventory and oversized refusal; exact 2 GiB streamed CHD in ${elapsed}ms under unchanged 30s deadline, oversized/descriptor/core refusal and cleanup")
}
