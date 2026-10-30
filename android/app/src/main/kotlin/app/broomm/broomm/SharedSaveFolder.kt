package app.broomm.broomm

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract
import android.provider.DocumentsContract.Document
import org.json.JSONArray
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest
import java.util.concurrent.atomic.AtomicReference
import java.util.concurrent.atomic.AtomicBoolean

/** Narrow SAF mechanisms. Snapshot ownership, title selection, profile swapping
 * and recovery are Dart workflows. Only the standard shared-storage provider is
 * admitted; a user grant cannot bypass another app's Android/data sandbox. */
class SharedSaveFolder(private val activity: Activity) {
    private val picker = 6205
    private var pending: MethodChannel.Result? = null
    private var pickingEmulator: String? = null
    private var pickingPackage: String? = null
    private val running = AtomicReference<Operation?>()
    private val closed = AtomicBoolean(false)
    private val resolver get() = activity.contentResolver
    private val main = Handler(Looper.getMainLooper())
    private val warning = "Choose the shared citra-emu folder (Internal storage/citra-emu). MMJ must use shared storage; its private Android/data or Storage Access folder is unsupported. No saves were changed."
    private data class Entry(val id: String, val name: String, val mime: String, val size: Long, val modified: Long) {
        val directory get() = mime == Document.MIME_TYPE_DIR
    }
    private class Operation {
        val signal = CancellationSignal()
        val descriptor = AtomicReference<ParcelFileDescriptor?>()
        fun check() = signal.throwIfCanceled()
        fun cancel() { signal.cancel(); try { descriptor.get()?.close() } catch (_: Exception) {} }
    }
    fun pick(result: MethodChannel.Result, emulator: String? = null, pkg: String? = null) {
        check(pending == null) { "A save-folder picker is already open" }
        pending = result
        pickingEmulator = emulator; pickingPackage = pkg
        try {
            activity.startActivityForResult(Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or Intent.FLAG_GRANT_PREFIX_URI_PERMISSION)
            }, picker)
        } catch (e: Exception) { pending = null; throw e }
    }
    fun activityResult(request: Int, code: Int, data: Intent?): Boolean {
        if (request != picker) return false
        val result = pending ?: return true
        pending = null
        if (code != Activity.RESULT_OK || data?.data == null) { result.success(null); return true }
        try {
            val uri = tree(data.data.toString(), pickingEmulator, pickingPackage)
            val flags = data.flags and (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)
            require(flags == (Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION)) { warning }
            resolver.takePersistableUriPermission(uri, flags)
            result.success(uri.toString())
        } catch (e: Exception) { result.error("save-folder", e.message ?: warning, null) }
        finally { pickingEmulator = null; pickingPackage = null }
        return true
    }
    fun close() {
        closed.set(true)
        running.get()?.cancel()
        pending?.error("mmj-folder", "Folder selection was interrupted. Select the shared folder again.", null)
        pending = null
    }
    fun busy(): Boolean = SharedDocumentLock.busy(File(activity.filesDir, "android"))
    private fun tree(value: String, emulator: String? = null, pkg: String? = null): Uri {
        val uri = Uri.parse(value)
        require(value.length < 4096 && '\u0000' !in value && uri.scheme == "content" &&
            uri.query == null && uri.fragment == null && uri.pathSegments.size == 2 && uri.pathSegments[0] == "tree") { "Select an emulator data folder" }
        if (emulator == null) {
            require(uri.authority == "com.android.externalstorage.documents" && Regex("[A-Za-z0-9_-]+:citra-emu").matches(uri.pathSegments[1])) { warning }
        } else {
            val packages = mapOf("ppsspp" to setOf("org.ppsspp.ppsspp", "org.ppsspp.ppssppgold"), "melonds" to setOf("me.magnum.melonds"),
                "azahar" to setOf("org.azahar_emu.azahar"), "citra-mmj" to setOf("org.citra.emu", "com.antutu.ABenchMark"),
                "dolphin" to setOf("org.dolphinemu.dolphinemu"), "eden" to setOf("dev.eden.eden_emulator"),
                "retroarch" to setOf("com.retroarch", "com.retroarch.aarch64", "com.retroarch.ra32"),
                "armsx2" to setOf("com.armsx2", "com.armsx2.nightly"), "duckstation" to setOf("com.github.stenzek.duckstation"))
            require(packages[emulator]?.contains(pkg) == true) { "Unknown emulator storage identity" }
            val provider = when (emulator) { "dolphin", "eden" -> "$pkg.user"; "retroarch" -> "$pkg.documents"; else -> null }
            val shared = uri.authority == "com.android.externalstorage.documents"
            require(shared || provider != null && uri.authority == provider) { "Select this emulator's provider or a shared folder" }
            if (shared) {
                val id = uri.pathSegments[1]; val split = id.split(':', limit = 2)
                require(split.size == 2 && Regex("[A-Za-z0-9_-]+").matches(split[0]) && split[1].isNotEmpty())
                val segments = path(split[1])
                require(segments.first() != "Android" && (emulator != "citra-mmj" || segments == listOf("citra-emu"))) { "Private Android/data storage is inaccessible. Choose a shared emulator folder." }
            }
        }
        return uri
    }
    private fun path(value: String): List<String> {
        require(value.length in 1..2048) { "Invalid shared save path" }
        val parts = value.removePrefix("@root/").let { if (it == "@root") emptyList() else it.split('/') }
        require(parts.size <= 32 && parts.all {
            it.isNotEmpty() && it.length <= 200 && it != "." && it != ".." &&
                it.none { c -> c.code < 32 || c == '\\' || c == ':' || c.code == 127 }
        }) { "Invalid shared save path" }
        return parts
    }
    private val columns = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE,
        Document.COLUMN_SIZE, Document.COLUMN_FLAGS, Document.COLUMN_LAST_MODIFIED)
    private fun entry(cursor: android.database.Cursor): Entry {
        require(cursor.getInt(4) and Document.FLAG_VIRTUAL_DOCUMENT == 0) { "Virtual saves are unsupported" }
        val result = Entry(cursor.getString(0), cursor.getString(1), cursor.getString(2), cursor.getLong(3), cursor.getLong(5))
        path(result.name)
        require('/' !in result.name && result.size >= 0) { "Invalid shared save entry" }
        return result
    }
    private fun uri(tree: Uri, id: String) = DocumentsContract.buildDocumentUriUsingTree(tree, id)
    private fun inspect(tree: Uri, id: String, op: Operation): Entry {
        op.check()
        val cursor = resolver.query(uri(tree, id), columns, null, null, null, op.signal)
            ?: error("Shared save folder could not be read; files were kept")
        return cursor.use {
            require(it.moveToFirst()) { "Shared save document is missing" }
            val found = entry(it); require(!it.moveToNext()); found
        }
    }
    private fun root(tree: Uri, op: Operation): Entry {
        require(resolver.persistedUriPermissions.any { it.uri == tree && it.isReadPermission && it.isWritePermission }) {
            "Save-folder access was revoked. Reconnect it in Emulator Settings."
        }
        return inspect(tree, DocumentsContract.getTreeDocumentId(tree), op).also {
            require(it.directory) { "The save root is not a folder" }
        }
    }
    private fun children(tree: Uri, parent: Entry, op: Operation): List<Entry> {
        op.check(); require(parent.directory)
        val cursor = resolver.query(DocumentsContract.buildChildDocumentsUriUsingTree(tree, parent.id),
            columns, null, null, null, op.signal) ?: error("Shared save scan failed; files were kept")
        return cursor.use {
            val results = ArrayList<Entry>()
            val names = HashSet<String>()
            val ids = HashSet<String>()
            while (it.moveToNext()) {
                op.check(); require(results.size < 10000) { "Shared save folder exceeds the scan limit" }
                val found = entry(it)
                require(names.add(found.name) && ids.add(found.id)) { "Ambiguous shared save entries" }
                results.add(found)
            }
            results
        }
    }
    private fun find(tree: Uri, parts: List<String>, op: Operation, create: Boolean = false): Entry? {
        var current = root(tree, op)
        for (part in parts) {
            require(current.directory) { "A save directory was replaced by a file" }
            var next = children(tree, current, op).singleOrNull { it.name == part }
            if (next == null && create) {
                op.check()
                val created = DocumentsContract.createDocument(resolver, uri(tree, current.id), Document.MIME_TYPE_DIR, part)
                    ?: error("Shared save directory could not be created")
                next = inspect(tree, DocumentsContract.getDocumentId(created), op)
                require(next.name == part && next.directory) { "Shared save directory creation changed its name" }
            }
            current = next ?: return null
        }
        return current
    }
    private fun digest(tree: Uri, file: Entry, op: Operation, target: File? = null): Pair<Long, String> {
        require(!file.directory && file.size <= 256L * 1024 * 1024) { "Shared save exceeds the file size limit" }
        val hash = MessageDigest.getInstance("SHA-256")
        var total = 0L
        val fd = resolver.openFileDescriptor(uri(tree, file.id), "r", op.signal) ?: error("Shared save could not be opened")
        op.descriptor.set(fd)
        try {
            ParcelFileDescriptor.AutoCloseInputStream(fd).use { input ->
                val out = target?.outputStream()
                try {
                    val buffer = ByteArray(131072)
                    while (true) {
                        op.check(); val count = input.read(buffer); if (count < 0) break
                        total += count; require(total <= 256L * 1024 * 1024) { "Shared save grew beyond its size limit" }
                        hash.update(buffer, 0, count); out?.write(buffer, 0, count)
                    }
                    out?.fd?.sync()
                } finally { out?.close() }
            }
        } finally { op.descriptor.getAndSet(null)?.close() }
        op.check(); require(total == file.size) { "Shared save changed while reading; close MMJ and retry" }
        return total to hash.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    private fun bounded(input: java.io.InputStream, limit: Int, op: Operation): ByteArray {
        val bytes = ByteArray(limit + 1); var count = 0
        while (count < bytes.size) {
            op.check(); val n = input.read(bytes, count, bytes.size-count); if (n < 0) break
            count += n
        }
        require(count <= limit) { "Document exceeds its inspection limit" }
        return bytes.copyOf(count)
    }
    private fun privateFile(value: String): File {
        val candidates = listOf("android/mmj-session", "android/shared-session").map { File(activity.filesDir, it) }
        val file = File(value)
        val base = candidates.singleOrNull { file.path.startsWith(it.path + "/") } ?: error("Invalid private save snapshot path")
        require(file.path.startsWith(base.path + "/") && file.canonicalPath == file.absolutePath &&
            file.parentFile?.isDirectory == true && !file.isDirectory) { "Invalid private MMJ snapshot path" }
        path(file.relativeTo(base).invariantSeparatorsPath)
        return file
    }
    private fun localHash(file: File, op: Operation): String {
        require(file.isFile && file.length() <= 256L * 1024 * 1024)
        val digest = MessageDigest.getInstance("SHA-256")
        file.inputStream().use { input ->
            val buffer = ByteArray(131072); var total = 0L
            while (true) { op.check(); val count = input.read(buffer); if (count < 0) break
                total += count; require(total <= 256L * 1024 * 1024); digest.update(buffer, 0, count) }
        }
        return digest.digest().joinToString("") { "%02x".format(it.toInt() and 255) }
    }
    fun operation(call: MethodCall): Any? {
        check(!closed.get()) { "The Android activity closed; retry save recovery." }
        val lock = SharedDocumentLock.acquire(File(activity.filesDir, "android"))
        val op = Operation()
        running.set(op)
        if (closed.get()) op.cancel()
        val timeout = Runnable { op.cancel() }
        main.postDelayed(timeout, 60000)
        try {
            val tree = tree(call.argument<String>("tree") ?: error("Missing shared folder"), call.argument<String>("emulator"), call.argument<String>("package"))
            root(tree, op)
            when (call.method) {
                "sharedCheck" -> {
                    if (call.argument<Boolean>("probe") == true) {
                        val parent = root(tree, op)
                        val name = ".broomm-probe-${java.util.UUID.randomUUID()}"
                        var created = DocumentsContract.createDocument(resolver, uri(tree, parent.id), "application/octet-stream", name)
                            ?: error("This emulator folder cannot create files")
                        try {
                            var entry = inspect(tree, DocumentsContract.getDocumentId(created), op)
                            require(entry.name == name && !entry.directory) { "Save provider changed the probe name" }
                            val fd = resolver.openFileDescriptor(created, "rwt", op.signal) ?: error("This folder is not writable")
                            op.descriptor.set(fd)
                            try { ParcelFileDescriptor.AutoCloseOutputStream(fd).use { it.write(23); it.fd.sync() } }
                            finally { op.descriptor.getAndSet(null)?.close() }
                            entry = inspect(tree, entry.id, op)
                            val expected = MessageDigest.getInstance("SHA-256").digest(byteArrayOf(23)).joinToString("") { "%02x".format(it.toInt() and 255) }
                            require(entry.size == 1L && digest(tree, entry, op).second == expected) { "Save provider failed readback" }
                            created = DocumentsContract.renameDocument(resolver, created, "$name-renamed") ?: error("Save provider does not support reliable replacement")
                            require(inspect(tree, DocumentsContract.getDocumentId(created), op).name == "$name-renamed")
                        } finally { require(DocumentsContract.deleteDocument(resolver, created)) { "Save probe cleanup failed" } }
                    }
                    return null
                }
                "sharedChildren" -> {
                    val relative = call.argument<String>("path") ?: ""
                    val directory = if (relative.isEmpty()) root(tree, op) else find(tree, path(relative), op) ?: return emptyList<Map<String, Any>>()
                    return children(tree, directory, op).map { mapOf("name" to it.name, "directory" to it.directory) }
                }
                "sharedStat" -> {
                    val found = find(tree, path(call.argument<String>("path")!!), op) ?: return null
                    require(!found.directory)
                    return mapOf("id" to found.id, "bytes" to found.size, "modified" to found.modified)
                }
                "sharedBytes" -> {
                    val found = find(tree, path(call.argument<String>("path")!!), op) ?: return null
                    require(!found.directory && found.size <= 1024*1024) { "Save configuration exceeds its inspection limit" }
                    val fd = resolver.openFileDescriptor(uri(tree, found.id), "r", op.signal) ?: error("Configuration cannot be opened")
                    op.descriptor.set(fd)
                    try {
                        return ParcelFileDescriptor.AutoCloseInputStream(fd).use { input ->
                            val bytes = bounded(input, 1024*1024, op)
                            require(bytes.size <= 1024*1024 && bytes.size.toLong() == found.size) { "Configuration changed during inspection" }; bytes
                        }
                    } finally { op.descriptor.getAndSet(null)?.close() }
                }
                "sharedList" -> {
                    val areas = call.argument<List<Map<String, String>>>("areas") ?: error("Missing save boundaries")
                    require(areas.size in 1..16)
                    val result = linkedMapOf<String, Map<String, Any>>()
                    val visited = HashSet<String>()
                    var total = 0L; var scanned = 0
                    fun visit(file: Entry, relative: String, area: Map<String, String>, base: String, depth: Int) {
                        op.check(); require(depth <= 32 && ++scanned <= 16384 && visited.add(file.id)) { "Shared save scan limit or duplicate document" }
                        if (file.directory) {
                            for (child in children(tree, file, op)) {
                                val r = "$relative/${child.name}".removePrefix("$base/")
                                if (area["prefix"] != null && (child.directory || !child.name.startsWith(area.getValue("prefix")))) continue
                                if (area["folderPrefix"] != null && !r.substringBefore('/').startsWith(area.getValue("folderPrefix"))) continue
                                if (area["exact"] != null && (child.directory || child.name != area["exact"])) continue
                                if (area["gciId"] != null && child.directory) continue
                                visit(child, "$relative/${child.name}", area, base, depth + 1)
                            }
                        } else {
                            val r = relative.removePrefix("$base/")
                            if (area["suffix"] != null && !r.endsWith(area.getValue("suffix"))) return
                            if (area["pattern"] != null && !Regex(area.getValue("pattern")).matches(r)) return
                            if (area["excluded"] != null && JSONArray(area.getValue("excluded")).let { a -> (0 until a.length()).any { a.getString(it) == r } }) return
                            if (area["gciId"] != null) {
                                val fd = resolver.openFileDescriptor(uri(tree, file.id), "r", op.signal) ?: error("GameCube save cannot be read")
                                op.descriptor.set(fd)
                                val header = try { ParcelFileDescriptor.AutoCloseInputStream(fd).use { input ->
                                    val h = ByteArray(6); var at = 0
                                    while (at < h.size) { op.check(); val n = input.read(h, at, h.size-at); if (n < 0) break; at += n }
                                    h.copyOf(at)
                                } }
                                    finally { op.descriptor.getAndSet(null)?.close() }
                                val id = area.getValue("gciId")
                                if (header.size < 6 || String(header, Charsets.US_ASCII) != id) return
                            }
                            val (bytes, sha) = digest(tree, file, op)
                            total += bytes; require(total <= 512L * 1024 * 1024 && result.size < 4096) { "Shared saves exceed bundle limits" }
                            require(!result.containsKey(relative)); result[relative] = mapOf("bytes" to bytes, "sha256" to sha)
                        }
                    }
                    for (area in areas) {
                        visited.clear()
                        val relative = area["path"] ?: error("Missing save directory")
                        val found = find(tree, path(relative), op) ?: continue
                        require(found.directory) { "Shared save directory is not a folder" }
                        visit(found, relative, area, relative, 0)
                    }
                    return result
                }
                "sharedRead" -> {
                    val target = privateFile(call.argument<String>("target") ?: error("Missing snapshot target"))
                    require(target.createNewFile()) { "Snapshot destination already exists" }
                    try {
                        val found = find(tree, path(call.argument<String>("path")!!), op) ?: error("Shared save disappeared")
                        val (bytes, sha) = digest(tree, found, op, target)
                        require(bytes == call.argument<Number>("bytes")!!.toLong() && sha == call.argument<String>("sha256")) { "Shared save changed during snapshot" }
                    } catch (e: Exception) { target.delete(); throw e }
                    return null
                }
                "sharedReplace" -> {
                    replace(call, tree, op)
                    return null
                }
                else -> error("Unknown shared save operation")
            }
        } finally {
            main.removeCallbacks(timeout)
            try { op.descriptor.getAndSet(null)?.close() }
            finally { running.compareAndSet(op, null); lock.close() }
        }
    }
    private fun replace(call: MethodCall, tree: Uri, op: Operation) {
        val parts = path(call.argument<String>("path")!!)
        val before = call.argument<String>("before")
        val after = call.argument<String>("after")
        require(listOfNotNull(before, after).all { Regex("[a-f0-9]{64}").matches(it) })
        val token = call.argument<String>("token")!!
        require(Regex("[a-f0-9]{32}-(in|out)").matches(token))
        val parent = find(tree, parts.dropLast(1), op, create = after != null)
        if (parent == null) { require(before == null && after == null); return }
        val name = parts.last()
        val stageName = ".broomm-$token-$name"
        // Leave room for provider filename limits while retaining exclusive identity.
        val tempName = if (stageName.length <= 180) stageName else ".broomm-$token-${MessageDigest.getInstance("SHA-256").digest(name.toByteArray()).take(16).joinToString("") { "%02x".format(it.toInt() and 255) }}"
        fun child(n: String) = children(tree, parent, op).singleOrNull { it.name == n }
        fun hash(file: Entry?) = file?.let { digest(tree, it, op).second }
        var current = child(name)
        var stage = child(tempName)
        val actual = hash(current)
        if (actual == after) {
            if (stage != null) {
                // Only this transaction's deterministic stage is eligible.
                require(after == null || hash(stage) == after)
                require(DocumentsContract.deleteDocument(resolver, uri(tree, stage.id)))
            }
            return
        }
        val stagedHash = hash(stage)
        require(actual == before || actual == null && stage != null && stagedHash == after) {
            "Shared save changed outside Broomm. Close MMJ and retry; recovery copies were kept."
        }
        if (after == null) {
            require(current != null && DocumentsContract.deleteDocument(resolver, uri(tree, current.id)))
            return
        }
        val source = privateFile(call.argument<String>("source") ?: error("Missing recovery source"))
        require(localHash(source, op) == after) { "Private recovery copy failed verification" }
        if (stage != null && stagedHash != after) {
            require(actual == before) { "Incomplete shared save stage; copies were kept" }
            require(DocumentsContract.deleteDocument(resolver, uri(tree, stage.id))); stage = null
        }
        if (stage == null) {
            op.check()
            val created = DocumentsContract.createDocument(resolver, uri(tree, parent.id), "application/octet-stream", tempName)
                ?: error("Shared save staging failed")
            stage = inspect(tree, DocumentsContract.getDocumentId(created), op)
            require(stage.name == tempName && !stage.directory) { "Shared save staging name changed" }
            val fd = resolver.openFileDescriptor(uri(tree, stage.id), "rwt", op.signal) ?: error("Shared save stage cannot be written")
            op.descriptor.set(fd)
            try {
                ParcelFileDescriptor.AutoCloseOutputStream(fd).use { output -> source.inputStream().use { input ->
                    val buffer = ByteArray(131072); var total = 0L
                    while (true) { op.check(); val count = input.read(buffer); if (count < 0) break
                        total += count; require(total <= 256L * 1024 * 1024); output.write(buffer, 0, count) }
                    output.fd.sync()
                } }
            } finally { op.descriptor.getAndSet(null)?.close() }
            stage = inspect(tree, stage.id, op)
            require(hash(stage) == after) { "Shared save stage failed readback" }
        }
        current = child(name)
        val latest = hash(current)
        require(latest == actual) { "Shared save changed before publication; copies were kept" }
        op.check()
        if (current != null) require(DocumentsContract.deleteDocument(resolver, uri(tree, current.id)))
        val renamed = DocumentsContract.renameDocument(resolver, uri(tree, stage.id), name)
            ?: error("Shared save publication was interrupted; finish the Broomm session to recover")
        val published = inspect(tree, DocumentsContract.getDocumentId(renamed), op)
        require(published.name == name && hash(published) == after) { "Shared save publication failed readback" }
    }
}
