import app.broomm.broomm.gameLibraryFile
import app.broomm.broomm.gameLibraryFromRelative
import app.broomm.broomm.gameLibraryRelative
import app.broomm.broomm.preparedCartridgeFile
import app.broomm.broomm.preparedCartridgeFromRelative
import app.broomm.broomm.preparedCartridgeRelative
import app.broomm.broomm.GameGrantPath
import app.broomm.broomm.gameGrantPath
import app.broomm.broomm.grantedGameFile
import app.broomm.broomm.duckStationDocumentLaunch
import app.broomm.broomm.duckStationGamePath
import app.broomm.broomm.duckStationDocumentToken
import app.broomm.broomm.sharedSaveSnapshotFile
import java.io.File
import java.nio.file.Files

fun main() {
    val token = "a".repeat(32)
    val parts = listOf("Discs", "Mega Man – X4 #1.chd")
    val legacy = gameGrantPath(listOf("game", token) + parts)
    val document = gameGrantPath(listOf("document", "$token:${parts.joinToString("/")}"))
    check(legacy == document && document == GameGrantPath(token, parts))
    check(duckStationGamePath("app.broomm.broomm.games.documents", document) ==
        "/android_content/app.broomm.broomm.games.documents/document@$token/Discs/Mega Man – X4 #1.chd")
    check(runCatching { duckStationGamePath("app.broomm.broomm.games", document) }.isFailure)
    check(duckStationDocumentToken(token) == token)
    for (invalid in listOf(null, "", "A".repeat(32), "a".repeat(31), "a".repeat(33), "a".repeat(31) + "/"))
        check(runCatching { duckStationDocumentToken(invalid) }.isFailure)
    for (bad in listOf(
        emptyList(), listOf("document", "$token:"), listOf("document", "foreign:Game.chd"),
        listOf("document", "$token:../Game.chd"), listOf("document", "$token:dir//Game.chd"),
        listOf("document", "$token:dir\\Game.chd"), listOf("document", "$token:Game\u0000.chd"),
        listOf("document", "$token:Game\n.chd"), listOf("document", "$token:${"x".repeat(4097)}"),
        listOf("document", "$token:Game.chd", "extra"), listOf("document", "$token:dir/./Game.chd"),
    )) check(runCatching { gameGrantPath(bad) }.isFailure)
    check(runCatching { duckStationGamePath("foreign/path.games", document) }.isFailure)
    val signer = "a6357957d296b3b03edeb62da317cb347ecde63b6577977ffcbfe0d9a6975450"
    check(duckStationDocumentLaunch(12126, "0.1-12693-gcc4a0d678", signer))
    check(!duckStationDocumentLaunch(5432, "older", "unknown"))
    check(runCatching { duckStationDocumentLaunch(12126, "changed", signer) }.isFailure)
    check(runCatching { duckStationDocumentLaunch(12126, "0.1-12693-gcc4a0d678", "f".repeat(64)) }.isFailure)
    println("PASS: legacy/document capabilities correspond; Unicode/space names preserved; invalid identities, traversal, control characters and oversized aliases refused; reviewed DuckStation contract is signer/version bound")
    val fixture = Files.createTempDirectory("broomm-game-library-").toFile().canonicalFile
    try {
        val real = File(fixture, "files").apply { mkdir() }
        val alias = File(fixture, "framework-files")
        Files.createSymbolicLink(alias.toPath(), real.toPath())
        val relative = "broomm/library/${"a".repeat(32)}/2338/content/Minish Cap.gba"
        val rom = File(real, relative).apply { parentFile.mkdirs(); writeBytes(byteArrayOf(1, 2)) }
        check(gameLibraryFile(alias, File(alias, relative).path) == rom)
        check(gameLibraryFile(alias, rom.path) == rom)
        val granted = GameGrantPath(token, listOf(rom.name))
        val content = rom.parentFile.path
        check(grantedGameFile(alias, granted, content, listOf(rom.path)) == rom)
        val sidecar = File(rom.parentFile, "Minish Cap.sbi").apply { writeBytes(byteArrayOf(9)) }
        val sibling = GameGrantPath(token, listOf(sidecar.name))
        // Missing/ungranted siblings must not resolve to the main image.
        check(runCatching { grantedGameFile(alias, sibling, content, listOf(rom.path)) }.isFailure)
        check(grantedGameFile(alias, sibling, content, listOf(rom.path, sidecar.path)).readBytes().contentEquals(byteArrayOf(9)))
        sidecar.delete()
        check(runCatching { grantedGameFile(alias, sibling, content, listOf(rom.path, sidecar.path)) }.isFailure)
        println("PASS: exact ROM and separately granted sidecar resolve independently; ungranted and missing sidecars never substitute the ROM")
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
        val snapshot = File(real, "broomm/android/shared-session/$transaction/captures/slot.cst")
        check(snapshot.parentFile.mkdirs())
        val logicalSnapshot = File(alias, snapshot.relativeTo(real).path)
        check(sharedSaveSnapshotFile(alias, logicalSnapshot.path) == snapshot && !snapshot.exists())
        val recovery = File(real, "broomm/android/mmj-session/$transaction/original/main")
        recovery.parentFile.mkdirs()
        recovery.writeBytes(byteArrayOf(7))
        check(sharedSaveSnapshotFile(alias, recovery.path).readBytes().contentEquals(byteArrayOf(7)))
        val wrongBase = File(real, "android/shared-session/$transaction/main")
        wrongBase.parentFile.mkdirs()
        wrongBase.writeBytes(byteArrayOf(8))
        check(runCatching { sharedSaveSnapshotFile(alias, wrongBase.path) }.isFailure)
        check(runCatching { sharedSaveSnapshotFile(alias, "${snapshot.parent}/../captures/slot.cst") }.isFailure)
        val linkedSnapshot = File(snapshot.parentFile, "linked")
        Files.createSymbolicLink(linkedSnapshot.toPath(), recovery.toPath())
        check(runCatching { sharedSaveSnapshotFile(alias, linkedSnapshot.path) }.isFailure)
        linkedSnapshot.delete()
        println("PASS: shared capture and legacy MMJ recovery resolve inside the Broomm data root; sibling, traversal and linked files refused")
        directory.delete(); link.delete(); alias.delete()
        check(rom.readBytes().contentEquals(byteArrayOf(1, 2)))
        println("PASS: actual Broomm library and trusted framework alias; old/foreign, traversal, missing and linked paths rejected")
    } finally { fixture.deleteRecursively() }
}
