package com.comfunny.mychild_reading

import android.app.Activity
import android.content.Intent
import android.provider.DocumentsContract
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InputStream
import java.io.OutputStream
import java.util.UUID
import java.util.concurrent.Executors

class MainActivity : AudioServiceActivity() {
    companion object { private var cacheRecovered = false }
    private val ioWorker = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var exportFile: File? = null
    private var copying = false
    private val requestCode = 7312
    private val maxBytes = 20L * 1024 * 1024 * 1024 + 8L * 1024 * 1024 + 12

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Once per process, recover only jobs left by a previous process.
        synchronized(MainActivity::class.java) {
            if (!cacheRecovered) {
                cacheRecovered = true
                val root = File(cacheDir, "backup-transfer")
                val stale = root.listFiles()?.filter {
                    it.name.startsWith("export-") || it.name.startsWith("import-")
                } ?: emptyList()
                ioWorker.execute { stale.forEach { file ->
                    try {
                        if (file.canonicalFile.parentFile == root.canonicalFile) file.deleteRecursively()
                    } catch (_: Exception) { }
                } }
            }
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mychild_reading/backup_files")
            .setMethodCallHandler { call, result ->
                if (call.method != "exportBackup" && call.method != "pickBackup") {
                    result.notImplemented()
                } else if (pending != null) {
                    result.error("busy", "이미 파일 작업 중입니다.", null)
                } else {
                    try {
                        exportFile = if (call.method == "exportBackup") {
                            val root = File(cacheDir, "backup-transfer").canonicalFile
                            val file = File(call.argument<String>("path") ?: "").canonicalFile
                            require(file.path.startsWith(root.path + File.separator) && file.isFile && file.length() <= maxBytes)
                            file
                        } else null
                        val intent = Intent(if (exportFile != null) Intent.ACTION_CREATE_DOCUMENT else Intent.ACTION_OPEN_DOCUMENT)
                            .addCategory(Intent.CATEGORY_OPENABLE)
                            .setType(if (exportFile != null) "application/octet-stream" else "*/*")
                            .putExtra(Intent.EXTRA_LOCAL_ONLY, true)
                        if (exportFile != null) {
                            intent.putExtra(Intent.EXTRA_TITLE, "little-library-${System.currentTimeMillis()}.mcrb")
                        }
                        pending = result
                        startActivityForResult(intent, requestCode)
                    } catch (_: Exception) {
                        pending = null
                        exportFile = null
                        result.error("file_unavailable", "파일 선택을 시작하지 못했습니다.", null)
                    }
                }
            }
    }

    @Deprecated("Android document picker callback")
    override fun onActivityResult(request: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(request, resultCode, data)
        if (request != requestCode) return
        val callback = pending ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            exportFile = null
            callback.success(null)
            return
        }
        val source = exportFile
        copying = true
        ioWorker.execute {
            var imported: File? = null
            try {
                val answer: Any = if (source != null) {
                    source.inputStream().use { input ->
                        requireNotNull(contentResolver.openOutputStream(uri, "w")).use { output -> copyLimited(input, output) }
                    }
                    true
                } else {
                    val directory = File(cacheDir, "backup-transfer").apply { mkdirs() }
                    imported = File(directory, "import-${UUID.randomUUID()}.mcrb")
                    requireNotNull(contentResolver.openInputStream(uri)).use { input ->
                        imported!!.outputStream().use { output -> copyLimited(input, output) }
                    }
                    imported!!.path
                }
                runOnUiThread {
                    pending = null
                    exportFile = null
                    copying = false
                    callback.success(answer)
                }
            } catch (_: Exception) {
                imported?.delete()
                // 새로 만든 출력만 정리한다. 가져오기 원본은 건드리지 않는다.
                if (source != null) {
                    try { DocumentsContract.deleteDocument(contentResolver, uri) } catch (_: Exception) { }
                }
                runOnUiThread {
                    pending = null
                    exportFile = null
                    copying = false
                    callback.error("copy_failed", "파일을 복사하지 못했습니다. 저장 공간을 확인해 주세요.", null)
                }
            }
        }
    }

    private fun copyLimited(input: InputStream, output: OutputStream) {
        val buffer = ByteArray(64 * 1024)
        var total = 0L
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            total += count
            require(total <= maxBytes)
            output.write(buffer, 0, count)
        }
        output.flush()
    }

    override fun onDestroy() {
        // 이미 시작한 복사는 끝내되 새로운 작업은 받지 않는다.
        if (!copying) {
            val callback = pending
            pending = null
            exportFile = null
            callback?.error("activity_closed", "File selection was interrupted.", null)
        }
        ioWorker.shutdown()
        super.onDestroy()
    }
}
