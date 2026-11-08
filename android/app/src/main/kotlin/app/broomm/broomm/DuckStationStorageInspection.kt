package app.broomm.broomm

/** App-private metadata only: this does not locate selected save folders or grant writes. */
internal object DuckStationStorageInspection {
    const val PACKAGE = "com.github.stenzek.duckstation"

    // Appended to the fixed root inspection command; package/path data stays on stdin.
    // Do not read settings contents: they can contain unrelated account credentials.
    val SCRIPT = """
        pkg="${'$'}{root##*/}"
        files="/storage/emulated/0/Android/data/${'$'}pkg/files"
        mirror="/data/media/0/Android/data/${'$'}pkg/files"
        [ "${'$'}(/system/bin/readlink -f "${'$'}files")" = "${'$'}files" ] || exit 66
        [ "${'$'}(/system/bin/readlink -f "${'$'}mirror")" = "${'$'}mirror" ] || exit 66
        [ -d "${'$'}files" ] && [ -d "${'$'}mirror" ] || exit 66
        storage_before="${'$'}(/system/bin/stat -c '%u %g %a %C %d %i' "${'$'}files")" || exit 66
        [ "${'$'}(/system/bin/stat -c '%u %g %a %C %d %i' "${'$'}mirror")" = "${'$'}storage_before" ] || exit 66
        settings="${'$'}files/settings.ini"
        [ "${'$'}(/system/bin/readlink -f "${'$'}settings")" = "${'$'}settings" ] || exit 66
        [ -f "${'$'}settings" ] && [ ! -L "${'$'}settings" ] || exit 66
        settings_before="${'$'}(/system/bin/stat -c '%u %g %a %C %s %h %d %i' "${'$'}settings")" || exit 66
        settings_identity="${'$'}(/system/bin/stat -c '%d %i %s %Y %Z' "${'$'}settings")" || exit 66
        [ "${'$'}(/system/bin/stat -c '%u %g %a %C %d %i' "${'$'}files")" = "${'$'}storage_before" ] || exit 66
        [ "${'$'}(/system/bin/stat -c '%u %g %a %C %d %i' "${'$'}mirror")" = "${'$'}storage_before" ] || exit 66
        [ "${'$'}(/system/bin/readlink -f "${'$'}settings")" = "${'$'}settings" ] || exit 66
        [ -f "${'$'}settings" ] && [ ! -L "${'$'}settings" ] || exit 66
        [ "${'$'}(/system/bin/stat -c '%u %g %a %C %s %h %d %i' "${'$'}settings")" = "${'$'}settings_before" ] || exit 66
        [ "${'$'}(/system/bin/stat -c '%d %i %s %Y %Z' "${'$'}settings")" = "${'$'}settings_identity" ] || exit 66
        printf 'BROOMM_DUCKSTATION_STORAGE_V1\n%s\n%s\n%s\n' "${'$'}files" "${'$'}storage_before" "${'$'}settings_before"
    """.trimIndent()

    fun parse(output: String, roots: Set<String>, uid: Int): Map<String, Any> {
        require(uid in 10000..99999 && roots.all { it == "/data/user/0/$PACKAGE" || it == "/data/data/$PACKAGE" })
        val lines = output.split('\n')
        require(lines.size == 9 && lines[4] == "BROOMM_DUCKSTATION_STORAGE_V1" && lines[8].isEmpty()) {
            "Incomplete DuckStation app-files observation; nothing was connected."
        }
        val base = RootInspectionCommand.parse(lines.take(4).joinToString("\n") + "\n", roots, uid)
        val appLabel = base.getValue("label") as String
        require(appLabel.startsWith("u:object_r:app_data_file:s0"))
        val mediaLabel = appLabel.replace("u:object_r:app_data_file:", "u:object_r:media_rw_data_file:")
        val storage = lines[6].split(' ')
        require(lines[5] == "/storage/emulated/0/Android/data/$PACKAGE/files" &&
            storage.size == 6 && storage[0].toIntOrNull() == uid &&
            storage[1].toIntOrNull()?.let { it >= 0 } == true &&
            Regex("[0-7]{3,4}").matches(storage[2]) &&
            (storage[2].toInt(8) and 0x1c7) == 0x1c0 && storage[3] == mediaLabel &&
            storage[4].toLongOrNull()?.let { it > 0 } == true &&
            storage[5].toLongOrNull()?.let { it > 0 } == true) {
            "DuckStation's app-private mount correspondence could not be verified."
        }
        val settings = lines[7].split(' ')
        require(settings.size == 8 && settings[0].toIntOrNull() == uid && settings[1] == storage[1] &&
            Regex("[0-7]{3}").matches(settings[2]) &&
            (settings[2].toInt(8) and 0x187) == 0x180 && settings[3] == mediaLabel &&
            settings[4].toLongOrNull()?.let { it in 1..1024 * 1024 } == true && settings[5] == "1" &&
            settings[6] == storage[4] && settings[7].toLongOrNull()?.let { it > 0 } == true) {
            "DuckStation's initialized settings-file metadata could not be verified."
        }
        return base + mapOf("appFiles" to mapOf(
            "path" to lines[5], "gid" to storage[1].toInt(), "mode" to storage[2], "label" to mediaLabel,
            "device" to storage[4].toLong(), "inode" to storage[5].toLong(), "settingsBytes" to settings[4].toLong(),
        ))
    }
}
