package app.broomm.broomm

import android.system.Os
import android.system.OsConstants
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.zip.ZipFile

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
    fun replace(relative: String, before: String?, after: String?, payload: ByteArray?, wantedMetadata: String?, token: String) =
        publish(relative, before, after, payload, wantedMetadata, token, MAX_BYTES,
            sessionConfiguration = relative.endsWith(".cfg"))

    private fun publish(relative: String, before: String?, after: String?, payload: ByteArray?,
                        wantedMetadata: String?, token: String, limit: Int,
                        sessionConfiguration: Boolean = false, beforeCommit: () -> Unit = {}) {
        live()
        require(Regex("[a-f0-9]{32}-(in|out)").matches(token))
        require(listOfNotNull(before, after).all { Regex("[a-f0-9]{64}").matches(it) })
        require((after == null) == (payload == null))
        if (payload != null) require(payload.size <= limit && digest(payload) == after)
        val file = path(relative)
        val stage = File(file.parentFile, ".${file.name}.broomm-$token")
        // Reclaim ONLY the deterministic private stage named by this journal's
        // token after an interrupted exclusive publication.
        if (present(file) && present(stage)) {
            val a = Os.lstat(file.path); val b = Os.lstat(stage.path)
            if (a.st_ino == b.st_ino && a.st_dev == b.st_dev) {
                require(after != null && a.st_nlink == 2L && metadata(file, 2) == metadata(stage, 2) && hash(file, limit) == after)
                live(); Os.remove(stage.path); flushDirectory(file.parentFile!!)
            }
        }
        fun current(): String? = if (present(file)) { metadata(file); hash(file, limit) } else null
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
        if (sessionConfiguration) {
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
        require(hash(stage, limit) == after && metadata(stage) == mode)
        live(); beforeCommit(); require(current() == before)
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

    fun mgba(abi: String? = null, recoverPublication: Boolean = false): String? {
        val file = path(MGBA_PATH)
        if (!present(file)) return null
        val stat = Os.lstat(file.path)
        metadata(file, if (recoverPublication && stat.st_nlink == 2L) 2 else 1)
        val payload = bytes(file, 32 * 1024 * 1024)
        if (abi != null) require(retroArchElfAbi(payload) == abi) {
            "The installed mGBA core does not match this RetroArch build. Repair it in RetroArch before continuing."
        }
        val digest = digest(payload)
        if (stat.st_nlink == 2L) {
            val stage = File(file.parentFile, ".${file.name}.broomm-${digest.take(32)}-in")
            val linked = Os.lstat(stage.path)
            require(linked.st_dev == stat.st_dev && linked.st_ino == stat.st_ino &&
                metadata(stage, 2) == metadata(file, 2)) { "Unexpected mGBA links. Existing files were kept." }
            live(); Os.remove(stage.path); flushDirectory(file.parentFile!!)
        }
        metadata(file)
        return digest
    }

    fun installMgba(source: File, caller: Int, expected: String, abi: String, ensureClosed: () -> Unit): String {
        require(Regex("[a-f0-9]{64}").matches(expected))
        val stat = Os.lstat(source.path)
        require(OsConstants.S_ISREG(stat.st_mode) && stat.st_uid == caller && stat.st_nlink == 1L)
        val payload = bytes(source, MAX_CORE_BYTES)
        require(digest(payload) == expected && retroArchElfAbi(payload) == abi) {
            "The staged mGBA core failed ABI or checksum verification."
        }
        ensureClosed()
        mgba(abi, recoverPublication = true)?.let { return it }
        publish(MGBA_PATH, null, expected, payload, null, expected.take(32) + "-in", MAX_CORE_BYTES, beforeCommit = ensureClosed)
        return expected
    }

    // Recognize the standard bundle before asking the player to initialize it.
    // The stock launcher extracts the resources as the emulator's own UID.
    fun needsFrontendAssets(apk: () -> File): Boolean {
        val menuFiles = listOf("assets/ozone/regular.ttf", "assets/ozone/bold.ttf",
            "assets/ozone/png/icons/settings.png")
        if (menuFiles.all { relative ->
            val file = File(root, relative)
            file.canonicalPath == file.absolutePath && file.isFile && file.length() > 0
        }) return false
        return ZipFile(apk()).use { zip ->
            menuFiles.all { zip.getEntry("assets/$it")?.size?.let { size -> size > 0 } == true }
        }
    }

    fun needsControllerProfiles(): Boolean {
        val dir = File(root, "autoconfig/android")
        if (dir.canonicalPath != dir.absolutePath) return false
        return dir.list()?.none { it.endsWith(".cfg") } ?: true
    }

    fun controllerProfilesReady(build: String): Boolean {
        val marker = path("${controllerProfilePath(build)}/.complete")
        if (!present(marker)) return false
        metadata(marker)
        require(hash(marker) == digest(build.toByteArray())) { "The managed controller profile record changed." }
        return true
    }

    fun prepareControllerProfiles(apk: File, build: String, ensureClosed: () -> Unit) {
        if (controllerProfilesReady(build)) return
        val target = controllerProfilePath(build)
        val profiles = RetroArchControllerProfiles.read(apk, live)
        ensureClosed()
        val token = build.take(32) + "-in"
        for ((name, bytes) in profiles)
            publish("$target/android/$name", null, digest(bytes), bytes, null, token, MAX_BYTES)
        val marker = build.toByteArray()
        publish("$target/.complete", null, digest(marker), marker, null, token, MAX_BYTES)
    }

    private fun controllerProfilePath(build: String): String {
        require(Regex("[a-f0-9]{64}").matches(build))
        return "files/Broomm/controller-profiles-$build"
    }

    private fun transferRom(file: File, owner: Int, out: FileOutputStream? = null, links: Long = 1): String {
        val fd = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW or OsConstants.O_NONBLOCK, 0)
        return FileInputStream(fd).use { input ->
            val stat = Os.fstat(fd)
            val limit = 32L * 1024 * 1024
            require(OsConstants.S_ISREG(stat.st_mode) && stat.st_uid == owner &&
                stat.st_nlink == links && stat.st_size in 1..limit) { "Invalid GBA ROM file" }
            val hash = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(65536)
            var size = 0L
            while (true) {
                live()
                val count = input.read(buffer)
                if (count < 0) break
                size += count
                require(size <= stat.st_size) { "GBA ROM grew while reading" }
                out?.write(buffer, 0, count)
                hash.update(buffer, 0, count)
            }
            val current = Os.lstat(file.path)
            require(size == stat.st_size && current.st_dev == stat.st_dev &&
                current.st_ino == stat.st_ino && current.st_size == size &&
                current.st_mtime == stat.st_mtime && current.st_ctime == stat.st_ctime) { "GBA ROM changed while reading" }
            hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
        }
    }

    fun stageRom(relative: String, source: File, caller: Int, expected: String): File {
        val parts = romPath(relative)
        require(source.name == parts[3] && source.path.substringBefore("/content/").substringAfterLast('/') == parts[1])
        val target = path(relative)
        val directory = target.parentFile!!
        require(!present(directory)) { "GBA session ROM directory already exists. Finish recovery first." }
        parents(relative, parts[2].removePrefix("rom-") + "-in")
        val stage = File(directory, ".pending")
        val mode = "$uid $uid 400 ${String(label).trimEnd('\u0000')}"
        val fd = Os.open(stage.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW, 384)
        FileOutputStream(fd).use { out ->
            require(transferRom(source, caller, out) == expected) { "GBA ROM changed before staging" }
            attributes(stage, mode)
            Os.fsync(fd)
        }
        require(transferRom(stage, uid) == expected && metadata(stage) == mode) { "Staged GBA ROM failed verification" }
        live()
        Os.link(stage.path, target.path)
        Os.remove(stage.path)
        flushDirectory(directory)
        require(metadata(target) == mode)
        return target
    }

    fun removeRom(relative: String, expected: String) {
        romPath(relative)
        val target = path(relative)
        val directory = target.parentFile!!
        if (!present(directory)) return
        val dir = Os.lstat(directory.path)
        require(OsConstants.S_ISDIR(dir.st_mode) && dir.st_uid == uid &&
            Os.getxattr(directory.path, "security.selinux").contentEquals(label))
        val entries = directory.listFiles() ?: error("Cannot inspect staged GBA ROM")
        require(entries.all { it.name == ".pending" || it == target }) { "Unexpected files in GBA ROM staging directory" }
        for (entry in entries) {
            val stat = Os.lstat(entry.path)
            require(OsConstants.S_ISREG(stat.st_mode) && stat.st_nlink in 1L..2L)
            if (stat.st_nlink == 2L) {
                val other = Os.lstat(File(directory, if (entry == target) ".pending" else target.name).path)
                require(stat.st_dev == other.st_dev && stat.st_ino == other.st_ino)
            }
            if (entry == target || stat.st_uid != 0) metadata(entry, stat.st_nlink)
            if (entry == target) require(transferRom(entry, uid, links = stat.st_nlink) == expected) {
                "Staged GBA ROM changed. Its files were kept."
            }
        }
        live()
        for (entry in entries) Os.remove(entry.path)
        flushDirectory(directory)
        Os.remove(directory.path)
        flushDirectory(directory.parentFile!!)
    }

    companion object {
        const val MAX_BYTES = 262144
        private const val MAX_CORE_BYTES = 8 * 1024 * 1024
        private const val MGBA_PATH = "cores/mgba_libretro_android.so"
        fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
        fun managedPath(path: String, saveOnly: Boolean = false) {
            val suffix = if (saveOnly) "saves/[^/]+\\.srm" else "(?:saves/[^/]+\\.srm|config-[a-f0-9]{32}\\.cfg)"
            require(path.length <= 512 && path.none { it.code < 32 || it == '\\' } &&
                Regex("files/Broomm/[a-f0-9]{32}/[a-zA-Z0-9_-]{1,128}/$suffix").matches(path)) { "Root path is outside the selected managed GBA files." }
        }

        fun romPath(path: String): List<String> {
            require(path.length <= 512 && path.none { it.code < 32 || it == '\\' } &&
                Regex("files/Broomm/[a-f0-9]{32}/[1-9][0-9]*/rom-[a-f0-9]{32}/[^/]+(?i:\\.gba)")
                    .matches(path)) { "ROM path is outside the rooted GBA session" }
            return path.split('/').drop(2)
        }
    }
}
