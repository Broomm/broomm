package app.broomm.broomm

/** Reviewed ARMSX2 Android 2.9.2 graceful shutdown followed by self-SIGKILL. */
internal object Armsx2ShutdownProof {
    private val begin = Regex("@@ANDROID_STOP_JAVA@@ begin saveAutosave=(?:true|false) forced=false restart=false")
    private val returned = Regex("@@ANDROID_STOP_JAVA@@ shutdown_return active=false runLoop=(?:true|false) state=[A-Z_]+")
    private val nativePrefix = Regex("^\\[\\s*\\d+\\.\\d+\\] ")
    private val done = Regex("@@ANDROID_STOP_DONE@@ waited_ms=\\d+")

    fun closed(bytes: ByteArray, pid: Int, uid: Int, observed: Long, exited: Long): Boolean {
        var phase = 0
        var javaThread = 0
        var nativeThread = 0
        var begunAt = 0L
        var selfSignal: Long? = null
        AndroidShutdownLog.read(bytes, pid, uid, observed, exited) { time, tid, priority, tag, text ->
            if (tag == "System.out" && priority == 4) {
                if (text.startsWith("@@ANDROID_STOP_JAVA@@ begin ")) {
                    phase = if (begin.matches(text)) 1 else 0
                    javaThread = tid
                    begunAt = time
                    selfSignal = null
                } else if (text.startsWith("@@ANDROID_STOP_JAVA@@ shutdown_return")) {
                    phase = if (phase == 2 && tid == javaThread && returned.matches(text)) 3 else 0
                }
            } else if (tag == "STDOUT" && priority == 5) {
                val message = text.removeSuffix("\n").replaceFirst(nativePrefix, "")
                if (phase == 1 && done.matches(message)) {
                    nativeThread = tid
                    phase = 2
                } else if (phase == 3 && tid == nativeThread &&
                    message == "@@ANDROID_STOP@@ request active=0 state=0 execute_exit=1") {
                    phase = 4
                }
            } else if (tag == "Process" && priority == 4 && tid == pid &&
                text == "Sending signal. PID: $pid SIG: 9") {
                selfSignal = if (phase == 4 && time - begunAt <= 30000) time else null
                phase = 0
            }
        }
        return selfSignal?.let { exited - it in 0..2000 } == true
    }
}
