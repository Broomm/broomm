package app.broomm.broomm

import android.content.Context
import android.os.Build
import android.os.Process
import java.io.File

internal fun interface RootProcessGuard { fun allow(): Boolean }

/** Only the root service uses this kernel mechanism. Addresses and guards are
 * fixed by its reviewed emulator layout, never supplied by Dart or metadata. */
internal object RootProcessKernel {
    @Volatile private var loaded = false

    @Synchronized fun load(context: Context) {
        if (loaded) return
        val apk = File(context.applicationInfo.sourceDir)
        require(apk.canonicalPath == apk.path && apk.path.startsWith("/data/app/"))
        val abi = (if (Process.is64Bit()) Build.SUPPORTED_64_BIT_ABIS else Build.SUPPORTED_32_BIT_ABIS).first()
        require(abi in setOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86"))
        try { System.load("${apk.path}!/lib/$abi/libbroomm_root_process.so") }
        catch (e: UnsatisfiedLinkError) { throw IllegalStateException("This Broomm build cannot load its root process adapter. Install a complete supported APK; recovery was kept.", e) }
        loaded = true
    }

    external fun stopIdle(pid: Int, ticks: Long, addresses: LongArray, lengths: IntArray,
        maps: Array<String>, prefixes: Array<String>, guard: RootProcessGuard): Int
}
