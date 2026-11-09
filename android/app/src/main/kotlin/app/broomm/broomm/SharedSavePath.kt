package app.broomm.broomm

import java.io.File

internal fun sharedSavePath(value: String): List<String> {
    require(value.length in 1..2048) { "Invalid shared save path" }
    val parts = value.removePrefix("@root/").let { if (it == "@root") emptyList() else it.split('/') }
    require(parts.size <= 32 && parts.all {
        it.isNotEmpty() && it.length <= 200 && it != "." && it != ".." &&
            it.none { c -> c.code < 32 || c == '\\' || c == ':' || c.code == 127 }
    }) { "Invalid shared save path" }
    return parts
}

/** Admit the framework's filesDir alias, but no links inside Broomm's data. */
internal fun sharedSaveSnapshotFile(filesDir: File, value: String): File {
    val canonical = filesDir.canonicalFile
    for (area in listOf("mmj-session", "shared-session")) {
        val suffix = "broomm/android/$area"
        val base = File(canonical, suffix)
        val logical = File(filesDir, suffix).absolutePath
        val prefix = listOf(logical, base.path).firstOrNull { value.startsWith("$it/") } ?: continue
        val relative = value.substring(prefix.length + 1)
        require(!relative.startsWith("@root/") && relative != "@root") { "Invalid private save snapshot path" }
        val parts = sharedSavePath(relative)
        require(base.canonicalPath == base.absolutePath) { "Invalid private save snapshot path" }
        var file = base
        for (part in parts) {
            file = File(file, part)
            require(file.canonicalPath == file.absolutePath) { "Invalid private save snapshot path" }
        }
        require(file.parentFile?.isDirectory == true && !file.isDirectory) { "Invalid private save snapshot path" }
        return file
    }
    error("Invalid private save snapshot path")
}
