package app.broomm.broomm

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException
import android.os.Handler
import android.os.Looper
import java.util.concurrent.atomic.AtomicInteger
import android.system.Os

/** Only explicitly configured emulator roots appear in Android's file picker.
 * Credentials, cloud recovery, application records and ROMs are never exposed.
 * Document identities include the profile; they never follow the active login.
 */
class EmulatorDocumentsProvider : DocumentsProvider() {
    companion object { val writers = AtomicInteger(0) }
    override fun onCreate() = true
    private val rootColumns = arrayOf(Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_TITLE, Root.COLUMN_FLAGS, Root.COLUMN_MIME_TYPES)
    private val documentColumns = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME, Document.COLUMN_MIME_TYPE, Document.COLUMN_FLAGS, Document.COLUMN_SIZE, Document.COLUMN_LAST_MODIFIED)
    private fun roots() = context!!.getSharedPreferences("emulator-roots", 0)
    private fun root(id: String): File {
        if (!Regex("[a-f0-9]{32}:(ppsspp|melonds|azahar)").matches(id)) throw FileNotFoundException("Unknown emulator root")
        val saved = roots().getString(id, null) ?: throw FileNotFoundException("Unknown emulator root")
        val parts = id.split(':')
        val expected = File(context!!.filesDir, "profiles/${parts[0]}/emulators/${parts[1]}/user")
        if (JSONObject(saved).getString("path") != expected.absolutePath || expected.canonicalPath != expected.absolutePath || !expected.isDirectory)
            throw FileNotFoundException("Emulator root is missing or linked")
        return expected
    }
    private fun resolve(id: String): Pair<String, File> {
        val key = id.substringBefore('|')
        val active = context!!.getSharedPreferences("game-grants", 0).getString("active-root", null)
        if (!active.isNullOrEmpty() && active != key) throw FileNotFoundException("Choose the current Broomm profile's emulator folder")
        val base = root(key)
        val path = if ('|' in id) id.substringAfter('|') else ""
        if (path.isEmpty()) return key to base
        val parts = path.split('/')
        if (parts.size > 32 || parts.any { it.isEmpty() || it == "." || it == ".." || it.contains('\\') || it.any { c -> c.code < 32 } }) throw FileNotFoundException("Unsafe emulator path")
        val file = File(base, path)
        if (!file.canonicalPath.startsWith(base.canonicalPath + File.separator) || file.canonicalPath != file.absolutePath)
            throw FileNotFoundException("Linked emulator path")
        return key to file
    }
    private fun id(key: String, file: File): String {
        val base = root(key)
        return if (file == base) key else "$key|${file.relativeTo(base).invariantSeparatorsPath}"
    }
    private fun row(cursor: MatrixCursor, key: String, file: File) {
        if (!file.exists() || file.canonicalPath != file.absolutePath) throw FileNotFoundException()
        cursor.newRow().also { row ->
            for (column in cursor.columnNames) row.add(when (column) {
                Document.COLUMN_DOCUMENT_ID -> id(key, file)
                Document.COLUMN_DISPLAY_NAME -> if (file == root(key)) JSONObject(roots().getString(key, null)!!).getString("label") else file.name
                Document.COLUMN_MIME_TYPE -> if (file.isDirectory) Document.MIME_TYPE_DIR else "application/octet-stream"
                Document.COLUMN_FLAGS -> if (file.isDirectory) Document.FLAG_DIR_SUPPORTS_CREATE else Document.FLAG_SUPPORTS_WRITE or Document.FLAG_SUPPORTS_DELETE or Document.FLAG_SUPPORTS_RENAME
                Document.COLUMN_SIZE -> if (file.isFile) file.length() else 0L
                Document.COLUMN_LAST_MODIFIED -> file.lastModified()
                else -> null
            })
        }
    }
    override fun queryRoots(projection: Array<out String>?): Cursor = MatrixCursor(projection ?: rootColumns).also { cursor ->
        for ((key, value) in roots().all) {
            if (value !is String) continue
            try { root(key) } catch (_: FileNotFoundException) { continue }
            val label = JSONObject(value).getString("label")
            cursor.newRow().also { row -> for (column in cursor.columnNames) row.add(when (column) {
                Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID -> key
                Root.COLUMN_TITLE -> label
                Root.COLUMN_FLAGS -> Root.FLAG_SUPPORTS_CREATE or Root.FLAG_SUPPORTS_IS_CHILD
                Root.COLUMN_MIME_TYPES -> "*/*"
                else -> null
            }) }
        }
    }
    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor = MatrixCursor(projection ?: documentColumns).also { cursor ->
        val (key, file) = resolve(documentId); row(cursor, key, file)
    }
    override fun queryChildDocuments(parentDocumentId: String, projection: Array<out String>?, sortOrder: String?): Cursor = MatrixCursor(projection ?: documentColumns).also { cursor ->
        val (key, parent) = resolve(parentDocumentId)
        if (!parent.isDirectory) throw FileNotFoundException("Not an emulator directory")
        val children = parent.listFiles() ?: throw FileNotFoundException("Emulator directory cannot be read")
        if (children.size > 10000) throw FileNotFoundException("Emulator directory exceeds enumeration limit")
        for (file in children) { resolve(id(key, file)); row(cursor, key, file) }
    }
    override fun isChildDocument(parentDocumentId: String, documentId: String): Boolean {
        val (pk, parent) = resolve(parentDocumentId); val (ck, child) = resolve(documentId)
        return pk == ck && child.path.startsWith(parent.path + File.separator)
    }
    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor {
        signal?.throwIfCanceled()
        val (_, file) = resolve(documentId)
        if (!file.isFile) throw FileNotFoundException("Emulator file is missing")
        if (mode == "r") return ParcelFileDescriptor.open(file, ParcelFileDescriptor.MODE_READ_ONLY)
        writers.incrementAndGet()
        try {
            return ParcelFileDescriptor.open(file, ParcelFileDescriptor.parseMode(mode), Handler(Looper.getMainLooper())) { _ -> writers.decrementAndGet() }
        } catch (e: Exception) { writers.decrementAndGet(); throw e }
    }
    private fun name(value: String): String {
        if (value.isEmpty() || value.length > 200 || value == "." || value == ".." || value.any { it == '/' || it == '\\' || it.code < 32 })
            throw FileNotFoundException("Invalid emulator filename")
        return value
    }
    override fun createDocument(parentDocumentId: String, mimeType: String, displayName: String): String {
        val (key, parent) = resolve(parentDocumentId)
        val file = File(parent, name(displayName))
        resolve(id(key, file))
        if (!parent.isDirectory || !(if (mimeType == Document.MIME_TYPE_DIR) file.mkdir() else file.createNewFile()))
            throw FileNotFoundException("Emulator destination already exists or is unavailable")
        return id(key, file)
    }
    override fun renameDocument(documentId: String, displayName: String): String {
        val (key, file) = resolve(documentId)
        if (file == root(key)) throw FileNotFoundException("Cannot rename an emulator root")
        val next = File(file.parentFile, name(displayName))
        resolve(id(key, next))
        if (!file.isFile) throw FileNotFoundException("Directory rename is not supported")
        // link() publishes exclusively; rename() could replace a destination
        // created between an existence check and publication.
        try { Os.link(file.path, next.path); Os.remove(file.path) }
        catch (e: Exception) { throw FileNotFoundException("Emulator rename failed; existing files were kept") }
        return id(key, next)
    }
    override fun deleteDocument(documentId: String) {
        val (key, file) = resolve(documentId)
        // No recursive directory removal through an external application.
        if (file == root(key) || !file.delete()) throw FileNotFoundException("Emulator removal failed")
    }
}
