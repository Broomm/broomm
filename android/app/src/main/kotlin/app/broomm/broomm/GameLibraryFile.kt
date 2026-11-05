package app.broomm.broomm

import java.io.File

/** Resolve only the framework filesDir alias, never a link within the library. */
internal fun gameLibraryFile(filesDir: File, value: String): File {
    val base = File(filesDir.canonicalFile, "broomm/library")
    require(base.canonicalPath == base.absolutePath && base.isDirectory)
    val logical = File(filesDir, "broomm/library").absolutePath
    val prefix = listOf(logical, base.path).firstOrNull { value.startsWith("$it/") }
        ?: error("Game file is outside the Broomm library")
    val relative = value.substring(prefix.length + 1)
    require(relative.split('/').all { it.isNotEmpty() && it != "." && it != ".." && it.none { c -> c.code < 32 || c == '\\' } })
    require(Regex("[a-f0-9]{32}/[1-9][0-9]*/content/.+").matches(relative))
    var file = base
    for (part in relative.split('/')) {
        file = File(file, part)
        require(file.canonicalPath == file.absolutePath) { "Game library contains a linked path" }
    }
    require(file.isFile) { "Game file is missing" }
    return file
}
