package app.broomm.broomm

import java.io.ByteArrayOutputStream
import java.io.IOException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

class RootInspectionFailure(val code: String, message: String) : Exception(message)

/** One read-only request. No caller can supply shell source or a write command. */
class RootInspectionCommand(
    private val start: (List<String>) -> Process = { ProcessBuilder(it).start() },
    private val timeoutMillis: Long = 30000,
) {
    private val cancelled = AtomicBoolean(false)
    fun cancel() { cancelled.set(true) }

    fun inspect(pkg: String, uid: Int, user: Int, dataDir: String): Map<String, Any> {
        require(Regex("[a-zA-Z][a-zA-Z0-9_]*(\\.[a-zA-Z][a-zA-Z0-9_]*)+").matches(pkg))
        require(user >= 0 && uid >= 10000 && uid / 100000 == user && uid % 100000 >= 10000)
        val roots = setOf("/data/user/$user/$pkg") + if (user == 0) setOf("/data/data/$pkg") else emptySet()
        require(dataDir in roots && dataDir.length < 256) { "Unsupported Android application data location; nothing was changed." }
        if (cancelled.get()) throw RootInspectionFailure("cancelled", "Root inspection cancelled.")
        val deadline = System.nanoTime() + TimeUnit.MILLISECONDS.toNanos(timeoutMillis)
        val process = try { start(listOf("su", "-c", SCRIPT)) }
        catch (_: IOException) { throw RootInspectionFailure("unavailable", "Root command unavailable. Use connected folders or check your existing root manager.") }
        val stdout = ByteArrayOutputStream()
        val stderr = ByteArrayOutputStream()
        var bytes = 0
        fun drain(stream: java.io.InputStream, output: ByteArrayOutputStream) {
            val buffer = ByteArray(1024)
            while (stream.available() > 0) {
                val n = stream.read(buffer, 0, minOf(buffer.size, stream.available()))
                if (n <= 0) break
                bytes += n
                if (bytes > 16384) throw RootInspectionFailure("output-limit", "Root inspection exceeded its output limit.")
                output.write(buffer, 0, n)
            }
        }
        try {
            // A validated path is under 256 bytes, fitting an empty process pipe
            // without waiting for the permission prompt to consume stdin.
            process.outputStream.use { it.write("$dataDir\n".toByteArray(Charsets.UTF_8)) }
            // Only read bytes already available. Waiting for EOF can deadlock
            // cancellation when a root-manager descendant retains a pipe.
            while (true) {
                if (cancelled.get()) throw RootInspectionFailure("cancelled", "Root inspection cancelled.")
                if (System.nanoTime() >= deadline)
                    throw RootInspectionFailure("timeout", "Root inspection timed out. Check the root prompt, then retry explicitly.")
                drain(process.inputStream, stdout)
                drain(process.errorStream, stderr)
                val exit = try { process.exitValue() } catch (_: IllegalThreadStateException) { null }
                if (exit != null) {
                    drain(process.inputStream, stdout)
                    drain(process.errorStream, stderr)
                    if (exit != 0) throw RootInspectionFailure("failed", "Root access was denied or inspection failed. No storage connection was created.")
                    // Do not log arbitrary su diagnostics (which can contain secrets
                    // or terminal controls), or mistake partial stdout for success.
                    if (stderr.size() != 0) throw RootInspectionFailure("failed", "Root inspection returned unexpected diagnostics. No storage connection was created.")
                    return parse(stdout.toString("UTF-8"), roots, uid)
                }
                Thread.sleep(10)
            }
        } finally {
            process.destroy()
            // No reader is blocked on these streams. Never wait for a
            // root-manager-owned descendant; even a surviving command is read-only.
            for (stream in listOf(process.inputStream, process.errorStream, process.outputStream))
                try { stream.close() } catch (_: IOException) { }
        }
    }

    companion object {
        // Metadata travels over stdin and is used only as a quoted argument.
        // Absolute Android tools avoid a root manager's customized utility PATH.
        val SCRIPT = """
            set -eu
            IFS= read -r root
            [ "${'$'}(/system/bin/id -u)" = 0 ]
            [ -d "${'$'}root" ]
            real="${'$'}(/system/bin/readlink -f "${'$'}root")"
            printf 'BROOMM_ROOT_V1\n0\n%s\n' "${'$'}real"
            /system/bin/stat -c '%u %g %a %C' "${'$'}real"
        """.trimIndent()

        fun parse(output: String, roots: Set<String>, uid: Int): Map<String, Any> {
            val lines = output.split('\n')
            require(lines.size == 5 && lines[0] == "BROOMM_ROOT_V1" && lines[1] == "0" && lines[4].isEmpty()) {
                "Incomplete or unexpected root inspection response."
            }
            require(lines[2] in roots) { "Emulator data resolved outside its Android user/package boundary." }
            val fields = lines[3].split(' ')
            require(fields.size == 4 && fields[0].toIntOrNull() == uid && fields[1].toIntOrNull()?.let { it >= 0 } == true &&
                Regex("[0-7]{3,4}").matches(fields[2]) &&
                Regex("u:object_r:[a-zA-Z0-9_]+:s[0-9]+(?::[a-zA-Z0-9_,.]+)?").matches(fields[3])) {
                "Emulator ownership, permissions or SELinux label could not be verified."
            }
            return mapOf("dataDir" to lines[2], "uid" to uid, "gid" to fields[1].toInt(), "mode" to fields[2], "label" to fields[3])
        }
    }
}
