package app.broomm.broomm

import java.nio.ByteBuffer
import java.nio.ByteOrder

private const val pid = 18482
private const val uid = 10135
private fun entry(message: String, time: Long, process: Int = pid, owner: Int = uid,
                  thread: Int = pid, tag: String = "PpssppActivity", priority: Byte = 4): ByteArray {
    val payload = byteArrayOf(priority) + tag.toByteArray() + byteArrayOf(0) + message.toByteArray() + byteArrayOf(0)
    return ByteBuffer.allocate(28 + payload.size).order(ByteOrder.LITTLE_ENDIAN).apply {
        putShort(payload.size.toShort()); putShort(28); putInt(process); putInt(thread)
        putInt((time / 1000).toInt()); putInt(((time % 1000) * 1_000_000).toInt()); putInt(0); putInt(owner)
        put(payload)
    }.array()
}
private fun cycle(start: Long = 100000) =
    entry("onCreate end", start) + entry("onResume end", start + 1) +
    entry("Setting shuttingDown = true and calling Finish", start + 2000) +
    entry("onPause end", start + 2001) +
    entry("in onDestroy, shutting down. Calling NativeApp.shutdown().", start + 2002) +
    entry("onDestroy end", start + 2003)

fun main() {
    fun inspect(bytes: ByteArray) = PpssppShutdownProof.inspect(bytes, pid, uid, 50000, 200000)
    fun reject(bytes: ByteArray) {
        try { inspect(bytes); error("Invalid binary lifecycle accepted") }
        catch (_: IllegalArgumentException) { }
    }
    check(inspect(cycle()) == PpssppShutdownProof.Observation(100000, 102003))
    // A long session can truncate create logs. A complete final shutdown still
    // supplies absolute idle evidence; session identity is independently held.
    check(inspect(cycle().let { b -> b.copyOfRange(entry("onCreate end", 100000).size + entry("onResume end", 100001).size, b.size) }).closed == 102003L)
    check(inspect(entry("onDestroy end", 100000)).closed == null)
    check(inspect(entry("in onDestroy, shutting down. Calling NativeApp.shutdown().", 100000) + entry("onDestroy end", 100001)).closed == null)
    check(inspect(cycle() + entry("onCreate end", 105000)).closed == null)
    check(inspect(cycle() + entry("onResume end", 105000)).closed == null)
    check(inspect(cycle() + entry("graphics_restart: Calling recreate() on activity", 105000)).closed == null)
    check(inspect(entry("in onDestroy, but not shutting down.", 100000) + entry("onDestroy end", 100001)).closed == null)
    println("PASS PPSSPP normal synchronous shutdown; cached reuse, lost create records, backend recreation and bare destruction boundaries")

    reject(entry("onDestroy end", 100000, process = pid + 1))
    reject(entry("onDestroy end", 100000, owner = uid + 1))
    check(inspect(entry("Setting shuttingDown = true and calling Finish", 100000, thread = pid + 1) +
        entry("in onDestroy, shutting down. Calling NativeApp.shutdown().", 100001) + entry("onDestroy end", 100002)).closed == null)
    check(inspect(entry("Setting shuttingDown = true and calling Finish", 100000, tag = "foreign") +
        entry("in onDestroy, shutting down. Calling NativeApp.shutdown().", 100001) + entry("onDestroy end", 100002)).closed == null)
    check(inspect(entry("onDestroy end", 49000) + cycle()).closed == 102003L)
    println("PASS binary UID/PID/TID/tag correspondence and previous-process timestamp refusal")

    reject(cycle().dropLast(1).toByteArray())
    reject(cycle() + byteArrayOf(1))
    reject(ByteArray(PpssppShutdownProof.MAX_BYTES + 1))
    reject(entry("onCreate end", 100000) + entry("onResume end", 99999))
    reject(entry("onDestroy end", 200001))
    val header = entry("onDestroy end", 100000); header[2] = 24; reject(header)
    println("PASS incomplete/oversized binary input and changed-clock/header refusal")
}
