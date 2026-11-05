package app.broomm.broomm

import java.io.File
import java.nio.file.Files

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
        println("Downloaded APK layout, foreign-path and linked/incomplete-file regressions passed")
    } finally {
        root.deleteRecursively()
    }
}
