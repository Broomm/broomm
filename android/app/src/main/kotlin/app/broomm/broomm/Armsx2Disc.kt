package app.broomm.broomm

import java.io.File
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.Locale

internal data class Armsx2Disc(val serial: String, val crc: String) {
    val statePrefix get() = "$serial ($crc)."
    val statePattern get() = "^(?:[0-9]{2}\\.p2s(?:\\.backup)?|resume\\.p2s|autosave(?:\\.[2-5])?\\.p2s)$"

    fun acceptsState(name: String) = name.startsWith(statePrefix) &&
        Regex(statePattern).matches(name.removePrefix(statePrefix))
}

private const val SECTOR_BYTES = 2048
private val SERIAL = Regex("([A-Z]{4})_([0-9]{3})\\.([0-9]{2})")
private val BOOT = Regex("(?im)^\\s*BOOT2\\s*=\\s*cdrom0:[\\\\/]([^\\r\\n]+?)\\s*$")

internal fun readArmsx2Disc(file: File, live: () -> Unit): Armsx2Disc =
    RandomAccessFile(file, "r").use { input ->
        val size = input.length()
        require(size in 17L * SECTOR_BYTES..(9L * 1024 * 1024 * 1024)) {
            "The PS2 image is outside the supported disc size."
        }
        val layouts = listOf(2048 to 0, 2352 to 16, 2352 to 24)
        val (stride, offset) = layouts.singleOrNull { (stride, offset) ->
            size >= 17L * stride && size % stride == 0L && isPrimary(readIsoSector(input, 16, stride, offset))
        } ?: error("Use a self-contained PS2 disc image with a supported ISO9660 layout.")
        readArmsx2Iso(size / stride, live) { index -> readIsoSector(input, index, stride, offset) }
    }

private fun readIsoSector(input: RandomAccessFile, index: Long, stride: Int, offset: Int): ByteArray {
    input.seek(index * stride + offset)
    return ByteArray(SECTOR_BYTES).also { input.readFully(it) }
}

internal fun isPrimary(bytes: ByteArray) = bytes.size == SECTOR_BYTES && bytes[0] == 1.toByte() &&
    String(bytes, 1, 5, Charsets.US_ASCII) == "CD001" && bytes[6] == 1.toByte()

internal fun readArmsx2Iso(sectors: Long, live: () -> Unit, read: (Long) -> ByteArray): Armsx2Disc {
    fun sector(index: Long): ByteArray {
        live()
        require(index in 0 until sectors) { "PS2 disc extent is out of range." }
        return read(index).also { require(it.size == SECTOR_BYTES) }
    }
    val primary = sector(16)
    require(isPrimary(primary) && dualNumber(primary, 128, 2) == SECTOR_BYTES.toLong()) {
        "Invalid PS2 ISO9660 volume."
    }
    val volume = dualNumber(primary, 80, 4)
    require(volume in 17..sectors)
    fun extent(entry: IsoEntry, max: Int): ByteArray {
        require(entry.size in 1..max.toLong()) { "PS2 disc metadata exceeds its supported size." }
        val blocks = (entry.size + SECTOR_BYTES - 1) / SECTOR_BYTES
        require(entry.sector >= 17 && entry.sector + blocks <= volume) { "Invalid PS2 disc extent." }
        val result = ByteArray(entry.size.toInt())
        for (block in 0 until blocks) {
            val offset = (block * SECTOR_BYTES).toInt()
            sector(entry.sector + block).copyInto(result, offset, 0, minOf(SECTOR_BYTES, result.size - offset))
        }
        return result
    }
    fun child(parent: IsoEntry, name: String, directory: Boolean): IsoEntry {
        require(parent.directory)
        val records = extent(parent, 1024 * 1024)
        var match: IsoEntry? = null
        var index = 0
        while (index < records.size) {
            val length = records[index].toInt() and 255
            if (length == 0) {
                index = (index / SECTOR_BYTES + 1) * SECTOR_BYTES
                continue
            }
            val entry = isoEntry(records, index)
            if (entry.name.equals(name, ignoreCase = true)) {
                require(match == null && entry.directory == directory) { "Ambiguous PS2 disc path." }
                match = entry
            }
            index += length
        }
        return match ?: error("The PS2 disc is missing its boot metadata.")
    }
    val root = isoEntry(primary, 156)
    val cnf = extent(child(root, "SYSTEM.CNF", false), 8192).toString(Charsets.US_ASCII)
    val boot = BOOT.findAll(cnf).toList().singleOrNull()?.groupValues?.get(1)
        ?.trim()?.replace('\\', '/')?.split('/') ?: error("This PS2 disc has no unique BOOT2 entry.")
    require(boot.size in 1..8 && boot.all { Regex("[A-Za-z0-9_.-]{1,64}(?:;1)?").matches(it) && it !in setOf(".", "..") })
    val executable = boot.last().removeSuffix(";1").uppercase(Locale.ROOT)
    val serial = SERIAL.matchEntire(executable) ?: error("This PS2 boot executable has no standard disc serial.")
    var directory = root
    for (component in boot.dropLast(1)) directory = child(directory, component, true)
    val elf = extent(child(directory, executable, false), 32 * 1024 * 1024)
    require(elf.size >= 52 && elf[0] == 0x7f.toByte() && String(elf, 1, 3, Charsets.US_ASCII) == "ELF" &&
        elf[4] == 1.toByte() && elf[5] == 1.toByte()) { "Invalid PS2 boot executable." }
    val words = ByteBuffer.wrap(elf).order(ByteOrder.LITTLE_ENDIAN)
    var crc = 0
    while (words.remaining() >= 4) crc = crc xor words.int
    require(crc != 0) { "The PS2 boot executable has no supported state identity." }
    return Armsx2Disc("${serial.groupValues[1]}-${serial.groupValues[2]}${serial.groupValues[3]}",
        crc.toUInt().toString(16).padStart(8, '0').uppercase(Locale.ROOT))
}

private data class IsoEntry(val name: String, val sector: Long, val size: Long, val directory: Boolean)

private fun isoEntry(bytes: ByteArray, offset: Int): IsoEntry {
    val length = bytes[offset].toInt() and 255
    require(length >= 34 && offset + length <= bytes.size && offset % SECTOR_BYTES + length <= SECTOR_BYTES)
    val nameBytes = bytes[offset + 32].toInt() and 255
    val flags = bytes[offset + 25].toInt() and 255
    require(nameBytes in 1..length - 33 && bytes[offset + 1] == 0.toByte() &&
        bytes[offset + 26] == 0.toByte() && bytes[offset + 27] == 0.toByte())
    val name = String(bytes, offset + 33, nameBytes, Charsets.US_ASCII).removeSuffix(";1")
    // Multi-extent files cannot be represented as a single boot extent.
    require(flags and 128 == 0)
    return IsoEntry(name, dualNumber(bytes, offset + 2, 4), dualNumber(bytes, offset + 10, 4), flags and 2 != 0)
}

private fun dualNumber(bytes: ByteArray, offset: Int, size: Int): Long {
    var little = 0L
    var big = 0L
    for (i in 0 until size) {
        little = little or ((bytes[offset + i].toLong() and 255) shl (8 * i))
        big = (big shl 8) or (bytes[offset + size + i].toLong() and 255)
    }
    require(little == big) { "Conflicting PS2 ISO9660 metadata." }
    return little
}
