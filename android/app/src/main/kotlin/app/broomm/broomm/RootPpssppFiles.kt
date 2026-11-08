package app.broomm.broomm

import android.content.Context
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.system.ErrnoException
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import org.json.JSONArray
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest

/** Narrow PPSSPP app-private file mechanism. Sessions, ownership decisions and recovery stay in Dart. */
internal class RootPpssppFiles(
    private val context: Context,
    private val identity: Map<String, Any>,
    private val live: () -> Unit,
    private val closed: () -> Unit,
    private val checkpoint: (String) -> Unit = {},
) {
    private val pkg = identity.getValue("package") as String
    private val uid = identity.getValue("uid") as Int
    private val internal = File(identity.getValue("dataDir") as String).canonicalFile
    private val internalLabel = Os.getxattr(internal.path, "security.selinux")
    val logical = "/storage/emulated/0/Android/data/$pkg/files"
    private val root = File("/data/media/0/Android/data/$pkg/files")
    private val label = Os.getxattr(root.path, "security.selinux")
    private val gid = Os.lstat(root.path).st_gid
    private val pointer = File(internal, "files/memstick_dir.txt")
    val abi: String

    init {
        checkpoint("identity")
        require(pkg == "org.ppsspp.ppsspp" && identity["user"] == 0)
        val app = context.packageManager.getApplicationInfo(pkg, 0)
        require(app.splitSourceDirs.isNullOrEmpty()) { "Root PSP saves require the reviewed universal PPSSPP 1.20.4 APK." }
        checkpoint("apk"); verifyApk(File(app.sourceDir)); checkpoint("apk-verified")
        val library = File(app.nativeLibraryDir, "libppsspp_jni.so")
        checkpoint("library"); require(library.canonicalPath == library.path)
        val h = ByteArray(64)
        library.inputStream().use { input -> var offset = 0
            while (offset < h.size) { val n = input.read(h, offset, h.size - offset); require(n > 0); offset += n } }
        require(h.size == 64 && h.take(4) == listOf(127.toByte(), 69.toByte(), 76.toByte(), 70.toByte()) && h[5] == 1.toByte())
        val machine = (h[18].toInt() and 255) or ((h[19].toInt() and 255) shl 8)
        abi = when (machine to h[4].toInt()) {
            183 to 2 -> "arm64-v8a"; 40 to 1 -> "armeabi-v7a"
            62 to 2 -> "x86_64"; 3 to 1 -> "x86"
            else -> error("Unsupported PPSSPP native ABI.")
        }
        checkpoint("storage")
        require(internal.path in setOf("/data/user/0/$pkg", "/data/data/$pkg") &&
            String(internalLabel).trimEnd('\u0000').startsWith("u:object_r:app_data_file:s0"))
        require(root.canonicalPath == root.path && File(logical).canonicalPath == logical)
        directory(root)
        require(snapshot(Os.lstat(root.path)) == snapshot(Os.lstat(logical)) &&
            Os.getxattr(logical, "security.selinux").contentEquals(label) &&
            String(label).trimEnd('\u0000') == String(internalLabel).trimEnd('\u0000').replace("app_data_file:", "media_rw_data_file:")) {
            "PPSSPP app-private storage correspondence changed. Recovery was kept."
        }
    }

    fun report(): Bundle {
        closed()
        val selected = pointerBytes()
        require(String(selected, Charsets.UTF_8) == logical) { "Finish PPSSPP’s previous Broomm handoff before connecting its root saves." }
        val config = path(root, "PSP/SYSTEM/ppsspp.ini")
        require(present(config)) { "Open PPSSPP once, wait for its menu and use Exit before setup." }
        val control = path(root, "PSP/SYSTEM/controls.ini")
        val info = Os.lstat(root.path)
        return Bundle().apply {
            putString("label", String(internalLabel).trimEnd('\u0000'))
            putString("externalLabel", String(label).trimEnd('\u0000'))
            putString("externalGid", gid.toString()); putString("externalMode", (info.st_mode and 4095).toString(8))
            putString("externalDevice", info.st_dev.toString()); putString("externalInode", info.st_ino.toString())
            putString("apk", APK); putString("abi", abi)
            putByteArray("config", small(config, 262144))
            putByteArray("controls", if (present(control)) small(control, 65536) else ByteArray(0))
        }.also { closed() }
    }

    fun validate(request: Bundle) {
        val info = Os.lstat(root.path)
        val expected = mapOf("externalLabel" to String(label).trimEnd('\u0000'), "externalGid" to gid.toString(),
            "externalMode" to (info.st_mode and 4095).toString(8), "externalDevice" to info.st_dev.toString(),
            "externalInode" to info.st_ino.toString(), "apk" to APK, "abi" to abi,
            "label" to String(internalLabel).trimEnd('\u0000'))
        require(expected.all { (k, v) -> request.getString(k) == v }) { "PPSSPP root storage identity changed. Recovery was kept." }
    }

    private fun profile(request: Bundle): File {
        val server = request.getString("server")!!; val profile = request.getString("profile")!!
        val nonce = request.getString("ownerNonce")!!
        require(listOf(server, profile, nonce).all { HEX32.matches(it) })
        return path(root, "Broomm-PSP-$server-$profile-$nonce")
    }
    private fun owner(request: Bundle) = "BROOMM_PSP_PROFILE_V1\n${request.getString("server")}/${request.getString("profile")}/${request.getString("ownerNonce")}\n$APK:$abi\n".toByteArray(Charsets.UTF_8)
    private fun verifyProfile(request: Bundle): File {
        val folder = profile(request); directory(folder)
        require(small(File(folder, "owner"), 1024).contentEquals(owner(request))) { "PPSSPP profile ownership changed. Nothing was adopted." }
        val memory = File(folder, "memstick"); directory(memory)
        for (name in listOf("PSP", "PSP/SYSTEM", "PSP/SAVEDATA", "PSP/PPSSPP_STATE")) directory(path(memory, name))
        attributes(path(memory, "PSP/SYSTEM/ppsspp.ini"))
        attributes(path(memory, "PSP/SYSTEM/controls.ini"))
        return memory
    }
    fun memoryPath(request: Bundle): String = verifyProfile(request).path.replace(root.path, logical)

    fun initialize(request: Bundle): Bundle {
        closed()
        val folder = profile(request)
        if (present(folder) && !present(File(folder, "owner")))
            return Bundle().apply { putString("status", "unclaimed") }
        if (present(folder)) {
            val memory = memoryPath(request)
            closed()
            return Bundle().apply { putString("status", "ready"); putString("memoryStick", memory) }
        }
        parents(folder, root)
        mkdir(folder)
        val marker = File(folder, "owner")
        val memory = File(folder, "memstick")
        if (!present(memory)) mkdir(memory) else directory(memory)
        for (name in listOf("PSP", "PSP/SYSTEM", "PSP/SAVEDATA", "PSP/PPSSPP_STATE")) {
            val dir = path(memory, name); parents(dir, memory)
            if (!present(dir)) mkdir(dir) else directory(dir)
        }
        for ((name, key, limit) in listOf(Triple("ppsspp.ini", "config", 262144), Triple("controls.ini", "controls", 65536))) {
            val bytes = request.getByteArray(key) ?: error("Missing initial PSP settings.")
            require(bytes.size <= limit)
            val destination = path(memory, "PSP/SYSTEM/$name")
            if (!present(destination)) create(destination, bytes) else attributes(destination)
        }
        checkpoint("profile-seeded")
        // Publish ownership last. An interrupted initialization remains unclaimed
        // and cannot be confused with a damaged previously usable profile.
        create(marker, owner(request))
        closed()
        return Bundle().apply { putString("status", "ready"); putString("memoryStick", memoryPath(request)) }
    }

    fun pointerBytes(): ByteArray {
        require(pointer.canonicalPath == pointer.path)
        val s = Os.lstat(pointer.path)
        require(OsConstants.S_ISREG(s.st_mode) && s.st_uid == uid && s.st_gid == uid &&
            s.st_nlink == 1L && s.st_size in 1..1024 && (s.st_mode and 4095) == 384 &&
            Os.getxattr(pointer.path, "security.selinux").contentEquals(internalLabel))
        val fd = Os.open(pointer.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW or OsConstants.O_NONBLOCK, 0)
        return FileInputStream(fd).use { input ->
            require(snapshot(Os.fstat(fd)) == snapshot(s))
            val out = ByteArrayOutputStream(); val buffer = ByteArray(1025)
            while (true) { live(); val n = input.read(buffer, 0, minOf(buffer.size, 1025 - out.size())); if (n < 0) break
                out.write(buffer, 0, n); require(out.size() <= 1024) }
            require(out.size().toLong() == s.st_size && snapshot(Os.fstat(fd)) == snapshot(s) && snapshot(Os.lstat(pointer.path)) == snapshot(s))
            out.toByteArray()
        }
    }
    fun selection(request: Bundle): Bundle {
        closed()
        val data = pointerBytes(); val selected = String(data, Charsets.UTF_8)
        require(selected == logical || selected == memoryPath(request)) { "PPSSPP selected a different memory stick. Recovery was kept." }
        return Bundle().apply { putString("selection", if (selected == logical) "native" else "profile"); putString("sha256", digest(data)) }
    }
    fun select(request: Bundle): Bundle {
        closed()
        val wanted = when (request.getString("selection")) {
            "native" -> logical; "profile" -> memoryPath(request)
            else -> error("Invalid PSP memory-stick selection.")
        }.toByteArray(Charsets.UTF_8)
        val before = request.getString("before")!!; require(HEX64.matches(before))
        val token = request.getString("token")!!; require(HEX32.matches(token))
        val current = pointerBytes(); val hash = digest(current); val after = digest(wanted)
        require(hash == before || hash == after) { "PPSSPP changed its memory-stick selection. Recovery was kept." }
        if (hash != after) {
            val stage = File(pointer.parentFile, ".broomm-psp-$token")
            if (present(stage)) {
                val s = Os.lstat(stage.path)
                require(OsConstants.S_ISREG(s.st_mode) && s.st_uid in setOf(0, uid) && s.st_gid in setOf(0, uid) &&
                    (s.st_mode and 4095) == 384 && s.st_nlink == 1L && s.st_size <= wanted.size)
                val partial = stage.readBytes()
                require(partial.size.toLong() == s.st_size && partial.contentEquals(wanted.copyOf(partial.size)) && snapshot(Os.lstat(stage.path)) == snapshot(s))
                closed(); live(); Os.remove(stage.path); flush(stage.parentFile!!)
            }
            run {
                val fd = Os.open(stage.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW, 384)
                FileOutputStream(fd).use { out -> out.write(wanted); out.flush(); Os.fsync(fd) }
                Os.chown(stage.path, uid, uid); Os.chmod(stage.path, 384); Os.setxattr(stage.path, "security.selinux", internalLabel, 0)
            }
            Os.chown(stage.path, uid, uid); Os.chmod(stage.path, 384); Os.setxattr(stage.path, "security.selinux", internalLabel, 0)
            syncFile(stage)
            flush(stage.parentFile!!)
            checkpoint("pointer-staged")
            closed(); live(); require(digest(pointerBytes()) == before)
            Os.rename(stage.path, pointer.path); flush(pointer.parentFile!!); checkpoint("pointer-published")
        }
        require(pointerBytes().contentEquals(wanted)); closed()
        return Bundle().apply { putString("sha256", after) }
    }

    private fun selector(request: Bundle, relative: String): Boolean {
        require(relative.toByteArray(Charsets.UTF_8).size <= 1024)
        val disc = request.getString("discId")!!; val version = request.getString("discVersion")!!
        require(Regex("[A-Z]{4}[0-9]{5}").matches(disc) && Regex("[0-9]{1,2}\\.[0-9]{2}").matches(version))
        val parts = relative.split('/')
        if (parts.size >= 4 && parts[0] == "PSP" && parts[1] in setOf("SAVEDATA", "GAME") &&
            Regex(Regex.escape(disc) + "[A-Za-z0-9_-]{0,80}").matches(parts[2])) return true
        return parts.size == 3 && parts[0] == "PSP" && parts[1] == "PPSSPP_STATE" &&
            Regex(Regex.escape("${disc}_${version}_") + "[0-9]{1,10}\\.(?:undo\\.)?(?:ppst|jpg)").matches(parts[2])
    }

    fun inventory(request: Bundle): Bundle {
        closed()
        val memory = verifyProfile(request); val selected = mutableListOf<File>()
        val excludedRaw = request.getString("excluded") ?: "[]"; require(excludedRaw.length <= 65536)
        val json = JSONArray(excludedRaw); require(json.length() <= 4096)
        val excluded = (0 until json.length()).map { json.getString(it).also { p -> require(selector(request, p)) } }.toSet()
        var total = 0L; var count = 0; var nodes = 0
        fun walk(folder: File, depth: Int) {
            require(depth <= 16 && ++nodes <= 16384); directory(folder)
            val names = folder.list() ?: error("PPSSPP saves could not be enumerated.")
            require(names.size <= 4096)
            for (name in names.sorted()) {
                live()
                val file = path(folder, name); val relative = file.path.removePrefix(memory.path + "/")
                if (folder == File(memory, "PSP/SAVEDATA") && !Regex(Regex.escape(request.getString("discId")!!) + "[A-Za-z0-9_-]{0,80}").matches(name)) continue
                if (folder == File(memory, "PSP/PPSSPP_STATE") && !selector(request, relative)) continue
                val s = Os.lstat(file.path)
                if (OsConstants.S_ISDIR(s.st_mode)) walk(file, depth + 1)
                else {
                    require(selector(request, relative))
                    if (relative in excluded) continue
                    require(++count <= 4096)
                    attributes(file); total += s.st_size
                    require(total <= 512L * 1024 * 1024) { "PSP progress exceeds its 512 MiB limit." }
                    selected.add(file)
                }
            }
        }
        walk(File(memory, "PSP/SAVEDATA"), 0); walk(File(memory, "PSP/PPSSPP_STATE"), 0)
        return page(request, memory, selected, MAX_FILE)
    }

    /** Private profile backup, never a game's cloud inventory. Includes undo,
     * console/settings and other writable data so removing the APK cannot erase
     * the only Broomm-owned copy. Only the verified profile root is traversed. */
    fun profileInventory(request: Bundle): Bundle {
        closed(); val memory = verifyProfile(request); val selected = mutableListOf<File>()
        var total = 0L; var count = 0; var nodes = 0
        fun walk(folder: File, depth: Int) {
            require(depth <= 24 && ++nodes <= 16384); directory(folder)
            val names = folder.list() ?: error("Private PSP data could not be enumerated.")
            require(names.size <= 8192)
            for (name in names.sorted()) {
                live(); val file = path(folder, name)
                if (OsConstants.S_ISDIR(Os.lstat(file.path).st_mode)) walk(file, depth + 1)
                else {
                    require(++count <= 8192)
                    attributes(file); val size = Os.lstat(file.path).st_size; require(size in 0..PROFILE_FILE.toLong()); total += size
                    require(total <= 2L * 1024 * 1024 * 1024) { "Private PSP backup exceeds its 2 GiB limit. Native data was kept." }
                    selected.add(file)
                }
            }
        }
        walk(memory, 0); closed()
        return page(request, memory, selected, PROFILE_FILE)
    }

    private fun page(request: Bundle, memory: File, selected: List<File>, limit: Int): Bundle {
        val paths = selected.associateBy { it.path.removePrefix(memory.path + "/") }.toSortedMap()
        val cursor = request.getString("cursor")
        require(cursor == null || paths.containsKey(cursor)) { "PSP inventory changed between pages. Nothing was inferred missing." }
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
        closed(); val relative = request.getString("path")!!; require(profileData || selector(request, relative))
        val file = path(verifyProfile(request), relative); val expected = request.getString("metadata")!!
        require(attributes(file) == expected)
        val fd = descriptor.fileDescriptor; val s = Os.fstat(fd)
        require(OsConstants.S_ISREG(s.st_mode) && s.st_uid == caller && s.st_nlink == 1L && s.st_size == 0L)
        ParcelFileDescriptor.AutoCloseOutputStream(descriptor).use { out ->
            val e = stream(file, if (profileData) PROFILE_FILE else MAX_FILE) { b, n -> out.write(b, 0, n) }
            require(e.getLong("bytes") == request.getLong("bytes") && e.getString("sha256") == request.getString("sha256") &&
                e.getString("metadata") == expected) { "PSP progress changed during capture. Recovery was kept." }
            out.flush(); Os.fsync(fd); require(Os.fstat(fd).st_size == e.getLong("bytes"))
        }
        closed(); return Bundle()
    }

    fun replace(request: Bundle, descriptor: ParcelFileDescriptor?, caller: Int, profileData: Boolean = false): Bundle {
        closed(); val relative = request.getString("path")!!; require(profileData || selector(request, relative))
        val limit = if (profileData) PROFILE_FILE else MAX_FILE
        val memory = verifyProfile(request); val file = path(memory, relative)
        val before = request.getString("before"); val after = request.getString("after")
        val desiredMode = request.getString("mode")?.also { require(profileData && Regex("6[0246]0").matches(it)) }?.toInt(8)
        val token = request.getString("token")!!; require(HEX32.matches(token))
        require(listOfNotNull(before, after).all { HEX64.matches(it) } && (after == null) == (descriptor == null))
        val stageDir = File(profile(request), "incoming")
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
        require(observed?.getString("sha256") == before) { "Native PSP progress changed before publication. Recovery was kept." }
        if (observed != null) require(observed.getString("metadata") == request.getString("metadata")) { "Native PSP file identity changed. Recovery was kept." }
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
                        require(a.copyOf(n).contentEquals(b.copyOf(n))) { "Private PSP incoming bytes changed. Recovery was kept." }
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
        require(sameEntry(if (present(file)) entry(file, limit) else null, observed)) { "PSP progress changed at publication. Recovery was kept." }
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
            Os.getxattr(file.path, "security.selinux").contentEquals(label)) { "PSP directory ownership or permissions changed." }
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
            Os.getxattr(file.path, "security.selinux").contentEquals(label)) { "PSP file ownership, permissions, links or label changed." }
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
    private fun verifyApk(apk: File) {
        require(apk.path.startsWith("/data/app/") && apk.canonicalPath == apk.path)
        val before = Os.lstat(apk.path)
        require(OsConstants.S_ISREG(before.st_mode) && before.st_size == 45448397L) { "Root PSP saves require the reviewed universal PPSSPP 1.20.4 APK. Existing data was kept." }
        val key = apk.path + ":" + snapshot(before)
        if (verifiedApk != key) {
            val hash = MessageDigest.getInstance("SHA-256")
            apk.inputStream().use { input -> val buffer = ByteArray(65536); var size = 0L
                while (true) { live(); val n = input.read(buffer); if (n < 0) break
                    size += n; require(size <= before.st_size); hash.update(buffer, 0, n) }
                require(size == before.st_size) }
            require(hash.digest().hex() == APK && snapshot(Os.lstat(apk.path)) == snapshot(before)) {
                "This PPSSPP build has not been verified for rooted saves. Its existing data was kept."
            }
            verifiedApk = key
        }
    }
    companion object {
        const val APK = "dd702a31270ecd68db37afee311d6efe08b1d4da9601d2750ce1a73bbd316c3f"
        const val MAX_FILE = 256 * 1024 * 1024
        const val PROFILE_FILE = 1024 * 1024 * 1024
        private val HEX32 = Regex("[a-f0-9]{32}"); private val HEX64 = Regex("[a-f0-9]{64}")
        private var verifiedApk: String? = null
        private fun ByteArray.hex() = joinToString("") { "%02x".format(it.toInt() and 255) }
        private fun digest(bytes: ByteArray) = MessageDigest.getInstance("SHA-256").digest(bytes).hex()
        private fun snapshot(s: StructStat) = "${s.st_dev}:${s.st_ino}:${s.st_uid}:${s.st_gid}:${s.st_mode}:${s.st_size}:${s.st_mtim}:${s.st_ctim}:${s.st_nlink}"
    }
}
