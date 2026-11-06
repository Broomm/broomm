package app.broomm.broomm

import java.io.File
import java.nio.file.Files

private fun isDownloadedApk(files: File, apk: File) =
    runCatching { downloadedApk(files, apk) }.isSuccess

fun main() {
    val root = Files.createTempDirectory("broomm-apk-check-").toFile().canonicalFile
    try {
        val files = File(root, "files").apply { mkdirs() }
        val name = "a".repeat(32) + ".apk"
        fun fixture(path: String) = File(files, path).apply {
            parentFile.mkdirs()
            writeText("APK path fixture; archive inspection is a separate boundary")
        }
        val apk = fixture("broomm/android/apks/$name")
        check(isDownloadedApk(files, apk)) { "Rejects the real Dart application-storage layout" }
        for (path in listOf("android/apks/$name", "broomm/android/elsewhere/$name", "broomm/android/apks/nested/$name", "broomm/android/apks/foreign.apk")) {
            check(!isDownloadedApk(files, fixture(path))) { "Accepted foreign staging path: $path" }
        }
        val link = File(apk.parentFile, "b".repeat(32) + ".apk")
        Files.createSymbolicLink(link.toPath(), apk.toPath())
        check(!isDownloadedApk(files, link)) { "Accepted linked APK" }
        check(!isDownloadedApk(files, File(apk.parentFile, "../apks/$name"))) { "Accepted path traversal" }
        apk.writeBytes(byteArrayOf())
        check(!isDownloadedApk(files, apk)) { "Accepted empty APK" }
        apk.delete()
        check(!isDownloadedApk(files, apk)) { "Accepted missing APK" }

        // Reproduce Android's app-private mount namespace, not the ADB shell's
        // different /data/user/0 view. Both native consumers use this result.
        val physical = File(root, "data/pkg/files").apply { mkdirs() }
        val user = File(root, "user").apply { mkdirs() }
        Files.createSymbolicLink(File(user, "0").toPath(), File(root, "data").toPath())
        val logical = File(user, "0/pkg/files")
        val staged = File(physical, "broomm/android/apks/$name").apply {
            parentFile.mkdirs()
            writeText("complete APK path fixture")
        }
        val aliased = File(logical, "broomm/android/apks/$name")
        check(aliased.absolutePath != aliased.canonicalPath)
        check(downloadedApk(logical, aliased) == staged) { "Rejected Android's trusted root alias" }
        check(downloadedApk(logical, staged) == staged) { "Rejected canonical content-grant path" }

        val linkedFile = File(aliased.parentFile, "c".repeat(32) + ".apk")
        Files.createSymbolicLink(linkedFile.toPath(), staged.toPath())
        check(!isDownloadedApk(logical, linkedFile)) { "Trusted root alias allowed a linked APK" }
        linkedFile.delete()
        val other = File(root, "other-user/files/broomm/android/apks/$name").apply {
            parentFile.mkdirs()
            writeText("another user's APK")
        }
        check(!isDownloadedApk(logical, other)) { "Accepted another user's staging root" }
        staged.parentFile.deleteRecursively()
        Files.createSymbolicLink(staged.parentFile.toPath(), other.parentFile.toPath())
        check(!isDownloadedApk(logical, aliased)) { "Trusted root alias allowed a linked staging directory" }
        println("Downloaded APK layout, foreign-path and linked/incomplete-file regressions passed")
    } finally {
        root.deleteRecursively()
    }
}
