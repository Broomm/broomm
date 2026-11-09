import app.broomm.broomm.RootInspectionCommand
import app.broomm.broomm.RootInspectionFailure
import app.broomm.broomm.PpssppStorageInspection
import app.broomm.broomm.DuckStationStorageInspection
import java.io.File
import java.io.IOException
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.system.exitProcess

private const val pkg = "com.retroarch.aarch64"
private const val root = "/data/user/0/$pkg"
private const val uid = 10123
private const val label = "u:object_r:app_data_file:s0:c123,c256,c512,c768"
private fun report(path: String = root, owner: Int = uid, context: String = label) =
    "BROOMM_ROOT_V1\n0\n$path\n$owner $owner 700 $context\n"
private const val psp = "org.ppsspp.ppsspp"
private const val pspRoot = "/data/user/0/$psp"
private val mediaLabel = label.replace("app_data_file", "media_rw_data_file")
private fun pspReport() = report(pspRoot) +
    "BROOMM_PSP_STORAGE_V1\nprivate\n/storage/emulated/0/Android/data/$psp/files\n" +
    "$uid 1078 2770 $mediaLabel 65038 28074\n$uid $uid 600 $label 56 1\n" +
    "$uid 1078 660 $mediaLabel 18822 1\n"
private const val duck = DuckStationStorageInspection.PACKAGE
private const val duckRoot = "/data/user/0/$duck"
private fun duckReport() = report(duckRoot) +
    "BROOMM_DUCKSTATION_STORAGE_V1\n/storage/emulated/0/Android/data/$duck/files\n" +
    "$uid 1078 2770 $mediaLabel 65038 27858\n$uid 1078 660 $mediaLabel 9913 1 65038 27859\n"

