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
    private val coreName: String = "mgba",
) {
    fun progressLimit(path: String): Int = limit(path, coreName)
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
    fun inventory(areas: List<Map<String, String>>): Map<String, BundleEntry> {
        require(areas.size in 1..2)
        val result = linkedMapOf<String, BundleEntry>()
        var total = 0L
        var base: String? = null
        for (area in areas) {
            val directory = area.getValue("path")
            val exact = area["exact"]
            val prefix = area["prefix"]
            require((exact != null && area.keys == setOf("path", "exact")) ||
                (prefix != null && area.keys == setOf("path", "prefix", "pattern")))
            val ordinary = directory.endsWith("/saves")
            val probe = "$directory/${exact ?: (prefix + if (ordinary) ".srm" else ".state")}"
            managedPath(probe, saveOnly = true)
            val owner = directory.substringBefore("/saves").substringBefore("/states")
            require(base == null || base == owner); base = owner
            require(if (exact != null) ordinary && exact.endsWith(".srm")
                else ordinary || Regex(".*/states/states-[a-f0-9]{16}-android").matches(directory))
            val folder = path(directory)
            if (!present(folder)) continue
            val stat = Os.lstat(folder.path)
            require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == uid &&
                Os.getxattr(folder.path, "security.selinux").contentEquals(label))
            val names = folder.list() ?: error("Cannot inspect the managed save directory.")
            require(names.size <= 1024) { "Managed save directory exceeds its entry limit." }
            val selected = names.filter { if (exact != null) it == exact else
                Regex(Regex.escape(prefix!!) + if (ordinary) "\\.(?:srm|rtc)" else
                    "\\.state(?:[0-9]{1,10}|\\.auto)?(?:\\.png)?").matches(it) }
            for (name in selected.sorted()) {
                live()
                val relative = "$directory/$name"
                managedPath(relative, saveOnly = true)
                require(!result.containsKey(relative) && result.size < 128) { "Too many rooted save files." }
                val file = path(relative)
                val metadata = metadata(file)
                val bytes = bytes(file, progressLimit(relative))
                total += bytes.size
                require(total <= 64L * 1024 * 1024) { "Rooted progress exceeds 64 MiB." }
                result[relative] = BundleEntry(bytes.size.toLong(), digest(bytes), metadata)
            }
        }
        return result
    }
    data class BundleEntry(val bytes: Long, val sha256: String, val metadata: String)

    fun replace(relative: String, before: String?, after: String?, payload: ByteArray?, wantedMetadata: String?, token: String, stateGroup: String? = null) =
        publish(relative, before, after, payload, wantedMetadata, token, progressLimit(relative),
            sessionConfiguration = relative.endsWith(".cfg"), stateGroup = stateGroup)

    private fun publish(relative: String, before: String?, after: String?, payload: ByteArray?,
                        wantedMetadata: String?, token: String, limit: Int,
                        sessionConfiguration: Boolean = false, stateGroup: String? = null, beforeCommit: () -> Unit = {}) {
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
            require(stateGroup == null || Regex("states-[a-f0-9]{16}-android").matches(stateGroup))
            parents(relative.substringBeforeLast('/') + "/states/" +
                (stateGroup?.let { "$it/" } ?: "") + "reserved.state", token)
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

    private data class CoreRead(val hash: String, val header: ByteArray)

    /** Core libraries can exceed the root service's heap. Never buffer their payloads. */
    private fun transferCore(file: File, owner: Int, links: Long = 1, out: FileOutputStream? = null): CoreRead {
        val fd = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW or OsConstants.O_NONBLOCK, 0)
        return FileInputStream(fd).use { input ->
            val stat = Os.fstat(fd)
            require(OsConstants.S_ISREG(stat.st_mode) && stat.st_uid == owner &&
                stat.st_nlink == links && stat.st_size in 20..MAX_CORE_BYTES.toLong()) { "Invalid RetroArch core file." }
            val digest = MessageDigest.getInstance("SHA-256")
            val header = ByteArray(20)
            val buffer = ByteArray(65536)
            var size = 0L
            while (true) {
                live()
                val count = input.read(buffer)
                if (count < 0) break
                require(size + count <= stat.st_size) { "RetroArch core grew while reading." }
                if (size < header.size) buffer.copyInto(header, size.toInt(), 0, minOf(count, header.size - size.toInt()))
                out?.write(buffer, 0, count)
                digest.update(buffer, 0, count)
                size += count
                checkpoint("core-chunk")
            }
            fun unchanged(current: android.system.StructStat): Boolean =
                current.st_dev == stat.st_dev && current.st_ino == stat.st_ino &&
                current.st_uid == owner && current.st_nlink == links &&
                current.st_mode == stat.st_mode && current.st_size == stat.st_size &&
                current.st_mtime == stat.st_mtime && current.st_ctime == stat.st_ctime
            require(size == stat.st_size && unchanged(Os.fstat(fd)) && unchanged(Os.lstat(file.path))) {
                "RetroArch core changed while reading. Existing files were kept."
            }
            CoreRead(digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }, header)
        }
    }

    fun core(abi: String? = null, recoverPublication: Boolean = false, coreName: String = "mgba"): String? {
        val file = path(corePath(coreName))
        if (!present(file)) return null
        val stat = Os.lstat(file.path)
        metadata(file, if (recoverPublication && stat.st_nlink == 2L) 2 else 1)
        val content = transferCore(file, uid, stat.st_nlink)
        if (abi != null) require(retroArchElfAbi(content.header) == abi) {
            "The installed RetroArch core does not match this RetroArch build. Repair it in RetroArch before continuing."
        }
        val digest = content.hash
        if (stat.st_nlink == 2L) {
            val stage = File(file.parentFile, ".${file.name}.broomm-${digest.take(32)}-in")
            val linked = Os.lstat(stage.path)
            require(linked.st_dev == stat.st_dev && linked.st_ino == stat.st_ino &&
                metadata(stage, 2) == metadata(file, 2)) { "Unexpected RetroArch core links. Existing files were kept." }
            live(); Os.remove(stage.path); flushDirectory(file.parentFile!!)
        }
        metadata(file)
        return digest
    }

    fun installCore(source: File, caller: Int, expected: String, abi: String, coreName: String = "mgba", ensureClosed: () -> Unit): String {
        require(Regex("[a-f0-9]{64}").matches(expected))
        val content = transferCore(source, caller)
        require(content.hash == expected && retroArchElfAbi(content.header) == abi) {
            "The staged RetroArch core failed ABI or checksum verification."
        }
        ensureClosed()
        core(abi, recoverPublication = true, coreName = coreName)?.let { return it }
        val relative = corePath(coreName)
        val token = expected.take(32) + "-in"
        parents(relative, token)
        val file = path(relative)
        val stage = File(file.parentFile, ".${file.name}.broomm-$token")
        if (present(stage)) {
            val old = Os.lstat(stage.path)
            require(OsConstants.S_ISREG(old.st_mode) && old.st_nlink == 1L && old.st_uid in setOf(0, uid))
            live(); Os.remove(stage.path)
        }
        val mode = "$uid $uid 600 ${String(label).trimEnd('\u0000')}"
        val fd = Os.open(stage.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW, 384)
        FileOutputStream(fd).use { out ->
            val copied = transferCore(source, caller, out = out)
            require(copied.hash == expected && retroArchElfAbi(copied.header) == abi) { "RetroArch core changed before staging." }
            out.flush(); checkpoint("staged")
            attributes(stage, mode); Os.fsync(fd)
        }
        require(transferCore(stage, uid).hash == expected && metadata(stage) == mode)
        live(); ensureClosed(); live()
        require(!present(file)) { "RetroArch core appeared before publication. Existing files were kept." }
        Os.link(stage.path, file.path)
        checkpoint("linked")
        flushDirectory(file.parentFile!!)
        Os.remove(stage.path); flushDirectory(file.parentFile!!)
        require(core(abi, coreName = coreName) == expected && metadata(file) == mode)
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

    private fun transferRom(file: File, owner: Int, out: FileOutputStream? = null, links: Long = 1, limit: Long = 32L * 1024 * 1024): String {
        val fd = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW or OsConstants.O_NONBLOCK, 0)
        return FileInputStream(fd).use { input ->
            val stat = Os.fstat(fd)
            require(OsConstants.S_ISREG(stat.st_mode) && stat.st_uid == owner &&
                stat.st_nlink == links && stat.st_size in 1..limit) { "Invalid RetroArch ROM file" }
            val hash = MessageDigest.getInstance("SHA-256")
            val buffer = ByteArray(65536)
            var size = 0L
            while (true) {
                live()
                val count = input.read(buffer)
                if (count < 0) break
                size += count
                require(size <= stat.st_size) { "RetroArch ROM grew while reading" }
                out?.write(buffer, 0, count)
                hash.update(buffer, 0, count)
            }
            val current = Os.lstat(file.path)
            require(size == stat.st_size && current.st_dev == stat.st_dev &&
                current.st_ino == stat.st_ino && current.st_size == size &&
                current.st_mtime == stat.st_mtime && current.st_ctime == stat.st_ctime) { "RetroArch ROM changed while reading" }
            hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
        }
    }

    fun stageRom(relative: String, source: File, caller: Int, expected: String, prepared: Boolean = false): File {
        val parts = romPath(relative)
        val limit = romLimit(parts[3])
        require(source.name == parts[3])
        if (prepared) {
            require(Regex("cartridge-[a-zA-Z0-9_-]+").matches(source.parentFile!!.name) &&
                source.parentFile!!.parentFile!!.name == parts[2].removePrefix("rom-") &&
                source.parentFile!!.parentFile!!.parentFile!!.name == "shared-session")
        } else require(source.path.substringBefore("/content/").substringAfterLast('/') == parts[1])
        val target = path(relative)
        val directory = target.parentFile!!
        require(!present(directory)) { "RetroArch session ROM directory already exists. Finish recovery first." }
        parents(relative, parts[2].removePrefix("rom-") + "-in")
        val stage = File(directory, ".pending")
        val mode = "$uid $uid 400 ${String(label).trimEnd('\u0000')}"
        val fd = Os.open(stage.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW, 384)
        FileOutputStream(fd).use { out ->
            require(transferRom(source, caller, out, limit = limit) == expected) { "RetroArch ROM changed before staging" }
            attributes(stage, mode)
            Os.fsync(fd)
        }
        require(transferRom(stage, uid, limit = limit) == expected && metadata(stage) == mode) { "Staged RetroArch ROM failed verification" }
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
        val entries = directory.listFiles() ?: error("Cannot inspect staged RetroArch ROM")
        require(entries.all { it.name == ".pending" || it == target }) { "Unexpected files in RetroArch ROM staging directory" }
        for (entry in entries) {
            val stat = Os.lstat(entry.path)
            require(OsConstants.S_ISREG(stat.st_mode) && stat.st_nlink in 1L..2L)
            if (stat.st_nlink == 2L) {
                val other = Os.lstat(File(directory, if (entry == target) ".pending" else target.name).path)
                require(stat.st_dev == other.st_dev && stat.st_ino == other.st_ino)
            }
            if (entry == target || stat.st_uid != 0) metadata(entry, stat.st_nlink)
            if (entry == target) require(transferRom(entry, uid, links = stat.st_nlink, limit = romLimit(target.name)) == expected) {
                "Staged RetroArch ROM changed. Its files were kept."
            }
        }
        live()
        for (entry in entries) Os.remove(entry.path)
        flushDirectory(directory)
        Os.remove(directory.path)
        flushDirectory(directory.parentFile!!)
    }

    private fun romLimit(name: String): Long =
        (if (coreName == "mupen64plus_next" && name.substringAfterLast('.').lowercase() in setOf("z64", "v64", "n64")) 64L else 32L) * 1024 * 1024

    companion object {
        const val MAX_BYTES = 262144
        private const val MAX_CORE_BYTES = 96 * 1024 * 1024
        const val MAX_STATE_BYTES = 16 * 1024 * 1024
        fun corePath(core: String): String {
            require(core in setOf("mgba", "snes9x", "gambatte", "stella", "mednafen_pce_fast", "genesis_plus_gx", "picodrive", "mupen64plus_next"))
            return "cores/${if (core == "mupen64plus_next") "mupen64plus_next_gles3" else core}_libretro_android.so"
        }
        fun limit(path: String, core: String = "mgba"): Int = when {
            path.contains("/states/") -> if (core == "mupen64plus_next") 32 * 1024 * 1024 else MAX_STATE_BYTES
            core == "mupen64plus_next" && path.endsWith(".srm") -> 296960
            else -> MAX_BYTES
        }
        fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
        fun managedPath(path: String, saveOnly: Boolean = false) {
            val save = "saves/[^/]+\\.(?:srm|rtc)"
            val state = "states/states-[a-f0-9]{16}-android/[^/]+\\.state(?:[0-9]{1,10}|\\.auto)?(?:\\.png)?"
            val suffix = if (saveOnly) "(?:$save|$state)" else "(?:$save|$state|config-[a-f0-9]{32}\\.cfg)"
            require(path.length <= 512 && path.none { it.code < 32 || it == '\\' } &&
                path.split('/').none { it == "." || it == ".." } &&
                Regex("files/Broomm/[a-f0-9]{32}/[a-zA-Z0-9_-]{1,128}/$suffix").matches(path)) { "Root path is outside the selected managed RetroArch files." }
        }

        fun romPath(path: String): List<String> {
            require(path.length <= 512 && path.none { it.code < 32 || it == '\\' } &&
                Regex("files/Broomm/[a-f0-9]{32}/[1-9][0-9]*/rom-[a-f0-9]{32}/[^/]+(?i:\\.(?:gba|sfc|smc|gb|gbc|dmg|a26|bin|pce|md|gen|smd|sms|sg|gg|32x|z64|v64|n64))")
                    .matches(path)) { "ROM path is outside the rooted RetroArch session" }
            return path.split('/').drop(2)
        }
    }
}
