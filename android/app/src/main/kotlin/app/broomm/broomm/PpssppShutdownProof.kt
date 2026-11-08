package app.broomm.broomm

import java.nio.ByteBuffer
import java.nio.ByteOrder

/** PPSSPP 1.20.4's synchronous Java/native shutdown protocol, not generic log matching. */
internal object PpssppShutdownProof {
    const val MAX_BYTES = 512 * 1024
    private const val FINISH = "Setting shuttingDown = true and calling Finish"
    private const val SHUTDOWN = "in onDestroy, shutting down. Calling NativeApp.shutdown()."
    data class Observation(val created: Long?, val closed: Long?)

    // logcat -B emits logger_entry_v4. UID/PID/TID and buffer identity are
    // checked in the binary header; untrusted text cannot impersonate them.
    // No arbitrary log message is returned to Dart or operational diagnostics.
    fun inspect(bytes: ByteArray, pid: Int, uid: Int, earliest: Long, latest: Long): Observation {
        require(bytes.size <= MAX_BYTES && pid > 0 && uid in 10000..99999 && earliest > 0 && latest >= earliest)
        val input = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        var created: Long? = null
        var closed: Long? = null
        var phase = 0
        var previous = earliest
        while (input.hasRemaining()) {
            require(input.remaining() >= 28) { "Incomplete PPSSPP lifecycle header." }
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
            require(time in previous..latest) { "PPSSPP lifecycle clock changed." }
            previous = time
            val endTag = payload.indexOf(0, 1)
            require(endTag in 2 until payload.lastIndex)
            if (tid != pid || payload[0] != 4.toByte() ||
                String(payload, 1, endTag - 1, Charsets.UTF_8) != "PpssppActivity") continue
            val text = String(payload, endTag + 1, payload.size - endTag - 2, Charsets.UTF_8)
            when {
                text.startsWith("onCreate") || text.startsWith("onResume") ||
                    text.contains("recreate()") || text.startsWith("graphics_restart:") -> {
                    phase = 0; closed = null
                    if (text == "onCreate end") created = time
                }
                text == FINISH -> { phase = 1; closed = null }
                text == SHUTDOWN -> { phase = if (phase == 1) 2 else 0; closed = null }
                text == "onDestroy end" -> { closed = if (phase == 2) time else null; phase = 0 }
            }
        }
        return Observation(created, closed)
    }

    private fun ByteArray.indexOf(value: Byte, from: Int): Int {
        for (i in from until size) if (this[i] == value) return i
        return -1
    }
}