fun main(args: Array<String>) {
    if (args.isNotEmpty()) {
        if (args[0] == "emit-psp-script") {
            print(RootInspectionCommand.SCRIPT + "\n" + PpssppStorageInspection.SCRIPT)
            return
        }
        if (args[0] == "emit-duck-script") {
            print(RootInspectionCommand.SCRIPT + "\n" + DuckStationStorageInspection.SCRIPT)
            return
        }
        if (args[0] == "parse-duck-report") {
            check(args.size == 2)
            val bytes = System.`in`.readNBytes(16385)
            check(bytes.size <= 16384)
            println(DuckStationStorageInspection.parse(bytes.toString(Charsets.UTF_8), setOf(duckRoot), args[1].toInt()))
            return
        }
        check(System.`in`.bufferedReader().readLine() == when {
            args[0].startsWith("psp") -> pspRoot
            args[0].startsWith("duck") -> duckRoot
            else -> root
        })
        when (args[0]) {
            "success" -> print(report())
            "denied" -> { print(report()); exitProcess(1) }
            "identity" -> exitProcess(61)
            "directory" -> exitProcess(62)
            "metadata" -> { System.err.print("secret\u001b[31m"); exitProcess(64) }
            "diagnostic" -> { print(report()); System.err.print("secret\u001b[31m") }
            "partial" -> print(report().dropLast(1))
            "flood" -> { while (true) { System.out.print("x".repeat(1024)); System.err.print("y".repeat(1024)) } }
            "wait" -> Thread.sleep(60000)
            "psp-success" -> print(pspReport())
            "psp-shared" -> print(report(pspRoot) + "BROOMM_PSP_STORAGE_V1\nother\n$uid $uid 600 $label 90 1\n")
            "psp-unavailable" -> { print(report(pspRoot)); exitProcess(65) }
            "duck-success" -> print(duckReport())
            "duck-unavailable" -> { print(report(duckRoot)); exitProcess(66) }
            "duck-partial" -> print(duckReport().dropLast(1))
        }
        return
    }
    fun expectFailure(code: String? = null, work: () -> Unit) {
        try { work(); error("Expected inspection refusal: $code") }
        catch (e: RootInspectionFailure) { check(code == null || e.code == code); check(!e.message.orEmpty().contains("secret")) }
        catch (e: IllegalArgumentException) { check(code == null) }
    }
    val children = mutableListOf<Process>()
    fun command(mode: String, timeout: Long = 5000, started: CountDownLatch? = null) = RootInspectionCommand(start = { argv ->
        val script = RootInspectionCommand.SCRIPT +
            when {
                mode.startsWith("psp") -> "\n" + PpssppStorageInspection.SCRIPT
                mode.startsWith("duck") -> "\n" + DuckStationStorageInspection.SCRIPT
                else -> ""
            }
        check(argv == listOf("su", "-M", "-c", script))
        check(!argv.last().contains(pkg)) // Paths remain stdin data, never shell source.
        ProcessBuilder(File(System.getProperty("java.home"), "bin/java").path,
            "-cp", System.getProperty("java.class.path"), "Check_root_inspectionKt", mode).start().also {
            synchronized(children) { children.add(it) }; started?.countDown()
        }
    }, timeoutMillis = timeout)
    fun RootInspectionCommand.run() = inspect(pkg, uid, 0, root)
    try {
        val result = command("success").run()
        check(result["uid"] == uid && result["dataDir"] == root && result["label"] == label)
        for (mode in listOf("denied", "diagnostic")) expectFailure("failed") { command(mode).run() }
        expectFailure("root-identity") { command("identity").run() }
        expectFailure("directory-unavailable") { command("directory").run() }
        expectFailure("metadata-unavailable") { command("metadata").run() }
        expectFailure { command("partial").run() }
        expectFailure("output-limit") { command("flood").run() }
        expectFailure("timeout") { command("wait", 200).run() }
        expectFailure("unavailable") { RootInspectionCommand(start = { throw IOException("secret") }).run() }

        val started = CountDownLatch(1)
        val cancelled = command("wait", started = started)
        var failure: Throwable? = null
        val caller = thread {
            try { cancelled.run(); failure = AssertionError("Cancellation accepted a report") }
            catch (e: Throwable) { if (e !is RootInspectionFailure || e.code != "cancelled") failure = e }
        }
        check(started.await(5, TimeUnit.SECONDS)); cancelled.cancel()
        caller.join(5000); check(!caller.isAlive); failure?.let { throw it }

        val noSpawn = RootInspectionCommand(start = { error("Invalid identity spawned a root process") })
        expectFailure { noSpawn.inspect("$pkg\ncommand", uid, 0, root) }
        expectFailure { noSpawn.inspect(pkg, uid, 10, root) }
        expectFailure { noSpawn.inspect(pkg, uid, 0, "$root/../foreign") }
        expectFailure { noSpawn.inspect(pkg, uid, 0, "/data/user/10/$pkg") }
        for (bad in listOf(report("/data/user/0/foreign"), report(owner = uid + 1), report(context = "?"),
            report(context = "$label\u001b"), report().replace("\n0\n", "\n2000\n"), report() + "extra\n"))
            expectFailure { RootInspectionCommand.parse(bad, setOf(root), uid) }
        val workRoot = "/data/user/10/$pkg"
        check(RootInspectionCommand.parse(report(workRoot, 1010123), setOf(workRoot), 1010123)["uid"] == 1010123)
        val privateMemory = command("psp-success").inspect(psp, uid, 0, pspRoot)["memoryStick"] as Map<*, *>
        check(privateMemory["kind"] == "private" && privateMemory["gid"] == 1078 &&
            privateMemory["mode"] == "2770" && privateMemory["inode"] == 28074L)
        check(command("psp-shared").inspect(psp, uid, 0, pspRoot)["memoryStick"] == mapOf("kind" to "other"))
        expectFailure("storage-unavailable") { command("psp-unavailable").inspect(psp, uid, 0, pspRoot) }
        for (bad in listOf(
            pspReport().replace("/Android/data/$psp/", "/Android/data/foreign/"),
            pspReport().replace("2770", "2777"),
            pspReport().replace("1078 660", "1079 660"),
            pspReport().replace("18822 1", "18822 2"),
            pspReport().replace("65038 28074", "65038 0"),
            pspReport().replace("media_rw_data_file", "app_data_file"),
            pspReport().replace("56 1", "1025 1"),
            pspReport().dropLast(1), pspReport() + "extra\n",
        )) expectFailure { PpssppStorageInspection.parse(bad, setOf(pspRoot), uid, psp) }
        val duckFiles = command("duck-success").inspect(duck, uid, 0, duckRoot)["appFiles"] as Map<*, *>
        check(duckFiles["path"] == "/storage/emulated/0/Android/data/$duck/files" &&
            duckFiles["inode"] == 27858L && duckFiles["settingsBytes"] == 9913L)
        expectFailure("storage-unavailable") { command("duck-unavailable").inspect(duck, uid, 0, duckRoot) }
        expectFailure { command("duck-partial").inspect(duck, uid, 0, duckRoot) }
        for (bad in listOf(
            duckReport().replace("/Android/data/$duck/", "/Android/data/foreign/"),
            duckReport().replace("2770", "2777"),
            duckReport().replace("2770", "2660"),
            duckReport().replace("1078 660", "1079 660"),
            duckReport().replace("1078 660", "1078 664"),
            duckReport().replace("9913 1", "9913 2"),
            duckReport().replace("9913 1", "1048577 1"),
            duckReport().replace("1 65038 27859", "1 65039 27859"),
            duckReport().replace("media_rw_data_file", "app_data_file"),
            duckReport().replace("65038 27858", "65038 0"),
            duckReport() + "extra\n",
        )) expectFailure { DuckStationStorageInspection.parse(bad, setOf(duckRoot), uid) }
        println("PASS: subprocess success; denial/partial/diagnostic refusal; output bound; deadline; coordinated cancellation; missing su; user/path/UID/label identity")
        println("PASS: PPSSPP app-private/shared observations; unavailable storage stays failed; foreign path, changed group/label, extra links, permissive mode and incomplete response refused")
        println("PASS: DuckStation initialized metadata; unavailable/partial observation stays failed; foreign storage, changed group/device/label, links, permissions and oversized settings refused")
    } finally {
        for (child in synchronized(children) { children.toList() }) {
            child.destroyForcibly()
            check(child.waitFor(5, TimeUnit.SECONDS)) { "Inspection fixture survived cleanup" }
        }
    }
}
