package app.broomm.broomm

import java.io.File

internal fun gameLibraryRelative(filesDir: File, value: String): String {
    val file = gameLibraryFile(filesDir, value)
    return file.relativeTo(File(filesDir.canonicalFile, "broomm/library")).invariantSeparatorsPath
}

internal fun gameLibraryFromRelative(filesDir: File, relative: String): File =
    gameLibraryFile(filesDir, "${filesDir.absolutePath}/broomm/library/$relative")

/** Only one prepared cartridge in this session's private extraction can cross
 * the root-service mount namespace. Ordinary library resolution stays separate. */
internal fun preparedCartridgeFile(filesDir: File, value: String, transaction: String, name: String): File {
    require(Regex("[a-f0-9]{32}").matches(transaction))
    require(name.isNotEmpty() && name !in setOf(".", "..") && name.none { it.code < 32 || it in "/\\" })
    val relativeBase = "broomm/android/shared-session/$transaction"
    val base = File(filesDir.canonicalFile, relativeBase)
    require(base.canonicalPath == base.absolutePath && base.isDirectory)
    val prefix = listOf(File(filesDir, relativeBase).absolutePath, base.path)
        .firstOrNull { value.startsWith("$it/") } ?: error("Cartridge is outside this private session")
    val relative = value.substring(prefix.length + 1)
    val parts = relative.split('/')
    require(parts.size == 2 && Regex("cartridge-[a-zA-Z0-9_-]+").matches(parts[0]) && parts[1] == name)
    var file = base
    for (part in parts) {
        file = File(file, part)
        require(file.canonicalPath == file.absolutePath) { "Prepared cartridge contains a linked path" }
    }
    require(file.isFile) { "Prepared cartridge is missing" }
    return file
}

internal fun preparedCartridgeRelative(filesDir: File, value: String, transaction: String, name: String): String =
    preparedCartridgeFile(filesDir, value, transaction, name)
        .relativeTo(File(filesDir.canonicalFile, "broomm/android/shared-session/$transaction")).invariantSeparatorsPath

internal fun preparedCartridgeFromRelative(filesDir: File, relative: String, transaction: String, name: String): File =
    preparedCartridgeFile(filesDir, "${filesDir.absolutePath}/broomm/android/shared-session/$transaction/$relative", transaction, name)

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
