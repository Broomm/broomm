package app.broomm.broomm

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.io.FileNotFoundException

/** Read-only capabilities for a verified library manifest, never all filesDir. */
class GameContentProvider : ContentProvider() {
    override fun onCreate() = true
    private fun file(uri: Uri): File {
        val segments = uri.pathSegments
        if (segments.size < 3 || segments.size > 35 || segments[0] != "game" ||
            !Regex("[a-f0-9]{32}").matches(segments[1])) throw FileNotFoundException("Invalid game grant")
        val record = context!!.getSharedPreferences("game-grants", 0).getString(segments[1], null)
            ?: throw FileNotFoundException("Game grant expired")
        val value = JSONObject(record)
        val files = value.getJSONArray("files")
        val relative = segments.drop(2)
        if (relative.any { it.isEmpty() || it == "." || it == ".." || it.contains('\\') || it.contains('/') || it.contains('\u0000') }) throw FileNotFoundException("Invalid game path")
        val path = value.getString("base") + "/" + relative.joinToString("/")
        if (!(0 until files.length()).any { files.getString(it) == path }) throw FileNotFoundException("Unknown game file")
        val file = File(path)
        val library = File(context!!.filesDir, "library").canonicalFile
        if (!file.canonicalPath.startsWith(library.path + File.separator) ||
            file.canonicalPath != file.absolutePath || !file.isFile)
            throw FileNotFoundException("Game file is missing or linked")
        return file
    }
    override fun getType(uri: Uri) = "application/octet-stream"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
                       selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
        val f = file(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        val result = MatrixCursor(columns)
        result.addRow(columns.map { when (it) {
            OpenableColumns.DISPLAY_NAME -> f.name
            OpenableColumns.SIZE -> f.length()
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
