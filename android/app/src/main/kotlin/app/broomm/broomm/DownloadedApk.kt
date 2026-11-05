package app.broomm.broomm

import java.io.File

/** Matches ShellStorage's Android data root and AndroidApkDownload's staging directory. */
internal fun isDownloadedApk(filesDir: File, apk: File): Boolean {
    val base = File(filesDir, "broomm/android/apks")
    return apk.parentFile?.canonicalFile == base.canonicalFile &&
        apk.canonicalPath == apk.absolutePath &&
        Regex("[a-f0-9]{32}\\.apk").matches(apk.name) &&
        apk.isFile && apk.length() in 1..1024L * 1024 * 1024
}
