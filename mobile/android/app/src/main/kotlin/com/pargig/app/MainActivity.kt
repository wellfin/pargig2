package com.pargig.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val CHANNEL = "pargig/speech_file"
        const val FILE_CHANNEL = "pargig/save_file"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Transcribes a finished recording with the on-device
                // recogniser so one spoken take yields both the stored
                // audio and the written description.
                "transcribeFile" -> {
                    val path = call.argument<String>("path")
                    if (path.isNullOrEmpty()) {
                        result.success(null)
                    } else {
                        FileSpeechRecognizer.transcribe(this, path) { payload ->
                            runOnUiThread { result.success(payload) }
                        }
                    }
                }
                // Lets Dart decide whether to offer the one-take flow or
                // fall back to live dictation, without guessing at the
                // Android version from the Flutter side.
                "isSupported" -> result.success(FileSpeechRecognizer.isSupported())
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            FILE_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                // Saves bytes straight into the public Downloads folder,
                // so "Download Invoice" downloads instead of opening a
                // share sheet.
                "saveToDownloads" -> {
                    val bytes = call.argument<ByteArray>("bytes")
                    val name = call.argument<String>("fileName")
                    val mime = call.argument<String>("mimeType") ?: "application/octet-stream"
                    if (bytes == null || name.isNullOrEmpty()) {
                        result.success(null)
                    } else {
                        result.success(DownloadSaver.save(this, bytes, name, mime))
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}
