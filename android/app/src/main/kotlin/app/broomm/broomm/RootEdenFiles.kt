package app.broomm.broomm

import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.system.Os
import android.system.OsConstants
import android.system.StructStat
import java.io.File

internal const val EDEN_PACKAGE = "dev.eden.eden_emulator"
internal const val EDEN_VERSION = "1f6734c"
internal const val EDEN_SIGNER = "7fca26483b2d1b3dc3e6d9bb836e2fee18f09dc644353befd2fce8606bd2a40a"
private const val EDEN_SAVE_BYTES = 64 * 1024 * 1024

/** The reviewed Eden build's default NAND and one initialized console account. */
internal class RootEdenFiles(identity: Map<String, Any>, private val live: () -> Unit) {
    private val uid = identity.getValue("uid") as Int
    private val internal = File(identity.getValue("dataDir") as String).canonicalFile
    private val internalLabel = Os.getxattr(internal.path, "security.selinux")
    private val label = String(internalLabel).replace("app_data_file:", "media_rw_data_file:").toByteArray()
    private val root = File("/data/media/0/Android/data/$EDEN_PACKAGE")
    private val logical = File("/storage/emulated/0/Android/data/$EDEN_PACKAGE")
    private val first = Os.lstat(root.path)
    private val files = RootSaveFiles(root, uid, label, live, writerClosed = ::closed, mediaGroup = 1078)

    init {
        require(identity["package"] == EDEN_PACKAGE && identity["user"] == 0 &&
            identity["version"] == EDEN_VERSION && identity["signer"] == EDEN_SIGNER)
        verifyMount()
    }

    private fun closed() = requireNoEmulatorProcess(uid, "Eden", live)

    private fun directory(file: File, stat: StructStat = Os.lstat(file.path)) {
        require(OsConstants.S_ISDIR(stat.st_mode) && stat.st_uid == uid && stat.st_gid == 1078 &&
            stat.st_dev == first.st_dev && (stat.st_mode and 4095) == 1528 &&
            Os.getxattr(file.path, "security.selinux").contentEquals(label)) {
            "Eden storage ownership or security label changed. Recovery was kept."
        }
    }

    private fun verifyMount() {
        live()
        for (path in listOf(root, logical)) {
            require(path.canonicalPath == path.path)
            val now = Os.lstat(path.path)
            directory(path, now)
            require(now.st_ino == first.st_ino) { "Eden’s storage mount changed. Recovery was kept." }
        }
    }

    private fun path(relative: String): File {
        verifyMount()
        require(relative.length in 1..2048 && relative.split('/').all { it.length in 1..200 && ':' !in it && '\u007f' !in it })
        val file = files.path(relative)
        var parent = file.parentFile!!
        while (parent != root) {
            if (files.present(parent)) directory(parent)
            parent = parent.parentFile!!
        }
        return file
    }

    private fun entry(relative: String, limit: Int): ByteArray {
        val file = path(relative)
        val metadata = files.metadata(file)
        val result = files.bytes(file, limit)
        require(files.metadata(file) == metadata) { "Eden’s file changed during access." }
        return result
    }

    private fun account(): ByteArray {
        val profile = entry("files/nand/system/save/8000000000000010/su/avators/profiles.dat", 0x650)
        require(profile.size == 0x650) { "Eden’s console account file is incomplete." }
        val active = (0..7).mapNotNull {
            val start = 0x10 + it * 0xc8
            val id = profile.copyOfRange(start, start + 16)
            if (id.all { b -> b == 0.toByte() }) null else {
                require(id.contentEquals(profile.copyOfRange(start + 16, start + 32))) {
                    "Eden’s console account identity is inconsistent."
                }
                id
            }
        }
        require(active.size == 1) { "Use one active console account in Eden. Its existing accounts were kept." }
        return active.single()
    }

    private fun verifySettings() {
        var section = ""
        val settings = mutableMapOf<String, String>()
        for (line in entry("files/config/config.ini", 256 * 1024).decodeToString(throwOnInvalidSequence = true).lineSequence()) {
            val text = line.trim()
            if (text.startsWith('[') && text.endsWith(']')) section = text.substring(1, text.length - 1)
            if (section != "Data%20Storage" || '=' !in text) continue
            val key = text.substringBefore('=').trim()
            if (key !in setOf("nand_directory", "save_directory")) continue
            require(settings.put(key, text.substringAfter('=').trim().removeSurrounding("\"")) == null) {
                "Eden has conflicting save-folder settings."
            }
        }
        require(settings["nand_directory"] == "${logical.path}/files/nand" &&
            settings["save_directory"] == "") {
            "Use Eden’s default NAND and save-data folders for rooted saves."
        }
    }

