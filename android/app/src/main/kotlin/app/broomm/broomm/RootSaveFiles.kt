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
    private val writerClosed: () -> Unit = {},
    private val mediaGroup: Int? = null,
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
        require(OsConstants.S_ISREG(s.st_mode) && s.st_nlink == links && (s.st_mode and 4095) <= 511 &&
            s.st_uid == uid && (mediaGroup == null || s.st_gid == mediaGroup) &&
            Os.getxattr(file.path, "security.selinux").contentEquals(label)) { "Save ownership, links or security label changed. Files were kept." }
        return "${s.st_uid} ${s.st_gid} ${(s.st_mode and 511).toString(8)} ${String(label).trimEnd('\u0000')}"
    }
    fun bytes(file: File, max: Int): ByteArray {
        val fd = Os.open(file.path, OsConstants.O_RDONLY or OsConstants.O_NOFOLLOW, 0)
        return FileInputStream(fd).use { input ->
            val stat = Os.fstat(fd)
            require(OsConstants.S_ISREG(stat.st_mode) && stat.st_size in 0..max.toLong()) { "Root file exceeds its supported size." }
            val bytes = RootSaveTransfer.readExact(input, stat.st_size.toInt(), live)
            require(Os.fstat(fd).st_mtime == stat.st_mtime && Os.lstat(file.path).st_ino == stat.st_ino) {
                "Root file changed during inspection."
            }
            bytes
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
                Os.chown(stage.path, uid, mediaGroup ?: uid)
                if (mediaGroup != null) Os.chmod(stage.path, 1528) // 02770
                Os.setxattr(stage.path, "security.selinux", label, 0)
                flushDirectory(stage)
                require(!present(target))
                Os.rename(stage.path, target.path); flushDirectory(parent)
            }
            val s = Os.lstat(target.path)
            require(OsConstants.S_ISDIR(s.st_mode) &&
                (if (mediaGroup == null) (s.st_mode and 4095) <= 511
                    else (s.st_mode and 3072) == 1024 && s.st_gid == mediaGroup) &&
                s.st_uid == uid && Os.getxattr(target.path, "security.selinux").contentEquals(label))
            parent = target
        }
    }
    fun inventory(areas: List<Map<String, String>>): Map<String, BundleEntry> {
        require(areas.size in 1..2)
        if (areas.any { it.containsKey("operaStem") }) return operaInventory(areas)
        if (areas.any { it.containsKey("saturnStem") }) return saturnInventory(areas)
        if (areas.any { it.containsKey("flycastVmus") }) return flycastInventory(areas)
        val result = linkedMapOf<String, BundleEntry>()
        var total = 0L
        var base: String? = null
        for (area in areas) {
            val directory = area.getValue("path")
            val exact = area["exact"]
            val prefix = area["prefix"]
            val driver = area["driver"]
            val arcade = coreName == "fbneo" && driver != null
            require(if (arcade) area.keys == setOf("path", "driver") && Regex("[a-z0-9_]{1,64}").matches(driver)
                else driver == null && ((exact != null && area.keys == setOf("path", "exact")) ||
                    (prefix != null && area.keys == setOf("path", "prefix", "pattern"))))
            val ordinary = directory.endsWith("/saves")
            require(coreName != "opera" || !ordinary) { "Opera needs its concrete native NVRAM selector." }
            val probe = if (arcade) "$directory/fbneo/$driver.fs"
                else "$directory/${exact ?: (prefix + if (ordinary) ".srm" else ".state")}"
            managedPath(probe, saveOnly = true, core = coreName)
            val owner = directory.substringBefore("/saves").substringBefore("/states")
            require(base == null || base == owner); base = owner
            require(if (arcade) ordinary else if (exact != null) ordinary && exact.endsWith(".srm")
                else ordinary || Regex(".*/states/states-[a-f0-9]{16}-android").matches(directory))
            val folder = path(if (arcade) "$directory/fbneo" else directory)
            if (!present(folder)) continue
            val stat = Os.lstat(folder.path)
            require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == uid &&
                Os.getxattr(folder.path, "security.selinux").contentEquals(label))
            val names = folder.list() ?: error("Cannot inspect the managed save directory.")
            require(names.size <= 1024) { "Managed save directory exceeds its entry limit." }
            val selected = names.filter { if (arcade)
                Regex(Regex.escape(driver) + "\\.(?:fs|nv|hi|memcard)|shared\\.memcard").matches(it)
                else if (exact != null) it == exact else
                Regex(Regex.escape(prefix!!) + if (ordinary) "\\.(?:srm|rtc)" else
                    "\\.state(?:[0-9]{1,10}|\\.auto)?(?:\\.png)?").matches(it) }
            for (name in selected.sorted()) {
                live()
                val relative = "$directory/${if (arcade) "fbneo/" else ""}$name"
                managedPath(relative, saveOnly = true, core = coreName)
                require(!result.containsKey(relative) && result.size < 128) { "Too many rooted save files." }
                val file = path(relative)
                val metadata = metadata(file)
                val bytes = bytes(file, progressLimit(relative))
                total += bytes.size
                require(total <= (if (coreName == "flycast") 128L else 64L) * 1024 * 1024) { "Rooted progress exceeds its size limit." }
                result[relative] = BundleEntry(bytes.size.toLong(), digest(bytes), metadata)
            }
        }
        return result
    }
    data class BundleEntry(val bytes: Long, val sha256: String, val metadata: String)

    private fun flycastInventory(areas: List<Map<String, String>>): Map<String, BundleEntry> {
        require(coreName == "flycast")
        val ordinary = areas.single { it.containsKey("flycastVmus") }
        require(ordinary.keys == setOf("path", "flycastVmus") && ordinary["flycastVmus"] == "true")
        val directory = ordinary.getValue("path")
        managedPath("$directory/probe.A1.bin", saveOnly = true, core = coreName)
        val stateAreas = areas.filter { !it.containsKey("flycastVmus") }
        require(stateAreas.all { it.getValue("path").startsWith(directory.removeSuffix("/saves") + "/states/") })
        val result = if (stateAreas.isEmpty()) linkedMapOf() else inventory(stateAreas).toMutableMap()
        var total = result.values.sumOf { it.bytes }
        val folder = path(directory)
        if (!present(folder)) return result
        val stat = Os.lstat(folder.path)
        require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == uid &&
            Os.getxattr(folder.path, "security.selinux").contentEquals(label))
        val names = folder.list() ?: error("Cannot inspect Dreamcast VMUs")
        require(names.size <= 1024)
        val selected = names.filter { Regex("[^/]+\\.[A-D][12]\\.bin").matches(it) }
        require(selected.size <= 16) { "Dreamcast has more than eight native and eight legacy VMUs. Recovery was kept." }
        for (name in selected.sorted()) {
            live()
            val relative = "$directory/$name"
            managedPath(relative, saveOnly = true, core = coreName)
            val file = path(relative)
            val metadata = metadata(file)
            val data = bytes(file, 131072)
            require(data.size == 131072) { "Dreamcast VMU is incomplete. Recovery was kept." }
            total += data.size
            require(total <= 128L * 1024 * 1024 && result.size < 128 && !result.containsKey(relative))
            result[relative] = BundleEntry(data.size.toLong(), digest(data), metadata)
        }
        return result
    }

    /** Concrete transaction-bound Dreamcast resources, outside game save selectors. */
    fun flycastResourceLimit(relative: String, config: String): Int {
        require(coreName == "flycast")
        managedPath(config, core = coreName)
        val name = config.substringAfterLast('/')
        require(Regex("config-[a-f0-9]{32}\\.cfg").matches(name))
        val nonce = name.removePrefix("config-").removeSuffix(".cfg")
        val base = config.substringBeforeLast('/')
        if (relative == "$base/options-$nonce.opt") return MAX_BYTES
        require(relative.startsWith("$base/system-$nonce/dc/") && !relative.substringAfter("/dc/").contains('/'))
        return when (relative.substringAfterLast('/')) {
            "dc_boot.bin" -> 2097152
            "dc_nvmem.bin" -> 131072
            else -> {
                require(Regex("vmu_save_[A-D][12]\\.bin").matches(relative.substringAfterLast('/')))
                131072
            }
        }
    }

    fun flycastResources(config: String): Map<String, BundleEntry> {
        val nonce = config.substringAfterLast('/').removePrefix("config-").removeSuffix(".cfg")
        val base = config.substringBeforeLast('/')
        val candidates = listOf("$base/options-$nonce.opt", "$base/system-$nonce/dc/dc_boot.bin",
            "$base/system-$nonce/dc/dc_nvmem.bin") +
            ('A'..'D').flatMap { port -> (1..2).map { "$base/system-$nonce/dc/vmu_save_$port$it.bin" } }
        return candidates.mapNotNull { relative ->
            val limit = flycastResourceLimit(relative, config)
            val file = path(relative)
            if (!present(file)) null else {
                val metadata = metadata(file)
                val data = bytes(file, limit)
                require(relative.endsWith(".opt") || data.size == limit) { "Dreamcast resource is incomplete. Recovery was kept." }
                relative to BundleEntry(data.size.toLong(), digest(data), metadata)
            }
        }.toMap()
    }

    fun flycastResource(relative: String, config: String, before: String?, after: String?,
                        payload: ByteArray?, token: String, ensureClosed: () -> Unit) {
        val limit = flycastResourceLimit(relative, config)
        require(!relative.substringAfterLast('/').startsWith("vmu_save_")) { "Fallback VMUs are read-only recovery data." }
        require(if (after == null) before != null && payload == null && token.endsWith("-out")
            else before == null && payload != null && (relative.endsWith(".opt") || payload.size == limit) && token.endsWith("-in"))
        ensureClosed()
        if (after == null) recoverResourceLink(relative, before!!, token, limit, ensureClosed)
        publish(relative, before, after, payload, null, token, limit, beforeCommit = ensureClosed)
        if (after == null) {
            val folder = path(relative).parentFile!!
            val stage = File(folder, ".${relative.substringAfterLast('/')}.broomm-${token.removeSuffix("-out")}-in")
            if (present(stage)) {
                val stat = Os.lstat(stage.path)
                require(OsConstants.S_ISREG(stat.st_mode) && stat.st_nlink == 1L &&
                    stat.st_uid in setOf(0, uid) && hash(stage, limit) == before)
                live(); ensureClosed(); Os.remove(stage.path); flushDirectory(folder)
            }
            // Unknown core-created files stay in the owned session directory.
            // Never infer that an unrecognized file is disposable cache/progress.
            var directory = folder
            repeat(if (relative.endsWith(".opt")) 0 else 2) {
                if (present(directory)) {
                    val stat = Os.lstat(directory.path)
                    require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == uid &&
                        Os.getxattr(directory.path, "security.selinux").contentEquals(label))
                    if (directory.list()?.isEmpty() == true) {
                        live(); ensureClosed(); Os.remove(directory.path); flushDirectory(directory.parentFile!!)
                    }
                }
                directory = directory.parentFile!!
            }
        }
    }

    private fun operaInventory(areas: List<Map<String, String>>): Map<String, BundleEntry> {
        require(coreName == "opera")
        val ordinary = areas.single { it.containsKey("operaStem") }
        require(ordinary.keys == setOf("path", "operaStem"))
        val directory = ordinary.getValue("path")
        val stem = ordinary.getValue("operaStem")
        require(stem.isNotEmpty() && stem !in setOf(".", "..") && stem.none { it.code < 32 || it in "/\\" })
        managedPath("$directory/opera/per_game/$stem.0.srm", saveOnly = true, core = coreName)
        val other = areas.filter { it !== ordinary }
        require(other.all { it.getValue("path").startsWith(directory.removeSuffix("/saves") + "/states/") })
        val result = if (other.isEmpty()) linkedMapOf<String, BundleEntry>() else LinkedHashMap(inventory(other))
        var total = result.values.sumOf { it.bytes }
        val folders = listOf(
            directory to Regex("${Regex.escape(stem)}\\.srm|3DO\\.nvram"),
            "$directory/opera/per_game" to Regex("${Regex.escape(stem)}\\.[0-9]\\.srm"),
            "$directory/opera/shared" to Regex("nvram\\.[0-9]\\.srm"))
        for ((relative, pattern) in folders) {
            val folder = path(relative)
            if (!present(folder)) continue
            val stat = Os.lstat(folder.path)
            require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == uid &&
                Os.getxattr(folder.path, "security.selinux").contentEquals(label))
            val names = folder.list() ?: error("Cannot inspect Opera NVRAM directory.")
            require(names.size <= 1024)
            for (name in names.filter { pattern.matches(it) }.sorted()) {
                live()
                val target = "$relative/$name"
                managedPath(target, saveOnly = true, core = coreName)
                val file = path(target)
                val metadata = metadata(file)
                val bytes = bytes(file, progressLimit(target))
                require(bytes.size == 32768) { "Opera NVRAM is incomplete. Recovery was kept." }
                total += bytes.size
                require(total <= 64L * 1024 * 1024 && result.size < 128)
                result[target] = BundleEntry(bytes.size.toLong(), digest(bytes), metadata)
            }
        }
        return result
    }

    private fun saturnInventory(areas: List<Map<String, String>>): Map<String, BundleEntry> {
        require(coreName == "mednafen_saturn")
        val ordinary = areas.single { it.containsKey("saturnStem") }
        require(ordinary.keys == setOf("path", "saturnStem"))
        val directory = ordinary.getValue("path")
        val stem = ordinary.getValue("saturnStem")
        require(stem.isNotEmpty() && stem.length <= 200 && stem.none { it == '/' || it == '\\' || it.code < 32 })
        managedPath("$directory/$stem.srm", saveOnly = true, core = coreName)
        require(directory.endsWith("/saves"))
        val stateAreas = areas.filter { !it.containsKey("saturnStem") }
        require(stateAreas.all { it.getValue("path").startsWith(directory.removeSuffix("/saves") + "/states/") })
        val result = if (stateAreas.isEmpty()) linkedMapOf() else inventory(stateAreas).toMutableMap()
        var total = result.values.sumOf { it.bytes }
        val folder = path(directory)
        if (!present(folder)) return result
        val stat = Os.lstat(folder.path)
        require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == uid &&
            Os.getxattr(folder.path, "security.selinux").contentEquals(label))
        val names = folder.list() ?: error("Cannot inspect Saturn backup memory")
        require(names.size <= 1024)
        val accepted = Regex("(?:${Regex.escape(stem)}|mednafen_saturn_libretro_shared)\\.(?:srm|bkr|smpc|bcr|4mb\\.bcr)")
        for (name in names.filter { accepted.matches(it) }.sorted()) {
            live()
            val relative = "$directory/$name"
            managedPath(relative, saveOnly = true, core = coreName)
            val file = path(relative)
            val metadata = metadata(file)
            val data = bytes(file, progressLimit(relative))
            require(data.size == progressLimit(relative)) { "Saturn backup memory is incomplete. Recovery was kept." }
            total += data.size
            require(total <= 64L * 1024 * 1024 && result.size < 128 && !result.containsKey(relative))
            result[relative] = BundleEntry(data.size.toLong(), digest(data), metadata)
        }
        return result
    }

    /** Read-only option files from the selected emulator's known storage roots. */
    fun options(absolute: String, roots: List<File>): ByteArray? {
        require(coreName in setOf("opera", "mednafen_saturn", "flycast") && absolute.length <= 1024 && absolute.startsWith('/') &&
            absolute.none { it.code < 32 || it == '\\' } &&
            absolute.split('/').drop(1).none { it.isEmpty() || it == "." || it == ".." } &&
            (absolute.endsWith(".opt") || absolute.endsWith(".cfg"))) { "Invalid RetroArch option path." }
        require(roots.any { absolute.startsWith(it.path + "/") }) {
            "Keep core options inside RetroArch's config or application folder before Play."
        }
        val file = File(absolute)
        require(file.canonicalPath == file.absolutePath) { "Linked RetroArch option files are unsupported." }
        if (!present(file)) return null
        val stat = Os.lstat(file.path)
        require(OsConstants.S_ISREG(stat.st_mode) && stat.st_nlink == 1L)
        if (file.path.startsWith(root.path + "/")) metadata(file)
        return bytes(file, MAX_BYTES)
    }

    /** Selected immutable Opera BIOS/font, isolated from mutable NVRAM. */
    fun operaFirmware(relative: String, config: String, before: String?, after: String?,
                      payload: ByteArray?, token: String, ensureClosed: () -> Unit) {
        require(coreName == "opera")
        managedPath(config)
        val configName = config.substringAfterLast('/')
        require(Regex("config-[a-f0-9]{32}\\.cfg").matches(configName))
        val nonce = configName.removePrefix("config-").removeSuffix(".cfg")
        val name = relative.substringAfterLast('/')
        val size = when (name) {
            "opera-boot.bin" -> 131072
            "3do_arcade_saot.bin" -> 524288
            "panafz1-kanji.bin" -> 933636
            "panafz1.bin", "panafz1j.bin", "panafz1j-norsa.bin", "panafz10.bin",
            "panafz10-norsa.bin", "panafz10e-anvil.bin", "panafz10e-anvil-norsa.bin",
            "goldstar.bin", "sanyotry.bin", "panafz1j-kanji.bin", "panafz10ja-anvil-kanji.bin" -> 1048576
            else -> error("Unsupported Opera firmware filename.")
        }
        require(relative == config.substringBeforeLast('/') + "/system-$nonce/$name")
        require(if (after == null) before != null && payload == null && token.endsWith("-out")
            else before == null && payload != null && payload.size == size && token.endsWith("-in"))
        ensureClosed()
        if (after == null) recoverResourceLink(relative, before!!, token, size, ensureClosed)
        publish(relative, before, after, payload, null, token, size, beforeCommit = ensureClosed)
        if (after == null) {
            val folder = path(relative).parentFile!!
            val stage = File(folder, ".$name.broomm-${token.removeSuffix("-out")}-in")
            if (present(stage)) {
                val stat = Os.lstat(stage.path)
                require(OsConstants.S_ISREG(stat.st_mode) && stat.st_nlink == 1L &&
                    stat.st_uid in setOf(0, uid) && before != null && hash(stage, size) == before) {
                    "Interrupted Opera firmware staging changed. Recovery was kept."
                }
                live(); ensureClosed(); Os.remove(stage.path); flushDirectory(folder)
            }
            if (present(folder)) {
                val stat = Os.lstat(folder.path)
                require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == uid &&
                    Os.getxattr(folder.path, "security.selinux").contentEquals(label))
                if (folder.list()?.isEmpty() == true) {
                    live(); ensureClosed(); Os.remove(folder.path); flushDirectory(folder.parentFile!!)
                }
            }
        }
    }

    /** Selected immutable Saturn BIOS/font, isolated from mutable NVRAM. */
    fun saturnFirmware(relative: String, config: String, before: String?, after: String?,
                      payload: ByteArray?, token: String, ensureClosed: () -> Unit) {
        require(coreName == "mednafen_saturn")
        managedPath(config)
        val configName = config.substringAfterLast('/')
        require(Regex("config-[a-f0-9]{32}\\.cfg").matches(configName))
        val nonce = configName.removePrefix("config-").removeSuffix(".cfg")
        val name = relative.substringAfterLast('/')
        val size = when (name) {
            "sega_101.bin", "mpr-17933.bin" -> 524288
            "mpr-18811-mx.ic1", "mpr-19367-mx.ic1" -> 2097152
            else -> error("Unsupported Saturn firmware filename.")
        }
        require(relative == config.substringBeforeLast('/') + "/system-$nonce/$name")
        require(if (after == null) before != null && payload == null && token.endsWith("-out")
            else before == null && payload != null && payload.size == size && token.endsWith("-in"))
        ensureClosed()
        if (after == null) recoverResourceLink(relative, before!!, token, size, ensureClosed)
        publish(relative, before, after, payload, null, token, size, beforeCommit = ensureClosed)
        if (after == null) {
            val folder = path(relative).parentFile!!
            val stage = File(folder, ".$name.broomm-${token.removeSuffix("-out")}-in")
            if (present(stage)) {
                val stat = Os.lstat(stage.path)
                require(OsConstants.S_ISREG(stat.st_mode) && stat.st_nlink == 1L &&
                    stat.st_uid in setOf(0, uid) && before != null && hash(stage, size) == before) {
                    "Interrupted Saturn firmware staging changed. Recovery was kept."
                }
                live(); ensureClosed(); Os.remove(stage.path); flushDirectory(folder)
            }
            if (present(folder)) {
                val stat = Os.lstat(folder.path)
                require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == uid &&
                    Os.getxattr(folder.path, "security.selinux").contentEquals(label))
                if (folder.list()?.isEmpty() == true) {
                    live(); ensureClosed(); Os.remove(folder.path); flushDirectory(folder.parentFile!!)
                }
            }
        }
    }

    fun replace(relative: String, before: String?, after: String?, payload: ByteArray?, wantedMetadata: String?, token: String, stateGroup: String? = null) {
        require(coreName != "flycast" || !relative.contains("/saves/") || payload == null || payload.size == 131072) { "Dreamcast VMU is incomplete. Recovery was kept." }
        require(coreName != "mednafen_saturn" || !relative.contains("/saves/") || payload == null || payload.size == progressLimit(relative)) { "Saturn backup memory is incomplete. Recovery was kept." }
        require(coreName != "opera" || !relative.contains("/saves/") || payload == null || payload.size == 32768) {
            "Opera NVRAM must contain exactly 32768 bytes. Recovery was kept."
        }
        publish(relative, before, after, payload, wantedMetadata, token, progressLimit(relative),
            sessionConfiguration = relative.endsWith(".cfg"), stateGroup = stateGroup)
    }

    /** The standalone adapter supplies an already resolved exact native filename. */
    fun replaceStandalone(relative: String, before: String?, after: String?, payload: ByteArray?,
                           metadata: String?, token: String, limit: Int, revalidate: () -> Unit) {
        require(mediaGroup != null && (metadata == null || metadata.split(' ').getOrNull(1) == mediaGroup.toString()))
        publish(relative, before, after, payload, metadata, token, limit, beforeCommit = revalidate)
    }

    /** One concrete immutable Lynx BIOS, separate from save/config allowlists. */
    fun lynxFirmware(relative: String, config: String, before: String?, after: String?,
                     payload: ByteArray?, token: String, ensureClosed: () -> Unit) {
        require(coreName == "mednafen_lynx")
        managedPath(config)
        val name = config.substringAfterLast('/')
        require(Regex("config-[a-f0-9]{32}\\.cfg").matches(name))
        val nonce = name.removePrefix("config-").removeSuffix(".cfg")
        require(relative == config.substringBeforeLast('/') + "/system-$nonce/lynxboot.img")
        require(if (after == null) before != null && payload == null && token.endsWith("-out")
            else before == null && payload != null && token.endsWith("-in"))
        require(payload == null || payload.size == 512) { "The Lynx BIOS must contain exactly 512 bytes." }
        ensureClosed()
        if (after == null) recoverResourceLink(relative, before!!, token, 512, ensureClosed)
        publish(relative, before, after, payload, null, token, 512, beforeCommit = ensureClosed)
        if (after == null) {
            val folder = path(relative).parentFile!!
            val inStage = File(folder, ".lynxboot.img.broomm-${token.removeSuffix("-out")}-in")
            if (present(inStage)) {
                val stat = Os.lstat(inStage.path)
                require(OsConstants.S_ISREG(stat.st_mode) && stat.st_nlink == 1L &&
                    stat.st_uid in setOf(0, uid) && before != null && hash(inStage, 512) == before) {
                    "Interrupted Lynx BIOS staging changed. Recovery was kept."
                }
                live(); ensureClosed(); Os.remove(inStage.path); flushDirectory(folder)
            }
            if (present(folder)) {
                val stat = Os.lstat(folder.path)
                require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == uid &&
                    Os.getxattr(folder.path, "security.selinux").contentEquals(label))
                if (folder.list()?.isEmpty() == true) {
                    live(); ensureClosed(); Os.remove(folder.path); flushDirectory(folder.parentFile!!)
                }
            }
        }
    }

    /** An interrupted exclusive install can leave precisely these two names
     * linked. Verify the journal's incoming link before an outgoing cleanup;
     * never relax ordinary file metadata or adopt a foreign extra link. */
    private fun recoverResourceLink(relative: String, expected: String, token: String, limit: Int, ensureClosed: () -> Unit) {
        require(Regex("[a-f0-9]{32}-out").matches(token) && Regex("[a-f0-9]{64}").matches(expected))
        val file = path(relative)
        val stage = File(file.parentFile, ".${file.name}.broomm-${token.removeSuffix("-out")}-in")
        if (!present(file) || !present(stage)) return
        val a = Os.lstat(file.path); val b = Os.lstat(stage.path)
        if (a.st_ino != b.st_ino || a.st_dev != b.st_dev) return
        require(a.st_nlink == 2L && b.st_nlink == 2L && metadata(file, 2) == metadata(stage, 2) && hash(file, limit) == expected) {
            "Interrupted resource publication changed. Recovery was kept."
        }
        live(); ensureClosed()
        require(Os.lstat(stage.path).st_ino == a.st_ino && Os.lstat(file.path).st_nlink == 2L)
        Os.remove(stage.path); flushDirectory(file.parentFile!!)
    }

    private fun publish(relative: String, before: String?, after: String?, payload: ByteArray?,
                        wantedMetadata: String?, token: String, limit: Int,
                        sessionConfiguration: Boolean = false, stateGroup: String? = null, beforeCommit: () -> Unit = {}) {
        live(); writerClosed()
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
                live(); writerClosed(); Os.remove(stage.path); flushDirectory(file.parentFile!!)
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
            live(); writerClosed(); beforeCommit(); require(current() == before); Os.remove(file.path); flushDirectory(file.parentFile!!); return
        }
        parents(relative, token)
        if (sessionConfiguration) {
            parents(relative.substringBeforeLast('/') + "/saves/reserved.srm", token)
            require(stateGroup == null || Regex("states-[a-f0-9]{16}-android").matches(stateGroup))
            parents(relative.substringBeforeLast('/') + "/states/" +
                (stateGroup?.let { "$it/" } ?: "") + "reserved.state", token)
        }
        val mode = wantedMetadata ?: if (present(file)) metadata(file) else "$uid ${mediaGroup ?: uid} 600 ${String(label).trimEnd('\u0000')}"
        if (present(stage)) {
            val s = Os.lstat(stage.path)
            require(OsConstants.S_ISREG(s.st_mode) && s.st_nlink == 1L && s.st_uid in setOf(0, uid))
            // This is a private, journal-owned stage, never the public save.
            live(); writerClosed(); Os.remove(stage.path)
        }
        run {
            val fd = Os.open(stage.path, OsConstants.O_WRONLY or OsConstants.O_CREAT or OsConstants.O_EXCL or OsConstants.O_NOFOLLOW, 384)
            FileOutputStream(fd).use { out ->
                out.write(payload!!); out.flush(); checkpoint("staged")
                attributes(stage, mode); Os.fsync(fd)
            }
        }
        require(hash(stage, limit) == after && metadata(stage) == mode)
        live(); writerClosed(); beforeCommit(); require(current() == before)
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
        live(); writerClosed()
        val parts = romPath(relative, coreName)
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
        checkpoint("rom-staged")
        live(); writerClosed()
        Os.link(stage.path, target.path)
        Os.remove(stage.path)
        flushDirectory(directory)
        require(metadata(target) == mode)
        return target
    }

    fun removeRom(relative: String, expected: String) {
        live(); writerClosed()
        romPath(relative, coreName)
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
        for (entry in entries) { live(); writerClosed(); Os.remove(entry.path) }
        flushDirectory(directory)
        live(); writerClosed()
        Os.remove(directory.path)
        flushDirectory(directory.parentFile!!)
    }

    private fun romLimit(name: String): Long =
        (if (coreName == "flycast" && name.endsWith(".chd", true)) 2048L
            else if (coreName == "mednafen_saturn" && name.endsWith(".chd", true)) 1024L
            else if (coreName == "opera" && name.substringAfterLast('.').lowercase() in setOf("chd", "iso", "bin")) 1024L
            else if (coreName == "fbneo" && name.endsWith(".zip", true)) 128L
            else if (coreName == "mupen64plus_next" && name.substringAfterLast('.').lowercase() in setOf("z64", "v64", "n64")) 64L else 32L) * 1024 * 1024

    companion object {
        const val MAX_BYTES = 262144
        private const val MAX_CORE_BYTES = 96 * 1024 * 1024
        const val MAX_STATE_BYTES = 16 * 1024 * 1024
        fun corePath(core: String): String {
            require(core in setOf("mgba", "snes9x", "gambatte", "stella", "mednafen_pce_fast", "genesis_plus_gx", "picodrive", "mupen64plus_next", "mesen", "virtualjaguar", "mednafen_lynx", "fbneo", "opera", "mednafen_saturn", "flycast"))
            return "cores/${if (core == "mupen64plus_next") "mupen64plus_next_gles3" else core}_libretro_android.so"
        }
        fun limit(path: String, core: String = "mgba"): Int = when {
            core == "flycast" && path.contains("/saves/") -> 131072
            core == "flycast" && path.contains("/states/") -> 64 * 1024 * 1024
            core == "mednafen_saturn" && path.contains("/saves/") -> when {
                path.endsWith(".smpc") -> 12
                path.endsWith(".4mb.bcr") -> 4 * 1024 * 1024
                path.endsWith(".bcr") -> 512 * 1024
                else -> 32768
            }
            core == "opera" && path.contains("/saves/") -> 32768
            path.contains("/states/") -> if (core == "mupen64plus_next") 32 * 1024 * 1024 else MAX_STATE_BYTES
            core == "mupen64plus_next" && path.endsWith(".srm") -> 296960
            else -> MAX_BYTES
        }
        fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it.toInt() and 255) }
        fun managedPath(path: String, saveOnly: Boolean = false, core: String = "mgba") {
            val save = if (core == "flycast") "saves/[^/]+\\.[A-D][12]\\.bin"
                else if (core == "fbneo") "saves/fbneo/(?:[a-z0-9_]{1,64}\\.(?:fs|nv|hi|memcard)|shared\\.memcard)"
                else if (core == "opera") "saves/(?:opera/per_game/[^/]+\\.[0-9]\\.srm|opera/shared/nvram\\.[0-9]\\.srm|[^/]+\\.srm|3DO\\.nvram)"
                else if (core == "mednafen_saturn") "saves/[^/]+\\.(?:srm|bkr|smpc|bcr|4mb\\.bcr)"
                else "saves/[^/]+\\.(?:srm|rtc)"
            val state = "states/states-[a-f0-9]{16}-android/[^/]+\\.state(?:[0-9]{1,10}|\\.auto)?(?:\\.png)?"
            val suffix = if (saveOnly) "(?:$save|$state)" else "(?:$save|$state|config-[a-f0-9]{32}\\.cfg)"
            require(path.length <= 512 && path.none { it.code < 32 || it == '\\' } &&
                path.split('/').none { it == "." || it == ".." } &&
                Regex("files/Broomm/[a-f0-9]{32}/[a-zA-Z0-9_-]{1,128}/$suffix").matches(path)) { "Root path is outside the selected managed RetroArch files." }
        }

        fun romPath(path: String, core: String = "mgba"): List<String> {
            val extensions = if (core in setOf("mednafen_saturn", "flycast")) "chd" else if (core == "opera") "chd|iso|bin"
                else "gba|sfc|smc|gb|gbc|dmg|a26|bin|pce|md|gen|smd|sms|sg|gg|32x|z64|v64|n64|nes|unf|unif|j64|jag|rom|abs|cof|prg|lnx|lyx|bll|o|zip"
            require(path.length <= 512 && path.none { it.code < 32 || it == '\\' } &&
                Regex("files/Broomm/[a-f0-9]{32}/[1-9][0-9]*/rom-[a-f0-9]{32}/[^/]+(?i:\\.(?:$extensions))")
                    .matches(path)) { "ROM path is outside the rooted RetroArch session" }
            return path.split('/').drop(2)
        }
    }
}
