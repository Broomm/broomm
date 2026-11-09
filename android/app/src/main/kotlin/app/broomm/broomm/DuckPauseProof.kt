package app.broomm.broomm

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.CodingErrorAction

/** Framework client events emitted after the reviewed MainActivity.onPause
 * returns. System-server timeout/state text is not positive callback evidence. */
internal object DuckPauseProof {
    const val MAX_BYTES = 512 * 1024
    fun completed(bytes: ByteArray, pid: Int, uid: Int, earliest: Long, latest: Long): Boolean {
        require(bytes.size <= MAX_BYTES && pid > 0 && uid in 10000..99999 && earliest > 0 && latest >= earliest)
        val input = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        var paused = false; var previous = earliest
        while (input.hasRemaining()) {
            require(input.remaining() >= 28) { "Incomplete Android pause event header." }
            val length = input.short.toInt() and 65535; val header = input.short.toInt() and 65535
            require(header == 28 && length in 4..5120 && input.remaining() >= 24 + length)
            val ownerPid = input.int; val tid = input.int
            val sec = input.int.toLong() and 0xffffffffL; val nano = input.int.toLong() and 0xffffffffL
            val buffer = input.int; val owner = input.int
            require(ownerPid == pid && owner == uid && buffer == 2 && tid > 0 && nano < 1_000_000_000L)
            val payload = ByteArray(length); input.get(payload)
            val time = sec * 1000 + nano / 1_000_000
            if (time < earliest) continue
            require(time in previous..latest) { "Android pause event clock changed." }; previous = time
            val value = ByteBuffer.wrap(payload).order(ByteOrder.LITTLE_ENDIAN); val tag = value.int
            if (tid != pid || tag !in setOf(30021, 30022, 30057, 30059)) continue
            require(value.remaining() >= 7 && value.get() == 3.toByte() && value.get() == 3.toByte() && value.get() == 0.toByte())
            value.int // Activity token; lifecycle ordering is process-bound below.
            fun text(): String {
                require(value.remaining() >= 5 && value.get() == 2.toByte())
                val size = value.int; require(size in 1..256 && value.remaining() >= size)
                val b = ByteArray(size); value.get(b)
                return Charsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(b)).toString()
            }
            val component = text(); val reason = text(); require(!value.hasRemaining())
            if (component != "com.github.stenzek.duckstation.MainActivity") continue
            paused = tag == 30021 && reason == "performPause"
        }
        return paused
    }
}
