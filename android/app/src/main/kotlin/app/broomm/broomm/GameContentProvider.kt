package app.broomm.broomm

import android.content.ContentProvider
import android.content.Context
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import android.provider.DocumentsContract
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException

internal fun gameGrantFile(context: Context, grant: GameGrantPath): File {
    val record = context.getSharedPreferences("game-grants", 0).getString(grant.token, null)
        ?: throw FileNotFoundException("Game grant expired")
    val value = JSONObject(record)
    val files = value.getJSONArray("files")
    return grantedGameFile(context.filesDir, grant, value.getString("base"),
        (0 until files.length()).map { files.getString(it) })
}

/** Read-only capabilities for a verified library manifest, never all filesDir. */
class GameContentProvider : ContentProvider() {
    override fun onCreate() = true
    private fun file(uri: Uri): File {
        val grant = try { gameGrantPath(uri.pathSegments) }
            catch (_: IllegalArgumentException) { throw FileNotFoundException("Invalid game grant") }
        return gameGrantFile(context!!, grant)
    }
    override fun getType(uri: Uri) = "application/octet-stream"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
                       selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val f = file(uri)
        val document = uri.pathSegments.firstOrNull() == "document"
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val result = MatrixCursor(columns)
        result.addRow(columns.map { when (it) {
            OpenableColumns.DISPLAY_NAME -> f.name
            OpenableColumns.SIZE -> f.length()
            DocumentsContract.Document.COLUMN_DOCUMENT_ID -> if (document) gameGrantPath(uri.pathSegments).documentId else null
            DocumentsContract.Document.COLUMN_MIME_TYPE -> if (document) "application/octet-stream" else null
            DocumentsContract.Document.COLUMN_LAST_MODIFIED -> if (document) f.lastModified() else null
            DocumentsContract.Document.COLUMN_FLAGS -> if (document) 0 else null // Read-only files, no folder capability.
            else -> null
        } })
        return result
    }
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException("Game files are read only")
        return ParcelFileDescriptor.open(file(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?) = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?) = throw UnsupportedOperationException()
}