    fun report(): Bundle {
        closed()
        verifySettings()
        account()
        closed()
        return Bundle().apply {
            putString("label", String(internalLabel).trimEnd('\u0000'))
            putString("externalLabel", String(label).trimEnd('\u0000'))
            putString("externalGid", "1078")
            putString("externalDevice", first.st_dev.toString())
            putString("externalInode", first.st_ino.toString())
        }
    }

    private fun headerKey(): ByteArray {
        require(files.present(path("files/keys/prod.keys"))) { "Import your prod.keys in Eden before playing." }
        val text = entry("files/keys/prod.keys", 256 * 1024).decodeToString(throwOnInvalidSequence = true)
        val values = Regex("^\\s*header_key\\s*=\\s*([a-fA-F0-9]{64})\\s*$", RegexOption.MULTILINE)
            .findAll(text).map { it.groupValues[1] }.take(2).toList()
        require(values.size == 1) { "Eden’s prod.keys does not have one valid header_key." }
        return ByteArray(32) { values.single().substring(it * 2, it * 2 + 2).toInt(16).toByte() }
    }

    private val registered = "files/nand/system/Contents/registered"
    private val keyPaths = mapOf("prod_keys" to "files/keys/prod.keys", "title_keys" to "files/keys/title.keys")

    private fun firmwarePresent(): Boolean {
        val folder = path(registered)
        if (!files.present(folder)) return false
        directory(folder)
        val names = folder.list() ?: error("Eden’s firmware directory could not be read.")
        require(names.size <= 4096)
        return names.any { Regex("[a-fA-F0-9]{32}(?:\\.cnmt)?\\.nca").matches(it) }
    }

    fun firmwareStatus(): Bundle = report().apply {
        val missing = mutableListOf<String>()
        for ((resource, relative) in keyPaths) {
            val target = path(relative)
            if (!files.present(target) || Os.lstat(target.path).st_nlink == 2L)
                missing.add(resource)
            else files.existing(relative)
        }
        if (!firmwarePresent()) missing.add("switch_firmware")
        closed()
        putString("missing", if (missing.any { it != "title_keys" }) missing.joinToString(",") else "")
    }

    private fun provision(request: Bundle, caller: Int): Bundle {
        val resource = request.getString("path")!!
        val after = request.getString("after")!!
        require(Regex("[a-f0-9]{64}").matches(after))
        val token = after.take(32) + "-in"
        val source = request.getParcelable<ParcelFileDescriptor>("transfer")!!
        if (resource == "switch_firmware") {
            if (!firmwarePresent()) {
                closed()
                files.parents(registered, token)
                val target = path(registered)
                fun verifyEmpty() {
                    live(); closed(); verifySettings(); path(registered)
                    if (files.present(target)) {
                        directory(target)
                        require(target.list()?.isEmpty() == true) { "Eden already has files in its firmware folder. They were kept." }
                    }
                }
                installEdenFirmware(target, source, caller, after, uid, label, live, ::verifyEmpty)
            }
            require(firmwarePresent()) { "Eden firmware installation was not confirmed." }
        } else {
            val relative = keyPaths[resource] ?: error("Invalid Switch resource.")
            val target = path(relative)
            if (!files.present(target) || Os.lstat(target.path).st_nlink == 2L) {
                val bytes = RootSaveTransfer.read(source, caller, 256 * 1024, live)
                files.replaceStandalone(relative, null, after, bytes, null, token, 256 * 1024) {
                    closed(); verifySettings(); path(relative)
                }
            }
            if (resource == "prod_keys") headerKey().fill(0) else files.existing(relative)
        }
        closed()
        return Bundle()
    }

    fun setup(): Bundle {
        val binding = report()
        headerKey().fill(0)
        require(firmwarePresent()) { "Install Switch firmware from RomM or inside Eden before setup." }
        closed()
        return binding
    }

