package app.broomm.broomm

import android.database.Cursor
import android.database.MatrixCursor
import android.os.CancellationSignal
import android.os.ParcelFileDescriptor
import android.provider.DocumentsContract.Document
import android.provider.DocumentsContract.Root
import android.provider.DocumentsProvider
import java.io.FileNotFoundException

/** Exact read-only game capabilities, with no browsable roots or tree grants.
 * A real DocumentsProvider is required by DuckStation's related-file resolver.
 * Legacy emulator URIs remain with GameContentProvider.
 */
class GameDocumentsProvider : DocumentsProvider() {
    override fun onCreate() = true
    private val columns = arrayOf(Document.COLUMN_DOCUMENT_ID, Document.COLUMN_DISPLAY_NAME,
        Document.COLUMN_SIZE, Document.COLUMN_MIME_TYPE, Document.COLUMN_FLAGS, Document.COLUMN_LAST_MODIFIED)

    private fun file(id: String) = gameGrantFile(context!!, try {
        gameGrantPath(listOf("document", id))
    } catch (_: IllegalArgumentException) { throw FileNotFoundException("Invalid game document") })

    override fun queryRoots(projection: Array<out String>?): Cursor =
        MatrixCursor(projection ?: arrayOf(Root.COLUMN_ROOT_ID, Root.COLUMN_DOCUMENT_ID, Root.COLUMN_TITLE))

    override fun queryDocument(documentId: String, projection: Array<out String>?): Cursor {
        val f = file(documentId)
        return MatrixCursor(projection ?: columns).also { result ->
            result.addRow(result.columnNames.map { when (it) {
                Document.COLUMN_DOCUMENT_ID -> documentId
                Document.COLUMN_DISPLAY_NAME -> f.name
                Document.COLUMN_SIZE -> f.length()
                Document.COLUMN_MIME_TYPE -> "application/octet-stream"
                Document.COLUMN_FLAGS -> 0
                Document.COLUMN_LAST_MODIFIED -> f.lastModified()
                else -> null
            } })
        }
    }

    override fun queryChildDocuments(parentDocumentId: String, projection: Array<out String>?, sortOrder: String?): Cursor =
        throw FileNotFoundException("Game folder access is not available")

    override fun isChildDocument(parentDocumentId: String, documentId: String) = false

    override fun openDocument(documentId: String, mode: String, signal: CancellationSignal?): ParcelFileDescriptor {
        signal?.throwIfCanceled()
        if (mode != "r") throw UnsupportedOperationException("Game files are read only")
        return ParcelFileDescriptor.open(file(documentId), ParcelFileDescriptor.MODE_READ_ONLY)
    }
}
