package app.broomm.broomm

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.AtomicFile
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.KeyStore
import java.util.concurrent.Executors
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

// OS storage only. Account ownership and token lifecycle are implemented in Dart.
class BroommCredentials(private val context: Context) {
    private val queue = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    fun register(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, "app.broomm/credentials").setMethodCallHandler { call, result ->
            val key = call.argument<String>("key") ?: ""
            val value = call.argument<String>("value")
            if (!key.matches(Regex("^(sgdb-)?[a-f0-9]{32}$")) || call.method !in listOf("read", "write", "delete")) {
                result.error("secure_store", "Invalid secure-store request", null)
            } else queue.execute {
                try {
                    val response = operation(call.method, key, value)
                    main.post { result.success(response) }
                } catch (_: Exception) {
                    main.post { result.error("secure_store", "Secure sign-in storage is unavailable or damaged.", null) }
                }
            }
        }
    }
    fun close() { queue.shutdown() }
    private fun operation(method: String, key: String, value: String?): String? {
        val directory = File(context.noBackupFilesDir, "romm-signins")
        check(directory.isDirectory || directory.mkdirs())
        val file = AtomicFile(File(directory, key))
        val alias = "app.broomm.romm.v1.$key"
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        if (method == "delete") {
            file.delete()
            if (store.containsAlias(alias)) store.deleteEntry(alias)
            return null
        }
        if (method == "read") {
            if (!file.baseFile.exists() && !File(file.baseFile.path + ".bak").exists()) return null
            val encrypted = file.openRead().use { stream ->
                val buffer = ByteArray(32798)
                var total = 0
                while (true) {
                    val count = stream.read(buffer, total, buffer.size - total)
                    if (count < 0) break
                    total += count
                    check(total < buffer.size)
                }
                buffer.copyOf(total)
            }
            check(encrypted.size >= 29 && encrypted[0] == 1.toByte())
            val secret = store.getKey(alias, null) as? SecretKey ?: error("Missing key")
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.DECRYPT_MODE, secret, GCMParameterSpec(128, encrypted.copyOfRange(1, 13)))
            cipher.updateAAD(alias.toByteArray(Charsets.UTF_8))
            return cipher.doFinal(encrypted.copyOfRange(13, encrypted.size)).toString(Charsets.UTF_8)
        }
        val plain = (value ?: error("Missing value")).toByteArray(Charsets.UTF_8)
        check(plain.size <= 32768)
        val secret = (store.getKey(alias, null) as? SecretKey) ?: KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore").run {
            init(KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
                .setKeySize(256).setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE).build())
            generateKey()
        }
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, secret)
        cipher.updateAAD(alias.toByteArray(Charsets.UTF_8))
        val encrypted = byteArrayOf(1) + cipher.iv + cipher.doFinal(plain)
        val output = file.startWrite()
        try { output.write(encrypted); file.finishWrite(output) }
        catch (e: Exception) { file.failWrite(output); throw e }
        return null
    }
}
