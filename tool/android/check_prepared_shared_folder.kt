package app.broomm.broomm

import android.os.Bundle
import android.system.Os
import java.io.File

fun main(args: Array<String>) {
    val relative = args.single()
    require(Regex("Broomm/\\.shared-path-test-[a-f0-9]{32}").matches(relative))
    val root = File("/data/media/0", relative)
    check(!root.exists())
    val visible = File("/storage/emulated/0", relative)
    check(!visible.exists())
    check(visible.mkdir())
    try {
        val cards = sharedSetupDirectory("$relative/memcards", create = true)
        val card = File(cards, "Mcd001.ps2").apply { writeBytes(byteArrayOf(1, 2, 3)) }
        val folder = RootPreparedFolder(sharedSetupDirectory(relative), {})
        fun operation(name: String, path: String) = folder.operation(Bundle().apply {
            putString("operation", "preparedshared$name")
            putString("path", path)
        }, 0)
        fun cardName(path: String) = operation("armsx2cardname", path).getString("name")

        val folded = File(cards, "mcd001.ps2")
        if (folded.exists()) {
            check(Os.lstat(folded.path).st_ino == Os.lstat(card.path).st_ino)
            check(cardName("memcards/mcd001.ps2") == card.name)
            check(operation("stat", "memcards/mcd001.ps2").getLong("bytes") == 3L)
            println("PASS: casefolded card resolves to its listed name and remains readable")
        } else {
            check(cardName("memcards/mcd001.ps2") == "mcd001.ps2")
            check(!operation("stat", "memcards/mcd001.ps2").containsKey("id"))
            println("PASS: distinct spelling stays missing on case-sensitive storage")
        }
        check(cardName("memcards/Mcd001.ps2") == card.name)
        check(cardName("memcards/mcd002.ps2") == "mcd002.ps2")

        Os.symlink(card.path, File(cards, "mcd002.ps2").path)
        Os.symlink(cards.path, File(root, "linked-cards").path)
        for (path in listOf("memcards/mcd002.ps2", "linked-cards/Mcd001.ps2")) {
            val failure = runCatching { cardName(path) }.exceptionOrNull()
            check(failure is IllegalArgumentException && failure.message?.contains("Linked") == true)
        }
        check(card.readBytes().contentEquals(byteArrayOf(1, 2, 3)))
        println("PASS: missing cards stay missing and linked files and directories are refused")
    } finally {
        for (link in listOf(File(root, "memcards/mcd002.ps2"), File(root, "linked-cards"))) {
            if (link.exists()) Os.remove(link.path)
        }
        check(root.deleteRecursively())
    }
}
