package app.broomm.broomm

import java.io.Closeable
import java.io.File
import java.io.RandomAccessFile
import java.nio.channels.FileLock

class SharedDocumentBusy : IllegalStateException("A shared save transfer is still running. Wait before retrying recovery.")

/** Retained OS locks plus process-wide admission across Flutter activities.
 * Never open/close another descriptor while this process holds the same POSIX
 * lock: closing it can silently release the first descriptor's OS exclusion. */
object SharedDocumentLock {
    private val gate = Any()
    private val held = HashSet<String>()
    private fun path(directory: File): File {
        require(directory.canonicalPath == directory.absolutePath &&
            (directory.isDirectory || directory.mkdir())) { "Invalid shared transfer lock directory" }
        return File(directory, "mmj-document-io.lock").also {
            require(it.canonicalPath == it.absolutePath && !it.isDirectory) { "Invalid shared transfer lock file" }
        }
    }
    fun acquire(directory: File): Lease = synchronized(gate) {
        val path = path(directory)
        if (path.path in held) throw SharedDocumentBusy()
        val file = RandomAccessFile(path, "rw")
        try {
            val lock = file.channel.tryLock() ?: throw SharedDocumentBusy()
            held.add(path.path)
            Lease(path.path, file, lock)
        } catch (e: Exception) { file.close(); throw e }
    }
    fun busy(directory: File): Boolean = synchronized(gate) {
        if (path(directory).path in held) return@synchronized true
        try { acquire(directory).use { false } } catch (_: SharedDocumentBusy) { true }
    }
    class Lease internal constructor(
        private val path: String, private val file: RandomAccessFile, private val lock: FileLock
    ) : Closeable {
        private var closed = false
        override fun close() = synchronized(gate) {
            if (!closed) {
                closed = true
                try { lock.release() }
                finally { try { file.close() } finally { held.remove(path) } }
            }
        }
    }
}
