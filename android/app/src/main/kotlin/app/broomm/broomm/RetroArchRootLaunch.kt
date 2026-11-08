package app.broomm.broomm

import java.io.File

/** Validate the exact private cartridge/configuration pair before Android
 * handoff. A prepared ZIP keeps its outer save/state stem. */
internal fun validateRootRetroArchLaunch(core: String, pkg: String, nativeData: String,
    nativeRom: String, config: String?, content: String, selected: String) {
    require(core in setOf("mgba", "snes9x", "gambatte", "stella", "mednafen_pce_fast", "genesis_plus_gx", "picodrive", "mupen64plus_next", "mesen", "virtualjaguar", "mednafen_lynx", "fbneo", "opera") && config != null &&
        pkg in setOf("com.retroarch.aarch64", "com.retroarch", "com.retroarch.ra32"))
    val root = listOf(nativeData, "/data/data/$pkg", "/data/user/0/$pkg")
        .firstOrNull { nativeRom.startsWith("$it/files/Broomm/") }
        ?: error("RetroArch ROM is outside RetroArch's private session")
    val parts = RootSaveFiles.romPath(nativeRom.removePrefix("$root/"), core)
    require(when (core) {
        "opera" -> setOf("chd", "iso", "bin").contains(parts[3].substringAfterLast('.').lowercase())
        "mgba" -> parts[3].endsWith(".gba", true)
        "snes9x" -> parts[3].endsWith(".sfc", true) || parts[3].endsWith(".smc", true)
        "stella" -> setOf("a26", "bin").contains(parts[3].substringAfterLast('.').lowercase())
        "mednafen_pce_fast" -> parts[3].endsWith(".pce", true)
        "genesis_plus_gx" -> setOf("md", "gen", "smd", "bin", "sms", "sg", "gg").contains(parts[3].substringAfterLast('.').lowercase())
        "picodrive" -> setOf("32x", "bin", "gen", "smd", "md").contains(parts[3].substringAfterLast('.').lowercase())
        "virtualjaguar" -> setOf("j64", "jag", "rom", "abs", "cof", "bin", "prg").contains(parts[3].substringAfterLast('.').lowercase())
        "mednafen_lynx" -> setOf("lnx", "lyx", "bll", "o").contains(parts[3].substringAfterLast('.').lowercase())
        "fbneo" -> Regex("[A-Za-z0-9_]{1,64}\\.[zZ][iI][pP]").matches(parts[3])
        "mesen" -> setOf("nes", "unf", "unif").contains(parts[3].substringAfterLast('.').lowercase())
        "mupen64plus_next" -> setOf("z64", "v64", "n64").contains(parts[3].substringAfterLast('.').lowercase())
        else -> setOf("gb", "gbc", "dmg").contains(parts[3].substringAfterLast('.').lowercase())
    })
    val sourceName = File(selected).name
    val sameContent = parts[3] == sourceName || sourceName.endsWith(".zip", true) &&
        parts[3].substringBeforeLast('.') == sourceName.substringBeforeLast('.')
    require(parts[1] == File(content).parentFile!!.name && sameContent &&
        config.substringAfter("/files/Broomm/").substringBeforeLast('/') == "${parts[0]}/${parts[1]}")
}
