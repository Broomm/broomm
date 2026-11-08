package app.broomm.broomm

/** Read-only discovery of PPSSPP's selected memory stick, never a save grant.
 *
 * PPSSPP's "App Private Data" choice is getExternalFilesDir(), not filesDir.
 * Only its exact user-0 app-private location is inspected. A SAF/public choice
 * is reported without following it or disclosing an arbitrary stored URI.
 */
internal object PpssppStorageInspection {
    val packages = setOf("org.ppsspp.ppsspp", "org.ppsspp.ppssppgold")

    // Appended to the existing root metadata command. All tools are read-only;
    // no path or shell fragment is interpolated from application metadata.
    val SCRIPT = """
        pointer="${'$'}real/files/memstick_dir.txt"
        [ "${'$'}(/system/bin/readlink -f "${'$'}pointer")" = "${'$'}pointer" ] || exit 65
        [ -f "${'$'}pointer" ] && [ ! -L "${'$'}pointer" ] || exit 65
        pointer_before="${'$'}(/system/bin/stat -c '%u %g %a %C %s %h' "${'$'}pointer")" || exit 65
        pointer_identity="${'$'}(/system/bin/stat -c '%d %i %s %Y %Z' "${'$'}pointer")" || exit 65
        size="${'$'}(/system/bin/stat -c '%s' "${'$'}pointer")" || exit 65
        [ "${'$'}size" -ge 1 ] && [ "${'$'}size" -le 1024 ] || exit 65
        selected="${'$'}(/system/bin/head -c 1025 "${'$'}pointer"; printf '.')" || exit 65
        selected="${'$'}{selected%.}"
        [ "${'$'}(printf '%s' "${'$'}selected" | /system/bin/wc -c)" -eq "${'$'}size" ] || exit 65
        [ "${'$'}(/system/bin/stat -c '%u %g %a %C %s %h' "${'$'}pointer")" = "${'$'}pointer_before" ] || exit 65
        [ "${'$'}(/system/bin/stat -c '%d %i %s %Y %Z' "${'$'}pointer")" = "${'$'}pointer_identity" ] || exit 65
        again="${'$'}(/system/bin/head -c 1025 "${'$'}pointer"; printf '.')" || exit 65
        [ "${'$'}again" = "${'$'}selected." ] || exit 65
        pkg="${'$'}{root##*/}"
        expected="/storage/emulated/0/Android/data/${'$'}pkg/files"
        if [ "${'$'}selected" != "${'$'}expected" ]; then
            printf 'BROOMM_PSP_STORAGE_V1\nother\n%s\n' "${'$'}pointer_before"
            exit 0
        fi
        mirror="/data/media/0/Android/data/${'$'}pkg/files"
        [ "${'$'}(/system/bin/readlink -f "${'$'}selected")" = "${'$'}selected" ] || exit 65
        [ "${'$'}(/system/bin/readlink -f "${'$'}mirror")" = "${'$'}mirror" ] || exit 65
        [ -d "${'$'}selected" ] && [ -d "${'$'}mirror" ] || exit 65
        storage_before="${'$'}(/system/bin/stat -c '%u %g %a %C %d %i' "${'$'}selected")" || exit 65
        [ "${'$'}(/system/bin/stat -c '%u %g %a %C %d %i' "${'$'}mirror")" = "${'$'}storage_before" ] || exit 65
        config="${'$'}selected/PSP/SYSTEM/ppsspp.ini"
        [ "${'$'}(/system/bin/readlink -f "${'$'}config")" = "${'$'}config" ] || exit 65
        [ -f "${'$'}config" ] && [ ! -L "${'$'}config" ] || exit 65
        config_before="${'$'}(/system/bin/stat -c '%u %g %a %C %s %h' "${'$'}config")" || exit 65
        [ "${'$'}(/system/bin/stat -c '%u %g %a %C %d %i' "${'$'}selected")" = "${'$'}storage_before" ] || exit 65
        [ "${'$'}(/system/bin/stat -c '%u %g %a %C %d %i' "${'$'}mirror")" = "${'$'}storage_before" ] || exit 65
        [ "${'$'}(/system/bin/stat -c '%u %g %a %C %s %h' "${'$'}pointer")" = "${'$'}pointer_before" ] || exit 65
        [ "${'$'}(/system/bin/stat -c '%d %i %s %Y %Z' "${'$'}pointer")" = "${'$'}pointer_identity" ] || exit 65
        again="${'$'}(/system/bin/head -c 1025 "${'$'}pointer"; printf '.')" || exit 65
        [ "${'$'}again" = "${'$'}selected." ] || exit 65
        [ "${'$'}(/system/bin/stat -c '%u %g %a %C %s %h' "${'$'}config")" = "${'$'}config_before" ] || exit 65
        printf 'BROOMM_PSP_STORAGE_V1\nprivate\n%s\n%s\n%s\n%s\n' \
            "${'$'}selected" "${'$'}storage_before" "${'$'}pointer_before" "${'$'}config_before"
    """.trimIndent()

