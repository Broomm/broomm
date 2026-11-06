import app.broomm.broomm.RootInspectionCommand
import app.broomm.broomm.RootInspectionFailure
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

fun main(args: Array<String>) {
    if (args.isNotEmpty()) {
        check(System.`in`.bufferedReader().readLine() == root)
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
        check(argv == listOf("su", "-M", "-c", RootInspectionCommand.SCRIPT))
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
        println("PASS: subprocess success; denial/partial/diagnostic refusal; output bound; deadline; coordinated cancellation; missing su; user/path/UID/label identity")
    } finally {
        for (child in synchronized(children) { children.toList() }) {
            child.destroyForcibly()
            check(child.waitFor(5, TimeUnit.SECONDS)) { "Inspection fixture survived cleanup" }
        }
    }
}
