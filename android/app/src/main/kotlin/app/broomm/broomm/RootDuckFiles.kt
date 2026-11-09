package app.broomm.broomm

import android.content.Context
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest

internal fun duckStorageLabel(path: String): ByteArray = try {
    Os.getxattr(path, "security.selinux")
} catch (e: ErrnoException) {
    if (e.errno != OsConstants.ENOENT) throw e
    throw IllegalStateException("Open DuckStation once, finish initialization, close any game and return to Broomm before setup.", e)
}

/** File effects only. Dart owns profile/game assignment, configuration loans,
 * cloud choices, durable checkpoints and recovery. No original save is adopted. */
internal class RootDuckFiles(private val context: Context, private val identity: Map<String, Any>,
    private val live: () -> Unit, private val closed: () -> Unit, private val checkpoint: (String) -> Unit = {}) {
    private val pkg = "com.github.stenzek.duckstation"
    private val uid = identity.getValue("uid") as Int
    private val internal = File(identity.getValue("dataDir") as String).canonicalFile
    private val internalLabel = duckStorageLabel(internal.path)
    val logical = "/storage/emulated/0/Android/data/$pkg/files"
    private val root = File("/data/media/0/Android/data/$pkg/files")
    private val label = duckStorageLabel(root.path)
    private val gid = Os.lstat(root.path).st_gid
    init {
        require(identity["package"] == pkg && identity["user"] == 0)
        require(root.canonicalPath == root.path && File(logical).canonicalPath == logical)
        directory(root)
        require(snapshot(Os.lstat(root.path)) == snapshot(Os.lstat(logical)) &&
            Os.getxattr(logical, "security.selinux").contentEquals(label) &&
            String(label).trimEnd('\u0000') == String(internalLabel).trimEnd('\u0000').replace("app_data_file:", "media_rw_data_file:"))
    }
    fun report(): Bundle {
        closed(); val info = Os.lstat(root.path)
        val config = File(root, "settings.ini")
        require(present(config)) { "Open DuckStation once, finish initialization, close its game and return to Broomm before setup." }
        return Bundle().apply {
            putString("label", String(internalLabel).trimEnd('\u0000')); putString("externalLabel", String(label).trimEnd('\u0000'))
            putString("externalGid", gid.toString()); putString("externalMode", (info.st_mode and 4095).toString(8))
            putString("externalDevice", info.st_dev.toString()); putString("externalInode", info.st_ino.toString())
            putString("apk", RootDuckImage.APK); putString("abi", "arm64-v8a")
            putByteArray("config", small(config, 262144)); putBundle("settings", entry(config, 262144))
            putBundle("bios", Bundle().apply {
                val dir = File(root, "bios")
                if (present(dir)) {
                    directory(dir); val names = dir.list() ?: error("DuckStation BIOS enumeration failed."); require(names.size <= 32)
                    for (name in names.sorted()) {
                        require(Regex("[A-Za-z0-9_. -]{1,120}").matches(name))
                        val file = path(dir, name); require(Os.lstat(file.path).st_size == 524288L)
                        putBundle(name, entry(file, 524288))
                    }
                }
            })
        }.also { closed() }
    }
    fun validate(request: Bundle) {
        val info = Os.lstat(root.path)
        val expected = mapOf("externalLabel" to String(label).trimEnd('\u0000'), "externalGid" to gid.toString(),
            "externalMode" to (info.st_mode and 4095).toString(8), "externalDevice" to info.st_dev.toString(),
            "externalInode" to info.st_ino.toString(), "apk" to RootDuckImage.APK, "abi" to "arm64-v8a",
            "label" to String(internalLabel).trimEnd('\u0000'))
        require(expected.all { (k, v) -> request.getString(k) == v }) { "DuckStation storage generation changed. Recovery was kept." }
    }
    private fun profile(request: Bundle): File {
        val server = request.getString("server")!!; val profile = request.getString("profile")!!; val nonce = request.getString("ownerNonce")!!
        require(listOf(server, profile, nonce).all { HEX32.matches(it) })
        return path(root, "Broomm-PS1-$server-$profile-$nonce")
    }
    private fun owner(request: Bundle) = "BROOMM_DUCK_PROFILE_V1\n${request.getString("server")}/${request.getString("profile")}/${request.getString("ownerNonce")}\n${RootDuckImage.APK}:arm64-v8a\n".toByteArray()
    private fun verifyProfile(request: Bundle): File {
        val folder = profile(request); directory(folder)
        require(small(File(folder, "owner"), 1024).contentEquals(owner(request))) { "DuckStation profile ownership changed. Nothing was adopted." }
        attributes(File(folder, "profile.ini")); directory(File(folder, "games")); return folder
    }
    fun initialize(request: Bundle): Bundle {
        closed(); val folder = profile(request)
        if (present(folder) && !present(File(folder, "owner"))) return Bundle().apply { putString("status", "unclaimed") }
        if (!present(folder)) {
            mkdir(folder)
            for (name in listOf("games", "bios", "gamesettings", "inputprofiles", "screenshots", "unassigned", "unassigned/cards", "unassigned/states")) mkdir(path(folder, name))
            val bytes = request.getByteArray("config")!!; require(bytes.size <= 262144)
            create(File(folder, "profile.ini"), bytes)
            create(File(folder, "owner"), owner(request))
        }
        verifyProfile(request); closed()
        return Bundle().apply { putString("status", "ready"); putString("directory", folder.path.replace(root.path, logical)) }
    }
    private fun game(request: Bundle): String = request.getString("game")!!.also { require(Regex("[1-9][0-9]{0,19}").matches(it)) }
    private fun stateGroup(request: Bundle): String = request.getString("stateGroup")!!.also { require(Regex("states-[a-f0-9]{16}-android").matches(it)) }
    private fun selector(request: Bundle, relative: String): Boolean {
        val prefix = "games/${game(request)}/"
        return relative in setOf(prefix + "cards/card1.mcd", prefix + "cards/card2.mcd") ||
            relative.startsWith(prefix + "${stateGroup(request)}/") &&
            Regex("[A-Za-z0-9_-]{1,160}\\.sav(?:\\.bak)?").matches(relative.removePrefix(prefix + "${stateGroup(request)}/"))
    }
    private fun resolve(request: Bundle, relative: String, profileData: Boolean): Pair<File, File> {
        val profile = verifyProfile(request)
        if (relative == "@settings") {
            require(profileData); return root to File(root, "settings.ini")
        }
        if (relative.startsWith("@bios/")) {
            require(profileData && Regex("[A-Za-z0-9_. -]{1,120}").matches(relative.removePrefix("@bios/")))
            val dir = File(root, "bios"); directory(dir)
            return dir to path(dir, relative.removePrefix("@bios/"))
        }
        require(relative != "owner" && relative != "incoming" && !relative.startsWith("incoming/"))
        require(profileData || selector(request, relative))
        return profile to path(profile, relative)
    }
    fun prepareGame(request: Bundle): Bundle {
        closed(); val profile = verifyProfile(request)
        for (name in listOf("games/${game(request)}", "games/${game(request)}/cards", "games/${game(request)}/${stateGroup(request)}")) {
            val dir = path(profile, name); if (!present(dir)) mkdir(dir) else directory(dir)
        }
        closed(); return Bundle()
    }
    fun inventory(request: Bundle, profileData: Boolean = false): Bundle {
        closed(); val folder = verifyProfile(request); val selected = mutableListOf<File>()
        var nodes = 0; var total = 0L
        fun walk(dir: File, depth: Int) {
            require(depth <= 20 && ++nodes <= 16384); directory(dir)
            val names = dir.list() ?: error("DuckStation inventory failed."); require(names.size <= 8192)
            for (name in names.sorted()) {
                live(); val file = path(dir, name); val relative = file.path.removePrefix(folder.path + "/")
                if (relative == "owner" || relative == "incoming") continue
                val s = Os.lstat(file.path)
                if (OsConstants.S_ISDIR(s.st_mode)) walk(file, depth + 1)
                else if (profileData || selector(request, relative)) {
                    attributes(file); require(s.st_size in 0..MAX_FILE.toLong()); total += s.st_size
                    require(total <= if (profileData) 2L * 1024 * 1024 * 1024 else 512L * 1024 * 1024)
                    require(selected.size < 8192); selected.add(file)
                }
            }
        }
        if (profileData) walk(folder, 0) else {
            val game = path(folder, "games/${game(request)}")
            if (present(game)) {
                for (relative in listOf("cards", stateGroup(request))) {
                    val dir = path(game, relative); if (present(dir)) walk(dir, 0)
                }
            }
        }
        return page(request, folder, selected, MAX_FILE)
    }

    private fun page(request: Bundle, memory: File, selected: List<File>, limit: Int): Bundle {
        val paths = selected.associateBy { it.path.removePrefix(memory.path + "/") }.toSortedMap()
        val cursor = request.getString("cursor")
        require(cursor == null || paths.containsKey(cursor)) { "DuckStation inventory changed between pages. Nothing was inferred missing." }
        val files = Bundle(); var encoded = 0; var next: String? = null
        for ((relative, file) in paths) {
            require(relative.toByteArray(Charsets.UTF_8).size <= 1024)
            if (cursor != null && relative <= cursor) continue
            val metadata = attributes(file)
            val estimate = 256 + 2 * (relative.length + metadata.length + 64)
            if (encoded + estimate > 192 * 1024) { require(!files.isEmpty); next = files.keySet().maxOrNull(); break }
            encoded += estimate; files.putBundle(relative, entry(file, limit))
        }
        closed()
        return Bundle().apply { putBundle("files", files); putString("next", next) }
    }

    fun capture(request: Bundle, descriptor: ParcelFileDescriptor, caller: Int, profileData: Boolean = false): Bundle {
        closed(); val relative = request.getString("path")!!
        val file = resolve(request, relative, profileData).second; val expected = request.getString("metadata")!!
        require(attributes(file) == expected)
        val fd = descriptor.fileDescriptor; val s = Os.fstat(fd)
        require(OsConstants.S_ISREG(s.st_mode) && s.st_uid == caller && s.st_nlink == 1L && s.st_size == 0L)
        ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { out ->
            val e = stream(file, if (profileData) PROFILE_FILE else MAX_FILE) { b, n -> out.write(b, 0, n) }
            require(e.getLong("bytes") == request.getLong("bytes") && e.getString("sha256") == request.getString("sha256") &&
                e.getString("metadata") == expected) { "DuckStation progress changed during capture. Recovery was kept." }
            out.flush(); Os.fsync(fd); require(Os.fstat(fd).st_size == e.getLong("bytes"))
        }
        closed(); return Bundle()
    }

    fun replace(request: Bundle, descriptor: ParcelFileDescriptor?, caller: Int, profileData: Boolean = false): Bundle {
        closed(); val relative = request.getString("path")!!
        require(!relative.startsWith("@bios/")) { "Original DuckStation firmware is read-only." }
        val limit = if (relative in setOf("@settings", "profile.ini")) 262144 else if (profileData) PROFILE_FILE else MAX_FILE
        val (memory, file) = resolve(request, relative, profileData)
        val before = request.getString("before"); val after = request.getString("after")
        val desiredMode = request.getString("mode")?.also { require(profileData && Regex("6[0246]0").matches(it)) }?.toInt(8)
        val token = request.getString("token")!!; require(HEX32.matches(token))
        require(listOfNotNull(before, after).all { HEX64.matches(it) } && (after == null) == (descriptor == null))
        val stageDir = File(verifyProfile(request), "incoming")
        if (!present(stageDir)) mkdir(stageDir) else directory(stageDir)
        val stage = File(stageDir, token)
        if (present(file) && present(stage)) {
            val a = Os.lstat(file.path); val b = Os.lstat(stage.path)
            if (a.st_dev == b.st_dev && a.st_ino == b.st_ino) {
                require(after != null && a.st_nlink == 2L && attributes(file, 2).substringBeforeLast(' ') == attributes(stage, 2).substringBeforeLast(' ') &&
                    stream(file, limit, links = 2).getString("sha256") == after)
                closed(); Os.remove(stage.path); flush(stageDir)
            }
        }
        val observed = if (present(file)) entry(file, limit) else null
        if (observed?.getString("sha256") == after && (desiredMode == null || observed?.getString("metadata")?.split(' ')?.get(2)?.toInt(8) == desiredMode)) return observed ?: Bundle()
        require(observed?.getString("sha256") == before) { "Native DuckStation progress changed before publication. Recovery was kept." }
        if (observed != null) require(observed.getString("metadata") == request.getString("metadata")) { "Native DuckStation file identity changed. Recovery was kept." }
        if (after == null) {
            closed(); require(sameEntry(entry(file, limit), observed))
            Os.remove(file.path); flush(file.parentFile!!); closed(); return Bundle()
        }
        parents(file, memory)
        if (present(stage)) {
            val s = Os.lstat(stage.path)
            val sourceFd = descriptor!!.fileDescriptor; val source = Os.fstat(sourceFd)
            val stageLabel = Os.getxattr(stage.path, "security.selinux")
            require(OsConstants.S_ISREG(source.st_mode) && source.st_uid == caller && source.st_nlink == 1L && source.st_size in 0..limit.toLong())
            require(OsConstants.S_ISREG(s.st_mode) && s.st_dev == Os.lstat(stageDir.path).st_dev &&
                s.st_uid in setOf(0, uid) && s.st_gid in setOf(0, gid) && s.st_nlink == 1L &&
                s.st_size in 0..source.st_size && (s.st_mode and 4095) in setOf(384, 400, 416, 432) &&
                (stageLabel.contentEquals(label) || (s.st_mode and 4095) == 384 &&
                    String(stageLabel).trimEnd('\u0000') == "u:object_r:media_rw_data_file:s0"))
            // Only the journal's deterministic private stage may be reclaimed.
            // Compare every retained byte with the held caller-owned source;
            // a different stage or linked/public file is never truncated.
            FileInputStream(stage).use { old ->
                FileInputStream(Os.dup(sourceFd)).use { input ->
                    Os.lseek(input.fd, 0, OsConstants.SEEK_SET)
                    val a = ByteArray(65536); val b = ByteArray(65536); var remaining = s.st_size
                    while (remaining > 0) {
                        live(); val n = minOf(a.size.toLong(), remaining).toInt()
                        var offset = 0
                        while (offset < n) { val read = old.read(a, offset, n - offset); require(read > 0); offset += read }
                        offset = 0
                        while (offset < n) { val read = input.read(b, offset, n - offset); require(read > 0); offset += read }
                        require(a.copyOf(n).contentEquals(b.copyOf(n))) { "Private DuckStation incoming bytes changed. Recovery was kept." }
                        remaining -= n
                    }
                }
            }
            require(snapshot(Os.fstat(sourceFd)) == snapshot(source) && snapshot(Os.lstat(stage.path)) == snapshot(s))
            closed(); live(); Os.remove(stage.path); flush(stageDir); Os.lseek(sourceFd, 0, OsConstants.SEEK_SET)
        }
        run {
            val inputFd = descriptor!!.fileDescriptor; val source = Os.fstat(inputFd)
            require(OsConstants.S_ISREG(source.st_mode) && source.st_uid == caller && source.st_nlink == 1L && source.st_size in 0..limit.toLong())
            val outputFd = Os.open(stage.path, OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_WRONLY or OsConstants.O_NOFOLLOW, 384)
            val digest = MessageDigest.getInstance("SHA-256"); var bytes = 0L
            FileOutputStream(outputFd).use { out ->
                ParcelFileDescriptor.AutoCloseInputStream(descriptor).use { input ->
                    val buffer = ByteArray(65536)
                    while (true) { live(); val n = input.read(buffer); if (n < 0) break
                        bytes += n; require(bytes <= source.st_size); digest.update(buffer, 0, n); out.write(buffer, 0, n); checkpoint("file-stage-bytes") }
                    require(bytes == source.st_size && snapshot(Os.fstat(inputFd)) == snapshot(source))
                }
                out.flush(); Os.fsync(outputFd)
            }
            require(digest.digest().hex() == after)
            Os.chown(stage.path, uid, gid)
            Os.chmod(stage.path, desiredMode ?: observed?.getString("metadata")?.split(' ')?.get(2)?.toInt(8) ?: 432)
            Os.setxattr(stage.path, "security.selinux", label, 0); syncFile(stage); flush(stageDir)
        }
        checkpoint("file-staged")
        require(entry(stage, limit).getString("sha256") == after)
        closed(); live()
        require(sameEntry(if (present(file)) entry(file, limit) else null, observed)) { "DuckStation progress changed at publication. Recovery was kept." }
        if (before == null) {
            // Exclusive link publication never falls back to replacement.
            Os.link(stage.path, file.path); flush(file.parentFile!!)
            checkpoint("file-linked")
            require(Os.lstat(file.path).st_ino == Os.lstat(stage.path).st_ino && Os.lstat(file.path).st_nlink == 2L)
            closed(); Os.remove(stage.path)
        } else Os.rename(stage.path, file.path)
        flush(file.parentFile!!); flush(stageDir)
        checkpoint("file-published")
        val result = entry(file, limit); require(result.getString("sha256") == after); closed(); return result
    }

    private fun sameEntry(first: Bundle?, other: Bundle?): Boolean =
        if (first == null || other == null) first == null && other == null else
            first.getLong("bytes") == other.getLong("bytes") && first.getString("sha256") == other.getString("sha256") && first.getString("metadata") == other.getString("metadata")

    private fun path(base: File, relative: String): File {
        require(relative.toByteArray(Charsets.UTF_8).size <= 1024)
        var file = base
        val parts = relative.split('/'); require(parts.size <= 24)
        for (part in parts) {
            require(part.isNotEmpty() && part != "." && part != ".." && part.toByteArray(Charsets.UTF_8).size <= 255 &&
                part.none { it.code < 32 || it.code == 127 || it == '\\' || it == '\u0000' })
            file = File(file, part)
            if (present(file)) require(!OsConstants.S_ISLNK(Os.lstat(file.path).st_mode))
        }
        require(file.canonicalPath == file.path)
        return file
    }
    private fun present(file: File): Boolean = try { Os.lstat(file.path); true }
    catch (e: ErrnoException) { if (e.errno == OsConstants.ENOENT) false else throw e }
    private fun directory(file: File) {
        val s = Os.lstat(file.path)
        require(OsConstants.S_ISDIR(s.st_mode) && s.st_uid == uid && s.st_gid == gid &&
            (s.st_mode and 7) == 0 && (s.st_mode and 448) == 448 && (s.st_mode and 2560) == 0 &&
            Os.getxattr(file.path, "security.selinux").contentEquals(label)) { "DuckStation directory ownership or permissions changed." }
    }
    private fun mkdir(dir: File) {
        live(); closed(); Os.mkdir(dir.path, 448)
        Os.chown(dir.path, uid, gid); Os.chmod(dir.path, 1528); Os.setxattr(dir.path, "security.selinux", label, 0)
        directory(dir); flush(dir); flush(dir.parentFile!!)
    }
    private fun parents(file: File, base: File) {
        require(file.path.startsWith(base.path + "/"))
        var current = base; directory(current)
        for (part in file.parentFile!!.path.removePrefix(base.path).split('/').filter { it.isNotEmpty() }) {
            current = path(current, part)
            if (!present(current)) mkdir(current) else directory(current)
        }
    }
    private fun create(file: File, bytes: ByteArray) {
        live(); closed()
        val fd = Os.open(file.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW, 384)
        FileOutputStream(fd).use { out -> out.write(bytes); out.flush(); Os.fsync(fd) }
        Os.chown(file.path, uid, gid); Os.chmod(file.path, 432); Os.setxattr(file.path, "security.selinux", label, 0)
        syncFile(file); flush(file.parentFile!!); require(small(file, bytes.size).contentEquals(bytes))
    }
    private fun attributes(file: File, links: Long = 1): String {
        val s = Os.lstat(file.path)
        require(OsConstants.S_ISREG(s.st_mode) && s.st_uid == uid && s.st_gid == gid && s.st_nlink == links &&
            (s.st_mode and 4095 and 432.inv()) == 0 && (s.st_mode and 384) == 384 &&
            Os.getxattr(file.path, "security.selinux").contentEquals(label)) { "DuckStation file ownership, permissions, links or label changed." }
        return "$uid $gid ${(s.st_mode and 4095).toString(8)} ${String(label).trimEnd('\u0000')} ${s.st_dev} ${s.st_ino} ${s.st_size} ${s.st_mtime}.${s.st_mtim.tv_nsec.toString().padStart(9, '0')} ${s.st_ctime}.${s.st_ctim.tv_nsec.toString().padStart(9, '0')} ${s.st_nlink}"
    }
    private fun entry(file: File, limit: Int = MAX_FILE): Bundle = stream(file, limit)
    private fun stream(file: File, limit: Int, links: Long = 1, consume: ((ByteArray, Int) -> Unit)? = null): Bundle {
        val named = Os.lstat(file.path)
        val metadata = attributes(file, links)
        require(snapshot(Os.lstat(file.path)) == snapshot(named))
        val fd = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW or OsConstants.O_NONBLOCK, 0)
        val digest = MessageDigest.getInstance("SHA-256"); var bytes = 0L
        FileInputStream(fd).use { input ->
            val before = Os.fstat(fd); require(snapshot(before) == snapshot(named) && before.st_size in 0..limit.toLong())
            val buffer = ByteArray(65536)
            while (true) { live(); val n = input.read(buffer); if (n < 0) break
                bytes += n; require(bytes <= before.st_size); digest.update(buffer, 0, n); consume?.invoke(buffer, n) }
            require(bytes == before.st_size && snapshot(Os.fstat(fd)) == snapshot(before) && attributes(file, links) == metadata)
        }
        return Bundle().apply { putLong("bytes", bytes); putString("sha256", digest.digest().hex()); putString("metadata", metadata) }
    }
    private fun small(file: File, limit: Int): ByteArray {
        val bytes = ByteArrayOutputStream(); stream(file, limit) { b, n -> bytes.write(b, 0, n) }; return bytes.toByteArray()
    }
    private fun flush(dir: File) {
        val fd = Os.open(dir.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        try { require(OsConstants.S_ISDIR(Os.fstat(fd).st_mode)); Os.fsync(fd) } finally { Os.close(fd) }
    }
    private fun syncFile(file: File) {
        val fd = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        try { require(OsConstants.S_ISREG(Os.fstat(fd).st_mode)); Os.fsync(fd) } finally { Os.close(fd) }
    }
    companion object {
        const val MAX_FILE = 256 * 1024 * 1024
        const val PROFILE_FILE = MAX_FILE
        private val HEX32 = Regex("[a-f0-9]{32}"); private val HEX64 = Regex("[a-f0-9]{64}")
        private fun ByteArray.hex() = joinToString("") { "%02x".format(it.toInt() and 255) }
        private fun snapshot(s: StructStat) = "${s.st_dev}:${s.st_ino}:${s.st_uid}:${s.st_gid}:${s.st_mode}:${s.st_size}:${s.st_mtim}:${s.st_ctim}:${s.st_nlink}"
    }
}