    fun parse(output: String, roots: Set<String>, uid: Int, pkg: String): Map<String, Any> {
        require(pkg in packages && uid in 10000..99999)
        val lines = output.split('\n')
        require(lines.size >= 8)
        val base = RootInspectionCommand.parse(lines.take(4).joinToString("\n") + "\n", roots, uid)
        require(lines[4] == "BROOMM_PSP_STORAGE_V1" && lines.last().isEmpty()) {
            "Incomplete PPSSPP storage observation; nothing was connected."
        }
        val appLabel = base.getValue("label") as String
        require(appLabel.startsWith("u:object_r:app_data_file:s0"))
        fun file(line: String, label: String, max: Long): List<String> {
            val fields = line.split(' ')
            require(fields.size == 6 && fields[0].toIntOrNull() == uid &&
                fields[1].toIntOrNull()?.let { it >= 0 } == true &&
                Regex("[0-7]{3}").matches(fields[2]) &&
                (fields[2].toInt(8) and 7) == 0 &&
                fields[3] == label && fields[4].toLongOrNull()?.let { it in 1..max } == true &&
                fields[5] == "1") { "PPSSPP storage file identity could not be verified." }
            return fields
        }
        val memory: Map<String, Any> = when (lines[5]) {
            "other" -> {
                require(lines.size == 8)
                file(lines[6], appLabel, 1024)
                mapOf("kind" to "other")
            }
            "private" -> {
                require(lines.size == 11 &&
                    lines[6] == "/storage/emulated/0/Android/data/$pkg/files")
                val fields = lines[7].split(' ')
                val mediaLabel = appLabel.replace("u:object_r:app_data_file:", "u:object_r:media_rw_data_file:")
                require(fields.size == 6 && fields[0].toIntOrNull() == uid &&
                    fields[1].toIntOrNull()?.let { it >= 0 } == true &&
                    Regex("[0-7]{3,4}").matches(fields[2]) &&
                    (fields[2].toInt(8) and 7) == 0 && fields[3] == mediaLabel &&
                    fields[4].toLongOrNull()?.let { it > 0 } == true &&
                    fields[5].toLongOrNull()?.let { it > 0 } == true) {
                    "PPSSPP's app-private mount correspondence could not be verified."
                }
                file(lines[8], appLabel, 1024)
                val config = file(lines[9], mediaLabel, 1024 * 1024)
                require(config[1] == fields[1])
                mapOf("kind" to "private", "path" to lines[6], "gid" to fields[1].toInt(),
                    "mode" to fields[2], "label" to mediaLabel,
                    "device" to fields[4].toLong(), "inode" to fields[5].toLong())
            }
            else -> error("Unknown PPSSPP storage observation.")
        }
        return base + mapOf("memoryStick" to memory)
    }
}
