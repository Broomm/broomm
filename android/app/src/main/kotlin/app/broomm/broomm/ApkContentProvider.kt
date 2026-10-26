package app.broomm.broomm

import android.content.ContentProvider
import android.content.ContentValues
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/** Installer access is confined to an explicitly selected, inspected APK. */
class ApkContentProvider : ContentProvider() {
    override fun onCreate() = true
    private fun file(uri: Uri): File {
        val token = uri.pathSegments.singleOrNull() ?: throw FileNotFoundException()
        if (!Regex("[a-f0-9]{32}").matches(token)) throw FileNotFoundException()
        val path = context!!.getSharedPreferences("apk-grants", 0).getString(token, null) ?: throw FileNotFoundException()
        val file = File(path)
        if (!file.isFile || file.canonicalPath != file.absolutePath ||
            file.parentFile?.canonicalFile != File(context!!.cacheDir, "install-apk").canonicalFile) throw FileNotFoundException()
        return file
    }
    override fun getType(uri: Uri) = "application/vnd.android.package-archive"
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, args: Array<out String>?, sort: String?): Cursor {
        val file = file(uri)
        val columns = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
        return MatrixCursor(columns).also { c -> c.addRow(columns.map { when (it) {
            OpenableColumns.DISPLAY_NAME -> file.name
            OpenableColumns.SIZE -> file.length()
            else -> null
        } }) }
    }
    override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
        if (mode != "r") throw FileNotFoundException()
        return ParcelFileDescriptor.open(file(uri), ParcelFileDescriptor.MODE_READ_ONLY)
    }
    override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
    override fun delete(uri: Uri, selection: String?, args: Array<out String>?) = throw UnsupportedOperationException()
    override fun update(uri: Uri, values: ContentValues?, selection: String?, args: Array<out String>?) = throw UnsupportedOperationException()
}
