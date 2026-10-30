import app.broomm.broomm.SharedDocumentLock
import app.broomm.broomm.SharedDocumentBusy
import java.io.File
import java.nio.file.Files
import java.util.concurrent.TimeUnit
import kotlin.concurrent.thread
import kotlin.system.exitProcess

fun main(args: Array<String>) {
    if (args.size == 2) {
        try {
            SharedDocumentLock.acquire(File(args[0])).use { }
            exitProcess(if (args[1] == "available") 0 else 2)
        } catch (_: SharedDocumentBusy) { exitProcess(if (args[1] == "held") 0 else 3) }
    }
    val fixture = Files.createTempDirectory("broomm-native-document-lock-").toFile().canonicalFile
    try {
        fun probe(expected: String) {
            val child = ProcessBuilder(File(System.getProperty("java.home"), "bin/java").path,
                "-cp", System.getProperty("java.class.path"), "Check_shared_document_lockKt", fixture.path, expected)
                .inheritIO().start()
            check(child.waitFor(10, TimeUnit.SECONDS)) { child.destroyForcibly(); "Lock probe did not exit" }
            check(child.exitValue() == 0) { "Native lock probe failed: $expected" }
        }
        SharedDocumentLock.acquire(fixture).use {
            var observed = false
            val query = thread {
                check(SharedDocumentLock.busy(fixture))
                try { SharedDocumentLock.acquire(fixture).use { error("Concurrent activity acquired a live lock") } }
                catch (_: SharedDocumentBusy) { observed = true }
            }
            query.join(10000); check(!query.isAlive && observed)
            // In-process status queries must not close a second FD and release
            // the original POSIX lock. A fresh process establishes exclusion.
            probe("held")
        }
        probe("available")
        val bad = File(fixture, "linked").apply { mkdir() }
        val foreign = File(fixture, "unrelated").apply { writeText("preserve") }
        Files.createSymbolicLink(File(bad, "mmj-document-io.lock").toPath(), foreign.toPath())
        try { SharedDocumentLock.acquire(bad).use { error("Linked lock was accepted") } }
        catch (_: IllegalArgumentException) { }
        check(foreign.readText() == "preserve")
        println("PASS: held transfer, concurrent activity query, cross-process exclusion, release and linked-file preservation")
    } finally { fixture.deleteRecursively() }
}