    private fun scope(title: String): Pair<String, String> {
        require(Regex("[a-f0-9]{16}").matches(title)) { "Invalid Switch title identity." }
        val id = title.uppercase()
        val bytes = account()
        val user = bytes.joinToString("") { "%02x".format(it.toInt() and 255) }
        val legacy = bytes.reversed().joinToString("") { "%02X".format(it.toInt() and 255) }
        val base = "files/nand/user/save"
        val futureUser = "$base/account/$user/$id/0"
        val futureDevice = "$base/device/$id/0"
        fun exists(relative: String): Boolean = files.present(path(relative)).also {
            if (it) directory(path(relative))
        }
        return (if (exists(futureUser)) futureUser else "$base/0000000000000000/$legacy/$id") to
            (if (exists(futureDevice)) futureDevice else "$base/0000000000000000/${"0".repeat(32)}/$id")
    }

    private fun row(relative: String, bytes: ByteArray): Bundle = Bundle().apply {
        putLong("bytes", bytes.size.toLong())
        putString("sha256", RootSaveFiles.digest(bytes))
        putString("metadata", files.metadata(path(relative)))
    }

    private fun inventory(scope: Pair<String, String>): Bundle {
        val result = Bundle()
        var total = 0L
        var visited = 0
        var pathBytes = 0
        fun walk(relative: String, depth: Int) {
            require(depth <= 12 && ++visited <= 256) { "Eden’s save folder exceeds the inspection limits." }
            val folder = path(relative)
            if (!files.present(folder)) return
            directory(folder)
            val names = folder.list() ?: error("Cannot inspect Eden’s save directory.")
            for (name in names.sorted()) {
                live()
                if (Regex("(?:\\..+\\.broomm-|\\.broomm-dir-)[a-f0-9]{32}-(?:in|out)").matches(name)) continue
                val child = "$relative/$name"
                val stat = Os.lstat(path(child).path)
                if (OsConstants.S_ISDIR(stat.st_mode)) walk(child, depth + 1) else {
                    require(++visited <= 256 && OsConstants.S_ISREG(stat.st_mode))
                    val bytes = entry(child, EDEN_SAVE_BYTES)
                    total += bytes.size
                    pathBytes += child.toByteArray().size
                    require(total <= 512L * 1024 * 1024 && pathBytes <= 48 * 1024) {
                        "Eden’s save inventory exceeds the supported size."
                    }
                    result.putBundle(child, row(child, bytes))
                }
            }
        }
        walk(scope.first, 0)
        walk(scope.second, 0)
        return result
    }

    fun operation(request: Bundle, caller: Int): Bundle {
        val binding = report()
        require(binding.keySet().all { binding.getString(it) == request.getString(it) }) {
            "Eden’s installation or save storage changed. Recovery was kept."
        }
        val action = request.getString("operation")
        if (action == "edenprovision") return provision(request, caller)
        if (action == "edenkey") return Bundle().apply { putByteArray("headerKey", headerKey()); closed() }
        val title = request.getString("title")!!
        val scope = scope(title)
        if (action == "edenscope") return Bundle().apply {
            putString("accountPath", scope.first)
            putString("devicePath", scope.second)
            closed()
        }
        require(scope.first == request.getString("accountPath") && scope.second == request.getString("devicePath")) {
            "Eden’s console account or save layout changed. Recovery was kept."
        }
        if (action == "edencheck") return Bundle()
        if (action == "edenlist") return Bundle().apply { putBundle("files", inventory(scope)); closed() }
        val relative = request.getString("path")!!
        require(relative.startsWith("${scope.first}/") || relative.startsWith("${scope.second}/")) {
            "Eden save is outside the selected title."
        }
        path(relative)
        if (action == "edenread") {
            val bytes = entry(relative, EDEN_SAVE_BYTES)
            val observed = row(relative, bytes)
            require(observed.getLong("bytes") == request.getLong("bytes") &&
                observed.getString("sha256") == request.getString("sha256") &&
                observed.getString("metadata") == request.getString("metadata")) { "Eden progress changed during capture." }
            closed()
            RootSaveTransfer.write(request.getParcelable<ParcelFileDescriptor>("transfer")!!, caller, bytes, live)
        } else {
            require(action == "edenreplace")
            val bytes = request.getParcelable<ParcelFileDescriptor>("transfer")?.let {
                RootSaveTransfer.read(it, caller, EDEN_SAVE_BYTES, live)
            }
            files.replaceStandalone(relative, request.getString("before"), request.getString("after"),
                bytes, request.getString("metadata"), request.getString("token")!!, EDEN_SAVE_BYTES) {
                verifyMount()
                verifySettings()
                require(scope(title) == scope)
                path(relative)
            }
        }
        verifyMount()
        closed()
        return Bundle()
    }
}
