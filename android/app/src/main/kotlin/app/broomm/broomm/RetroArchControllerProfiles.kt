package app.broomm.broomm

import java.io.File
import java.util.Locale
import java.util.zip.CRC32
import java.util.zip.ZipFile

/** The installed frontend's Android autoconfig assets, scoped to flat config files. */
internal object RetroArchControllerProfiles {
    private const val prefix = "assets/autoconfig/android/"
    private const val maxProfile = 16 * 1024

    fun read(apk: File, live: () -> Unit): Map<String, ByteArray> = ZipFile(apk).use { zip ->
        val profiles = zip.entries().asSequence()
            .filter { !it.isDirectory && it.name.startsWith(prefix) }
            .take(513).toList()
        require(profiles.size in 1..512) { "RetroArch's APK has no supported Android controller profiles." }
        val names = HashSet<String>()
        var total = 0L
        profiles.associate { entry ->
            live()
            val name = entry.name.removePrefix(prefix)
            require(name.length in 5..200 && name.endsWith(".cfg") &&
                name.none { it == '/' || it == '\\' || it.isISOControl() } &&
                names.add(name.lowercase(Locale.ROOT)) && entry.size in 1..maxProfile.toLong()) {
                "RetroArch's APK contains an invalid controller profile."
            }
            total += entry.size
            require(total <= 1024 * 1024)
            val bytes = zip.getInputStream(entry).use { input ->
                val output = ByteArray(entry.size.toInt())
                var offset = 0
                while (offset < output.size) {
                    live()
                    val count = input.read(output, offset, output.size - offset)
                    require(count > 0)
                    offset += count
                }
                require(input.read() == -1)
                output
            }
            require(CRC32().apply { update(bytes) }.value == entry.crc) {
                "A bundled RetroArch controller profile failed verification."
            }
            name to bytes
        }
    }
}
