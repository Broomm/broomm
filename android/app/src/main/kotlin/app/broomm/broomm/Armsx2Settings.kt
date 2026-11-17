package app.broomm.broomm

import android.util.Xml
import org.json.JSONObject
import org.xmlpull.v1.XmlPullParser
import java.util.Locale
import java.io.File

internal fun requireArmsx2SharedSetup(internal: RootSaveFiles, folder: File, visible: String) {
    val config = File(folder, "PCSX2-Android.ini")
    require(config.canonicalPath == config.path && config.isFile && config.length() in 1..1024L * 1024) {
        "Finish ARMSX2’s first-run setup in $visible and close it."
    }
    val relative = "shared_prefs/ARMSX2.xml"
    require(!internal.present(internal.path("$relative.bak"))) {
        "Open ARMSX2 once to finish recovering its settings."
    }
    val prefs = internal.bytes(internal.existing(relative), 256 * 1024)
    val parser = Xml.newPullParser()
    parser.setFeature(XmlPullParser.FEATURE_PROCESS_DOCDECL, false)
    parser.setInput(prefs.inputStream(), "UTF-8")
    require(parser.nextTag() == XmlPullParser.START_TAG && parser.name == "map")
    var configured: String? = null
    var complete = false
    val seen = mutableSetOf<String>()
    while (parser.next() != XmlPullParser.END_DOCUMENT) {
        if (parser.eventType != XmlPullParser.START_TAG || parser.depth != 2) continue
        val key = parser.getAttributeValue(null, "name") ?: continue
        if (key !in setOf("systemDir", "setupComplete", "memcard.perGame")) continue
        require(seen.add(key)) { "ARMSX2 has conflicting preferences." }
        when (key) {
            "systemDir" -> {
                require(configured == null && parser.name == "string")
                configured = parser.nextText()
            }
            "setupComplete" -> complete = parser.name == "boolean" && parser.getAttributeValue(null, "value") == "true"
            "memcard.perGame" -> require(parser.name == "boolean" && parser.getAttributeValue(null, "value") == "false") {
                "Turn off per-game memory cards in ARMSX2 before continuing."
            }
        }
    }
    require(complete && configured == visible) {
        "Finish ARMSX2’s first-run setup using $visible as its App Data Folder."
    }
}

private const val DEFAULTS = "Use ARMSX2’s default app data folder, both standard memory cards, and turn off per-game memory cards. Existing files were kept."

internal fun requireArmsx2DefaultSettings(
    root: String, ini: ByteArray, prefs: ByteArray?, backup: ByteArray?, disc: Armsx2Disc?,
) {
    requireArmsx2IniDefaults(root, ini)
    if (prefs != null) {
        val parser = Xml.newPullParser()
        parser.setFeature(XmlPullParser.FEATURE_PROCESS_DOCDECL, false)
        parser.setInput(prefs.inputStream(), "UTF-8")
        require(parser.nextTag() == XmlPullParser.START_TAG && parser.name == "map")
        val observed = mutableSetOf<String>()
        while (parser.next() != XmlPullParser.END_DOCUMENT) {
            if (parser.eventType != XmlPullParser.START_TAG || parser.depth != 2) continue
            val key = parser.getAttributeValue(null, "name") ?: continue
            require(observed.add(key)) { "ARMSX2 has conflicting preferences." }
            when (key) {
                "systemDir" -> require(parser.name == "string" && parser.nextText() == root) { DEFAULTS }
                "memcard.perGame" -> require(parser.name == "boolean" && parser.getAttributeValue(null, "value") == "false") { DEFAULTS }
                "config.global", disc?.let { "config.game.${it.serial}" } -> {
                    require(parser.name == "string") { DEFAULTS }
                    requireDefaultCards(JSONObject(parser.nextText()))
                }
            }
        }
    }
    // First-run reconciliation can seed SharedPreferences from this mirror.
    if (backup != null) {
        val stored = JSONObject(backup.toString(Charsets.UTF_8))
        if (stored.has("global")) requireDefaultCards(stored.getJSONObject("global"))
        if (disc != null && stored.has("games")) {
            val games = stored.getJSONObject("games")
            if (games.has(disc.serial)) requireDefaultCards(games.getJSONObject(disc.serial))
        }
    }
}

private fun requireDefaultCards(json: JSONObject) {
    for (slot in 1..2) {
        val enabled = "memoryCardSlot${slot}Enabled"
        val name = "memoryCardSlot${slot}Filename"
        require((!json.has(enabled) || json.get(enabled) == true) &&
            (!json.has(name) || json.get(name) in setOf("", "mcd00$slot.ps2"))) { DEFAULTS }
    }
}

internal fun requireArmsx2IniDefaults(root: String, ini: ByteArray) {
    val relevant = mutableMapOf<String, String>()
    var section = ""
    for (line in ini.toString(Charsets.UTF_8).removePrefix("\uFEFF").lineSequence()) {
        val text = line.trim()
        if (text.startsWith('[') && text.endsWith(']')) {
            section = text.substring(1, text.length - 1).trim().lowercase(Locale.ROOT)
            continue
        }
        if (text.startsWith('#') || text.startsWith(';') || '=' !in text) continue
        val key = text.substringBefore('=').trim().lowercase(Locale.ROOT)
        val name = "$section/$key"
        val value = text.substringAfter('=').trim().removeSurrounding("\"")
        val folder = when (name) {
            "folders/memorycards" -> "memcards"
            "folders/savestates" -> "sstates"
            "folders/gamesettings" -> "gamesettings"
            else -> null
        }
        val valid = when {
            folder != null -> value in setOf(folder, "$root/$folder")
            name == "memorycards/slot1_filename" -> value == "mcd001.ps2"
            name == "memorycards/slot2_filename" -> value == "mcd002.ps2"
            name in setOf("memorycards/slot1_enable", "memorycards/slot2_enable") -> value.lowercase(Locale.ROOT) in setOf("true", "1")
            name.matches(Regex("memorycards/slot[3-8]_enable")) ||
                name in setOf("emucore/multitapport0_enabled", "emucore/multitapport1_enabled") -> value.lowercase(Locale.ROOT) in setOf("false", "0")
            else -> continue
        }
        require(valid && relevant.put(name, value)?.let { it == value } != false) { DEFAULTS }
    }
}
