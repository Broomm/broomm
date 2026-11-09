package app.broomm.broomm

import java.io.ByteArrayOutputStream
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.io.File

private fun pauseEntry(tag:Int, time:Long=2000, pid:Int=77, uid:Int=10137, tid:Int=77, buffer:Int=2,
    component:String="com.github.stenzek.duckstation.MainActivity"):ByteArray {
    val out=ByteArrayOutputStream()
    fun integer(v:Int) {out.write(ByteBuffer.allocate(4).order(ByteOrder.LITTLE_ENDIAN).putInt(v).array())}
    fun text(v:String) {out.write(2);val b=v.toByteArray();integer(b.size);out.write(b)}
    integer(tag);out.write(3);out.write(3);out.write(0);integer(123)
    text(component);text(if(tag==30021) "performPause" else "RESUME_ACTIVITY")
    val p=out.toByteArray()
    return ByteBuffer.allocate(28+p.size).order(ByteOrder.LITTLE_ENDIAN).apply {
        putShort(p.size.toShort());putShort(28);putInt(pid);putInt(tid);putInt((time/1000).toInt());putInt((time%1000*1000000).toInt());putInt(buffer);putInt(uid);put(p)
    }.array()
}
fun main(args:Array<String>) {
    fun proof(bytes:ByteArray)=DuckPauseProof.completed(bytes,77,10137,1500,3000)
    check(proof(pauseEntry(30022,1700)+pauseEntry(30021)))
    check(!proof(pauseEntry(30021,1499)))
    check(!proof(pauseEntry(30021)+pauseEntry(30022))) // Forced timestamp tie, later resume wins.
    check(!proof(pauseEntry(30021)+pauseEntry(30057)))
    check(!proof(pauseEntry(30021,tid=78)))
    check(!proof(pauseEntry(30021,component="com.github.stenzek.duckstation.EmulationActivity")))
    println("PASS completed client pause, fresh epoch, resume/create ordering, activity and thread correspondence")
    val malformed=listOf(pauseEntry(30021,pid=78),pauseEntry(30021,uid=10138),pauseEntry(30021,buffer=0),
        pauseEntry(30021).copyOf(29),pauseEntry(30021,2100)+pauseEntry(30022,2000))
    for(b in malformed) {var rejected=false;try{proof(b)}catch(_:IllegalArgumentException){rejected=true};check(rejected)}
    println("PASS foreign source, wrong buffer, truncated event and backwards clock refusal")
    if(args.isNotEmpty()) {
        require(args.size==5)
        check(DuckPauseProof.completed(File(args[0]).readBytes(),args[1].toInt(),args[2].toInt(),args[3].toLong(),args[4].toLong()))
        println("PASS captured Thor framework pause evidence")
    }
}
