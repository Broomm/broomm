package app.broomm.broomm

import android.Manifest
import android.app.AppOpsManager
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.system.Os
import android.system.OsConstants
import java.io.File

internal const val CITRA_SHARED_PACKAGE = "org.citra.emu"
internal const val CITRA_SHARED_SIGNER = "5ebda360d963001a31b3a062b6151f7d38345d8da49540e74895825ed0ca5e1a"
internal const val CITRA_ROOT_FOLDER = "root-mmj-folder-v1"

/** Check the reviewed APK's legacy initialization branch, without changing permissions. */
internal fun requireCitraSharedFolder(context: Context, uid: Int, selected: String) {
    val uri = Uri.parse(selected)
    require(uri.scheme == "content" && uri.authority == "com.android.externalstorage.documents" &&
        uri.query == null && uri.fragment == null && uri.pathSegments == listOf("tree", "primary:citra-emu")) {
        "Select Internal storage/citra-emu for Citra MMJ."
    }
    val packageManager = context.packageManager
    val appOps = context.getSystemService(AppOpsManager::class.java)
    require(packageManager.checkPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE, CITRA_SHARED_PACKAGE) ==
        PackageManager.PERMISSION_GRANTED &&
        appOps.unsafeCheckOpNoThrow("android:legacy_storage", uid, CITRA_SHARED_PACKAGE) == AppOpsManager.MODE_ALLOWED) {
        "Open the standard Citra MMJ APK once and finish its legacy shared-storage setup."
    }
    val physical = File("/data/media/0/citra-emu")
    val logical = File("/storage/emulated/0/citra-emu")
    val initialized = listOf("config", "nand", "sdmc").all { name ->
        val child = File(physical, name)
        child.canonicalPath == child.path && child.isDirectory
    }
    require(initialized && physical.canonicalPath == physical.path && logical.canonicalPath == logical.path) {
        "Open Citra MMJ once and wait for Internal storage/citra-emu to initialize."
    }
    val source = Os.lstat(physical.path)
    val visible = Os.lstat(logical.path)
    require(OsConstants.S_ISDIR(source.st_mode) && OsConstants.S_ISDIR(visible.st_mode) && source.st_ino == visible.st_ino) {
        "Citra MMJ’s shared storage mount could not be verified."
    }
}
