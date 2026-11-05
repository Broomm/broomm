package app.broomm.broomm

import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest

/** Descriptor/metadata checks and atomic publication; independently exercised on device. */
internal class RootSaveFiles(
    private val root: File, private val uid: Int, private val label: ByteArray,
    private val live: () -> Unit,
    private val checkpoint: (String) -> Unit = {},
) {
    fun present(file: File): Boolean = try { Os.lstat(file.path); true }
        catch (e: android.system.ErrnoException) { if (e.errno == OsConstants.ENOENT) false else throw e }
    fun path(relative: String): File {
        var file = root
        for (part in relative.split('/')) {
            require(part.isNotEmpty() && part != "." && part != ".." && part.none { it.code < 32 || it == '\\' })
            file = File(file, part)
            try { require(!OsConstants.S_ISLNK(Os.lstat(file.path).st_mode)) { "Linked emulator paths are unsupported." } }
            catch (e: android.system.ErrnoException) { if (e.errno != OsConstants.ENOENT) throw e }
        }
        return file
    }
    fun existing(relative: String): File = path(relative).also { metadata(it) }
    fun metadata(file: File, links: Long = 1): String {
        val s = Os.lstat(file.path)
        require(OsConstants.S_ISREG(s.st_mode) && s.st_nlink == links && (s.st_mode and 4095) <= 511 && s.st_uid == uid && Os.getxattr(file.path, "security.selinux").contentEquals(label)) { "Save ownership, links or security label changed. Files were kept." }
        return "${s.st_uid} ${s.st_gid} ${(s.st_mode and 511).toString(8)} ${String(label).trimEnd('\u0000')}"
    }
    fun bytes(file: File, max: Int): ByteArray {
        val fd = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        return FileInputStream(fd).use { input ->
            val stat = Os.fstat(fd)
            require(OsConstants.S_ISREG(stat.st_mode) && stat.st_size in 0..max.toLong()) { "Root file exceeds its supported size." }
            val out = java.io.ByteArrayOutputStream()
            val buffer = ByteArray(16384)
            while (true) { live(); val n = input.read(buffer); if (n < 0) break; require(out.size() + n <= max); out.write(buffer, 0, n) }
            require(out.size().toLong() == stat.st_size && Os.fstat(fd).st_mtime == stat.st_mtime && Os.lstat(file.path).st_ino == stat.st_ino) { "Root file changed during inspection." }
            out.toByteArray()
        }
    }
    fun hash(file: File, max: Int = MAX_BYTES): String = digest(bytes(file, max))
    private fun flushDirectory(dir: File) {
        val fd = Os.open(dir.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        try { require(OsConstants.S_ISDIR(Os.fstat(fd).st_mode)); Os.fsync(fd) } finally { Os.close(fd) }
    }
    private fun attributes(file: File, value: String) {
        val p = value.split(' ')
        require(p.size == 4 && p[0].toInt() == uid && p[1].toInt() >= 0 && Regex("[0-7]{3}").matches(p[2]) && p[3] == String(label).trimEnd('\u0000'))
        Os.chown(file.path, uid, p[1].toInt()); Os.chmod(file.path, p[2].toInt(8)); Os.setxattr(file.path, "security.selinux", label, 0)
    }
    private fun parents(relative: String, token: String) {
        var parent = root
        for (part in relative.split('/').dropLast(1)) {
            val target = File(parent, part)
            if (!present(target)) {
                // The native lock serializes Broomm writers. A stage is never
                // substituted for an existing public directory after failure.
                val stage = File(parent, ".broomm-dir-$token")
                live()
                if (present(stage)) {
                    val old = Os.lstat(stage.path)
                    require(OsConstants.S_ISDIR(old.st_mode) && old.st_uid in setOf(0, uid) && stage.list()?.isEmpty() == true)
                } else Os.mkdir(stage.path, 448)
                Os.chown(stage.path, uid, uid); Os.setxattr(stage.path, "security.selinux", label, 0)
                flushDirectory(stage)
                require(!present(target))
                Os.rename(stage.path, target.path); flushDirectory(parent)
            }
            val s = Os.lstat(target.path)
            require(OsConstants.S_ISDIR(s.st_mode) && (s.st_mode and 4095) <= 511 && s.st_uid == uid && Os.getxattr(target.path, "security.selinux").contentEquals(label))
            parent = target
        }
    }
    fun replace(relative: String, before: String?, after: String?, payload: ByteArray?, wantedMetadata: String?, token: String) {
        live()
        require(Regex("[a-f0-9]{32}-(in|out)").matches(token))
        require(listOfNotNull(before, after).all { Regex("[a-f0-9]{64}").matches(it) })
        require((after == null) == (payload == null))
        if (payload != null) require(payload.size <= MAX_BYTES && digest(payload) == after)
        val file = path(relative)
        val stage = File(file.parentFile, ".${file.name}.broomm-$token")
        // Reclaim ONLY the deterministic private stage named by this journal's
        // token after an interrupted exclusive publication.
        if (present(file) && present(stage)) {
            val a = Os.lstat(file.path); val b = Os.lstat(stage.path)
            if (a.st_ino == b.st_ino && a.st_dev == b.st_dev) {
                require(after != null && a.st_nlink == 2L && metadata(file, 2) == metadata(stage, 2) && hash(file) == after)
                live(); Os.remove(stage.path); flushDirectory(file.parentFile!!)
            }
        }
        fun current(): String? = if (present(file)) { metadata(file); hash(file) } else null
        val observed = current()
        if (observed == after) {
            if (present(file) && wantedMetadata != null) require(metadata(file) == wantedMetadata)
            return
        }
        require(observed == before) { "Emulator save changed before replacement. Recovery was kept." }
        if (after == null) {
            live(); require(current() == before); Os.remove(file.path); flushDirectory(file.parentFile!!); return
        }
        parents(relative, token)
        if (relative.endsWith(".cfg")) {
            parents(relative.substringBeforeLast('/') + "/saves/reserved.srm", token)
            parents(relative.substringBeforeLast('/') + "/states/reserved.state", token)
        }
        val mode = wantedMetadata ?: if (present(file)) metadata(file) else "$uid $uid 600 ${String(label).trimEnd('\u0000')}"
        if (present(stage)) {
            val s = Os.lstat(stage.path)
            require(OsConstants.S_ISREG(s.st_mode) && s.st_nlink == 1L && s.st_uid in setOf(0, uid))
            // This is a private, journal-owned stage, never the public save.
            live(); Os.remove(stage.path)
        }
        run {
            val fd = Os.open(stage.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW, 384)
            FileOutputStream(fd).use { out ->
                out.write(payload!!); out.flush(); checkpoint("staged")
                attributes(stage, mode); Os.fsync(fd)
            }
        }
        require(hash(stage) == after && metadata(stage) == mode)
        live(); require(current() == before)
        // Existing destination replacement is atomic. New publication uses an
        // exclusive hard-link; the deterministic stage permits interrupted-link recovery.
        if (before == null) {
            Os.link(stage.path, file.path)
            checkpoint("linked")
            flushDirectory(file.parentFile!!)
            Os.remove(stage.path)
        } else Os.rename(stage.path, file.path)
        flushDirectory(file.parentFile!!)
        require(current() == after && metadata(file) == mode)
    }
    companion object {
        const val MAX_BYTES = 262144
        fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
        fun managedPath(path: String, saveOnly: Boolean = false) {
            val suffix = if (saveOnly) "saves/[^/]+\\.srm" else "(?:saves/[^/]+\\.srm|config-[a-f0-9]{32}\\.cfg)"
            require(path.length <= 512 && path.none { it.code < 32 || it == '\\' } &&
                Regex("files/Broomm/[a-f0-9]{32}/[a-zA-Z0-9_-]{1,128}/$suffix").matches(path)) { "Root path is outside the selected managed GBA files." }
        }
    }
}
