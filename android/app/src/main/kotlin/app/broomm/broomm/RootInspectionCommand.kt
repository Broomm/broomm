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
        // Root UID alone does not expose other apps through Android's isolated
        // app-data mounts. Select the global namespace for this command only;
        // never modify root-manager policy or the application's namespace.
        val psp = pkg in PpssppStorageInspection.packages && user == 0
        val duck = pkg == DuckStationStorageInspection.PACKAGE && user == 0
        val script = SCRIPT + when {
            psp -> "\n" + PpssppStorageInspection.SCRIPT
            duck -> "\n" + DuckStationStorageInspection.SCRIPT
            else -> ""
        }
        val process = try { start(listOf("su", "-M", "-c", script)) }
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
                    if (exit != 0) throw when (exit) {
                        60 -> RootInspectionFailure("request-unreadable", "Root inspection could not read its request. Retry inspection.")
                        61 -> RootInspectionFailure("root-identity", "Root UID could not be verified. Check Broomm's grant in your root manager.")
                        62 -> RootInspectionFailure("directory-unavailable", "The emulator directory is unavailable to root inspection. Check that your root manager supports the global mount namespace (-M); granting root alone may leave other apps hidden.")
                        63 -> RootInspectionFailure("directory-unresolved", "The emulator directory could not be resolved. No storage connection was created.")
                        64 -> RootInspectionFailure("metadata-unavailable", "Emulator directory metadata could not be read. No storage connection was created.")
                        65 -> RootInspectionFailure("storage-unavailable", "PPSSPP's selected memory stick could not be verified. Open PPSSPP, wait for its menu, use Exit, then retry inspection. Nothing was connected or changed.")
                        66 -> RootInspectionFailure("storage-unavailable", "DuckStation's app-private files and initialized settings metadata could not be verified. Open DuckStation, complete first-run setup, wait for its menu, then retry inspection. Nothing was connected or changed.")
                        else -> RootInspectionFailure("failed", "Root command failed (exit $exit). Check Broomm's root grant and root-manager support for the global mount namespace (-M). No storage connection was created.")
                    }
                    // Do not log arbitrary su diagnostics (which can contain secrets
                    // or terminal controls), or mistake partial stdout for success.
                    if (stderr.size() != 0) throw RootInspectionFailure("failed", "Root inspection returned unexpected diagnostics. No storage connection was created.")
                    val output = stdout.toString("UTF-8")
                    return if (psp) PpssppStorageInspection.parse(output, roots, uid, pkg)
                        else if (duck) DuckStationStorageInspection.parse(output, roots, uid)
                        else parse(output, roots, uid)
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
            IFS= read -r root || exit 60
            identity="${'$'}(/system/bin/id -u)" || exit 61
            [ "${'$'}identity" = 0 ] || exit 61
            [ -d "${'$'}root" ] || exit 62
            real="${'$'}(/system/bin/readlink -f "${'$'}root")" || exit 63
            metadata="${'$'}(/system/bin/stat -c '%u %g %a %C' "${'$'}real")" || exit 64
            printf 'BROOMM_ROOT_V1\n0\n%s\n%s\n' "${'$'}real" "${'$'}metadata"
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
