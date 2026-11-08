import app.broomm.broomm.gameLibraryFile
import app.broomm.broomm.gameLibraryFromRelative
import app.broomm.broomm.gameLibraryRelative
import app.broomm.broomm.preparedCartridgeFile
import app.broomm.broomm.preparedCartridgeFromRelative
import app.broomm.broomm.preparedCartridgeRelative
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
        val transaction = "b".repeat(32)
        val preparedRelative = "broomm/android/shared-session/$transaction/cartridge-Abc123/Sonic.md"
        val prepared = File(real, preparedRelative).apply { parentFile.mkdirs(); writeBytes(byteArrayOf(3, 4)) }
        check(preparedCartridgeFile(alias, File(alias, preparedRelative).path, transaction, prepared.name) == prepared)
        check(runCatching { gameLibraryFile(alias, prepared.path) }.isFailure)
        val preparedHandoff = preparedCartridgeRelative(alias, prepared.path, transaction, prepared.name)
        val servicePrepared = File(serviceFiles, preparedRelative).apply { parentFile.mkdirs(); writeBytes(prepared.readBytes()) }
        check(preparedCartridgeFromRelative(serviceFiles, preparedHandoff, transaction, prepared.name) == servicePrepared)
        check(runCatching { preparedCartridgeFromRelative(serviceFiles, "../$preparedHandoff", transaction, prepared.name) }.isFailure)
        check(runCatching { preparedCartridgeFile(alias, prepared.path, "c".repeat(32), prepared.name) }.isFailure)
        check(runCatching { preparedCartridgeFile(alias, prepared.path, transaction, "Other.md") }.isFailure)
        check(runCatching { preparedCartridgeFile(alias, rom.path, transaction, rom.name) }.isFailure)
        val preparedLink = File(prepared.parentFile, "Linked.md")
        Files.createSymbolicLink(preparedLink.toPath(), prepared.toPath())
        check(runCatching { preparedCartridgeFile(alias, preparedLink.path, transaction, preparedLink.name) }.isFailure)
        preparedLink.delete()
        val nestedPrepared = File(prepared.parentFile, "nested/Sonic.md").apply { parentFile.mkdirs(); writeBytes(byteArrayOf(5)) }
        check(runCatching { preparedCartridgeFile(alias, nestedPrepared.path, transaction, prepared.name) }.isFailure)
        val privateLink = File(prepared.parentFile.parentFile, "cartridge-link")
        Files.createSymbolicLink(privateLink.toPath(), prepared.parentFile.toPath())
        check(runCatching { preparedCartridgeFile(alias, File(privateLink, prepared.name).path, transaction, prepared.name) }.isFailure)
        privateLink.delete()
        check(prepared.readBytes().contentEquals(byteArrayOf(3, 4)))
        println("PASS: private prepared cartridge aliases and service-relative handoff; wrong transaction/name, traversal, nested and linked sources refused")
        directory.delete(); link.delete(); alias.delete()
        check(rom.readBytes().contentEquals(byteArrayOf(1, 2)))
        println("PASS: actual Broomm library and trusted framework alias; old/foreign, traversal, missing and linked paths rejected")
    } finally { fixture.deleteRecursively() }
}
