import app.broomm.broomm.gameLibraryFile
import app.broomm.broomm.gameLibraryFromRelative
import app.broomm.broomm.gameLibraryRelative
import java.io.File
import java.nio.file.Files

fun main() {
    val fixture = Files.createTempDirectory("broomm-game-library-").toFile().canonicalFile
    try {
        val real = File(fixture, "files").apply { mkdir() }
        val alias = File(fixture, "framework-files")
        Files.createSymbolicLink(alias.toPath(), real.toPath())
        val relative = "broomm/library/${"a".repeat(32)}/2338/content/Minish Cap.gba"
        val rom = File(real, relative).apply { parentFile.mkdirs(); writeBytes(byteArrayOf(1, 2)) }
        check(gameLibraryFile(alias, File(alias, relative).path) == rom)
        check(gameLibraryFile(alias, rom.path) == rom)
        // Separate mount names can both be canonical. The receiving side
        // resolves the validated relative path beneath its own library.
        val serviceFiles = File(fixture, "service-files").apply { mkdir() }
        val serviceRom = File(serviceFiles, relative).apply {
            parentFile.mkdirs()
            writeBytes(rom.readBytes())
        }
        check(runCatching { gameLibraryFile(serviceFiles, rom.path) }.isFailure)
        val handoff = gameLibraryRelative(alias, File(alias, relative).path)
        check(gameLibraryFromRelative(serviceFiles, handoff) == serviceRom)
        check(runCatching { gameLibraryFromRelative(serviceFiles, "../library/$handoff") }.isFailure)
        fun rejected(path: String) {
            check(runCatching { gameLibraryFile(alias, path) }.isFailure) { "Accepted $path" }
        }
        rejected(File(real, "library/${"a".repeat(32)}/2338/content/Minish Cap.gba").path)
        rejected(File(rom.parentFile, "../content/Minish Cap.gba").path)
        rejected(File(rom.parentFile, "Missing.gba").path)
        val link = File(rom.parentFile, "Linked.gba")
        Files.createSymbolicLink(link.toPath(), rom.toPath()); rejected(link.path)
        val directory = File(rom.parentFile, "linked-directory")
        Files.createSymbolicLink(directory.toPath(), rom.parentFile.toPath())
        rejected(File(directory, rom.name).path)
        directory.delete(); link.delete(); alias.delete()
        check(rom.readBytes().contentEquals(byteArrayOf(1, 2)))
        println("PASS: actual Broomm library and trusted framework alias; old/foreign, traversal, missing and linked paths rejected")
    } finally { fixture.deleteRecursively() }
}
