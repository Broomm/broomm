package app.broomm.broomm

import android.net.Uri
import android.util.Xml
import java.io.ByteArrayInputStream
import org.xmlpull.v1.XmlPullParser

internal const val AZAHAR_SCOPED_PACKAGE = "io.github.lime3ds.android"
internal const val AZAHAR_SCOPED_SIGNER = "5ba2563e0d13fae2aba067d1c230cd1c863a93005c10d648ce5b331792aa0af1"
internal const val AZAHAR_ROOT_FOLDER = "root-azahar-folder-v1"

/** Verify the configured grant without writing with root or exposing preferences. */
internal fun requireAzaharFolder(files: RootSaveFiles, selected: String) {
    val path = "shared_prefs/${AZAHAR_SCOPED_PACKAGE}_preferences.xml"
    require(files.present(files.path(path))) { "Open Azahar once and select its user-data folder." }
    val bytes = files.bytes(files.existing(path), 256 * 1024)
    val parser = Xml.newPullParser()
    parser.setInput(ByteArrayInputStream(bytes), "UTF-8")
    var configured: String? = null
    var legacy: String? = null
    while (parser.next() != XmlPullParser.END_DOCUMENT) {
        if (parser.eventType != XmlPullParser.START_TAG) continue
        if (parser.depth == 1) require(parser.name == "map")
        if (parser.depth != 2 || parser.name != "string") continue
        when (parser.getAttributeValue(null, "name")) {
            "CITRA_DIRECTORY" -> {
                require(configured == null) { "Azahar has conflicting user-data settings." }
                configured = parser.nextText()
            }
            "LIME3DS_DIRECTORY" -> {
                require(legacy == null) { "Azahar has conflicting user-data settings." }
                legacy = parser.nextText()
            }
        }
    }
    require(legacy.isNullOrEmpty() || legacy == configured) {
        "Finish Azahar’s user-data migration before connecting its folder."
    }
    val wanted = azaharTreeId(selected)
    require(wanted != null && azaharTreeId(configured) == wanted) {
        "Select the same user-data folder in Azahar and Broomm."
    }
}

private fun azaharTreeId(value: String?): String? {
    if (value.isNullOrEmpty() || value.length >= 4096) return null
    val uri = Uri.parse(value)
    val path = uri.pathSegments
    return path.getOrNull(1)?.takeIf {
        uri.scheme == "content" && uri.authority == "com.android.externalstorage.documents" &&
            uri.query == null && uri.fragment == null && path.size == 2 && path[0] == "tree" &&
            it.startsWith("primary:") && it.length > 8
    }
}
