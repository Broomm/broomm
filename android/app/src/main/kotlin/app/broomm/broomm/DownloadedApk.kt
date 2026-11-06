package app.broomm.broomm

import java.io.File

/** Matches ShellStorage's Android data root and AndroidApkDownload's staging directory. */
internal fun downloadedApk(filesDir: File, apk: File): File {
    require(Regex("[a-f0-9]{32}\\.apk").matches(apk.name)) { "Invalid downloaded APK filename" }
    // Context supplies the trusted application root. Android's isolated app
    // namespace may alias /data/user/0 to /data/data above that root.
    // Resolve only that root, never an app-owned staging directory or file.
    val base = File(filesDir.canonicalFile, "broomm/android/apks")
    val canonical = File(base, apk.name)
    val logical = File(File(filesDir, "broomm/android/apks"), apk.name)
    require(apk == logical || apk == canonical) { "Downloaded APK is outside Broomm's staging directory" }
    require(apk.canonicalFile == canonical) { "Downloaded APK staging contains a linked path" }
    require(canonical.isFile && canonical.length() in 1..1024L * 1024 * 1024) { "Downloaded APK is missing, empty or too large" }
    // Package inspection and the content grant consume the same verified path.
    return canonical
}
