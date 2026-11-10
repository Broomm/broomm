package app.broomm.broomm

/** PPSSPP 1.20.4's synchronous Java/native shutdown protocol, not generic log matching. */
internal object PpssppShutdownProof {
    const val MAX_BYTES = AndroidShutdownLog.MAX_BYTES
    private const val FINISH = "Setting shuttingDown = true and calling Finish"
    private const val SHUTDOWN = "in onDestroy, shutting down. Calling NativeApp.shutdown()."
    data class Observation(val created: Long?, val closed: Long?)

    fun inspect(bytes: ByteArray, pid: Int, uid: Int, earliest: Long, latest: Long): Observation {
        var created: Long? = null
        var closed: Long? = null
        var phase = 0
        AndroidShutdownLog.read(bytes, pid, uid, earliest, latest) { time, tid, priority, tag, text ->
            if (tid != pid || priority != 4 || tag != "PpssppActivity") return@read
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

}
