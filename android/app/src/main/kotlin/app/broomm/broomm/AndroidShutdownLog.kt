package app.broomm.broomm

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** Bounded logger_entry_v4 decoder. Native header identity prevents other
 * processes from supplying shutdown evidence. */
internal object AndroidShutdownLog {
    const val MAX_BYTES = 512 * 1024
    fun read(bytes: ByteArray, pid: Int, uid: Int, earliest: Long, latest: Long,
             entry: (time: Long, tid: Int, priority: Int, tag: String, text: String) -> Unit) {
        require(bytes.size <= MAX_BYTES && pid > 0 && uid in 10000..99999 && earliest > 0 && latest >= earliest)
        val input = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        var previous = earliest
        while (input.hasRemaining()) {
            require(input.remaining() >= 28) { "Incomplete emulator lifecycle header." }
            val length = input.short.toInt() and 65535
            val header = input.short.toInt() and 65535
            require(header == 28 && length in 3..5120 && input.remaining() >= 24 + length)
            val entryPid = input.int
            val tid = input.int
            val sec = input.int.toLong() and 0xffffffffL
            val nano = input.int.toLong() and 0xffffffffL
            val buffer = input.int
            val owner = input.int
            require(entryPid == pid && owner == uid && buffer == 0 && tid > 0 && nano < 1_000_000_000L)
            val payload = ByteArray(length); input.get(payload)
            require(payload[0].toInt() in 2..7 && payload.last() == 0.toByte())
            val time = sec * 1000 + nano / 1_000_000
            // A PID can have older entries from a previous incarnation. Only
            // this kernel process's lifetime can supply evidence.
            if (time < earliest) continue
            require(time in previous..latest) { "Emulator lifecycle clock changed." }
            previous = time
            val endTag = payload.indexOf(0, 1)
            require(endTag in 2 until payload.lastIndex)
            val tag = String(payload, 1, endTag - 1, Charsets.UTF_8)
            val text = String(payload, endTag + 1, payload.size - endTag - 2, Charsets.UTF_8)
            entry(time, tid, payload[0].toInt(), tag, text)
        }
    }

    private fun ByteArray.indexOf(value: Byte, from: Int): Int {
        for (i in from until size) if (this[i] == value) return i
        return -1
    }
}
