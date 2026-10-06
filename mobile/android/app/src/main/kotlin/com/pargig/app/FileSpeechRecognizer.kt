package com.pargig.app

import android.content.Context
import android.content.Intent
import android.media.AudioFormat
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.ParcelFileDescriptor
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import java.io.File
import java.util.Locale

/**
 * Transcribes an already-recorded WAV using the phone's speech recogniser.
 *
 * This exists because the microphone can only be held by one consumer at
 * a time: running the recogniser live alongside the recorder leaves the
 * recording empty. Feeding it the finished file instead lets a single
 * spoken take produce both the stored audio and the written text.
 *
 * Requires Android 13 (API 33) — that's when SpeechRecognizer gained
 * EXTRA_AUDIO_SOURCE. Below that this reports unsupported and the app
 * falls back to live dictation or typing.
 *
 * Two recognisers are tried in order. The on-device one keeps audio on
 * the handset but in practice often ignores EXTRA_AUDIO_SOURCE and
 * listens to the (silent) microphone instead, returning no words. When
 * that happens we retry with the system default recogniser, which does
 * honour the file source.
 */
object FileSpeechRecognizer {

    private const val MIN_WAV_BYTES = 44

    fun isSupported(): Boolean = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    /** Raw PCM extracted from a WAV, with the format it's actually in. */
    private data class Pcm(
        val file: File,
        val sampleRate: Int,
        val channels: Int,
    ) {
        val seconds: Double
            get() = file.length().toDouble() / (sampleRate * channels * 2)
    }

    /**
     * @param onDone called exactly once with `text` (the transcript, or
     *   null) and `error` (a short reason when there is no text). Failures
     *   are reported rather than swallowed: a silent null is impossible to
     *   tell apart from "the recording was empty" on a real device.
     */
    fun transcribe(
        context: Context,
        wavPath: String,
        onDone: (Map<String, Any?>) -> Unit,
    ) {
        val fail = { reason: String -> onDone(mapOf("text" to null, "error" to reason)) }

        if (!isSupported()) {
            fail("Needs Android 13 or newer (this device is API ${Build.VERSION.SDK_INT})")
            return
        }
        val wav = File(wavPath)
        if (!wav.exists() || wav.length() <= MIN_WAV_BYTES) {
            fail("Recording file was empty")
            return
        }

        // SpeechRecognizer is main-thread only.
        Handler(Looper.getMainLooper()).post {
            val pcm = parseWav(wav)
            if (pcm == null) {
                fail("Could not read the recording")
                return@post
            }

            val onDeviceAvailable = SpeechRecognizer.isOnDeviceRecognitionAvailable(context)
            val defaultAvailable = SpeechRecognizer.isRecognitionAvailable(context)
            if (!onDeviceAvailable && !defaultAvailable) {
                pcm.file.delete()
                fail("No speech recogniser installed on this device")
                return@post
            }

            val finish = { text: String?, reason: String? ->
                pcm.file.delete()
                onDone(mapOf("text" to text, "error" to reason))
            }

            // Prefer on-device (audio never leaves the phone); fall back to
            // the system recogniser only when it yields nothing.
            val first = if (onDeviceAvailable) true else false
            runRecognizer(context, pcm, first) { text, reason ->
                if (text != null) {
                    finish(text, null)
                } else if (first && defaultAvailable) {
                    runRecognizer(context, pcm, false) { text2, reason2 ->
                        finish(text2, if (text2 == null) reason2 else null)
                    }
                } else {
                    finish(null, reason)
                }
            }
        }
    }

    /** One recognition attempt. Always calls [onDone] exactly once. */
    private fun runRecognizer(
        context: Context,
        pcm: Pcm,
        onDevice: Boolean,
        onDone: (String?, String?) -> Unit,
    ) {
        var descriptor: ParcelFileDescriptor? = null
        try {
            val recognizer = if (onDevice) {
                SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
            } else {
                SpeechRecognizer.createSpeechRecognizer(context)
            }
            descriptor = ParcelFileDescriptor.open(
                pcm.file,
                ParcelFileDescriptor.MODE_READ_ONLY,
            )

            val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
                putExtra(
                    RecognizerIntent.EXTRA_LANGUAGE_MODEL,
                    RecognizerIntent.LANGUAGE_MODEL_FREE_FORM,
                )
                // Device locale, so a Hindi/English description isn't
                // forced through an en-US model.
                putExtra(RecognizerIntent.EXTRA_LANGUAGE, Locale.getDefault().toLanguageTag())
                putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, false)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE, descriptor)
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_CHANNEL_COUNT, pcm.channels)
                putExtra(
                    RecognizerIntent.EXTRA_AUDIO_SOURCE_ENCODING,
                    AudioFormat.ENCODING_PCM_16BIT,
                )
                putExtra(RecognizerIntent.EXTRA_AUDIO_SOURCE_SAMPLING_RATE, pcm.sampleRate)
            }

            var settled = false
            val fd = descriptor
            val settle = { text: String?, reason: String? ->
                if (!settled) {
                    settled = true
                    try {
                        fd.close()
                    } catch (_: Exception) {
                    }
                    recognizer.destroy()
                    onDone(text, reason)
                }
            }

            recognizer.setRecognitionListener(object : RecognitionListener {
                override fun onResults(results: Bundle?) {
                    val hit = results
                        ?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
                        ?.firstOrNull()
                        ?.trim()
                    if (hit.isNullOrEmpty()) {
                        settle(null, noWordsDetail(pcm, onDevice))
                    } else {
                        settle(hit, null)
                    }
                }

                override fun onError(error: Int) = settle(null, describeError(error, onDevice))

                override fun onReadyForSpeech(params: Bundle?) {}
                override fun onBeginningOfSpeech() {}
                override fun onRmsChanged(rmsdB: Float) {}
                override fun onBufferReceived(buffer: ByteArray?) {}
                override fun onEndOfSpeech() {}
                override fun onPartialResults(partialResults: Bundle?) {}
                override fun onEvent(eventType: Int, params: Bundle?) {}
            })

            recognizer.startListening(intent)
        } catch (e: Exception) {
            try {
                descriptor?.close()
            } catch (_: Exception) {
            }
            onDone(null, e.message ?: e.javaClass.simpleName)
        }
    }

    /**
     * Reports what was actually fed in. If the seconds/rate look right the
     * audio reached the recogniser intact and the fault is the recogniser's
     * (usually a missing offline language model); if they look wrong, the
     * WAV was parsed badly.
     */
    private fun noWordsDetail(pcm: Pcm, onDevice: Boolean): String = String.format(
        Locale.US,
        "Recogniser returned no words (fed %.1fs @ %dHz, %dch, onDevice=%b, lang=%s)",
        pcm.seconds,
        pcm.sampleRate,
        pcm.channels,
        onDevice,
        Locale.getDefault().toLanguageTag(),
    )

    private fun describeError(code: Int, onDevice: Boolean): String = when (code) {
        SpeechRecognizer.ERROR_AUDIO -> "Could not read the recording's audio"
        SpeechRecognizer.ERROR_NO_MATCH -> "Nothing recognisable was heard"
        SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> "No speech detected in the recording"
        SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> "Permission denied"
        SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE,
        SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED ->
            "Language model not installed for ${Locale.getDefault().toLanguageTag()}. " +
                "Add it in Settings > System > Languages & input > On-device recognition."
        SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT -> "Recogniser could not be checked"
        SpeechRecognizer.ERROR_SERVER, SpeechRecognizer.ERROR_NETWORK,
        SpeechRecognizer.ERROR_NETWORK_TIMEOUT ->
            if (onDevice) "On-device recogniser failed (model may be downloading)"
            else "Speech service unavailable — check the network"
        else -> "Speech recogniser error $code"
    }

    /**
     * Extracts the PCM payload from a WAV by walking its RIFF chunks.
     *
     * A fixed 44-byte offset does not work: encoders may insert LIST/fact
     * chunks before `data`, and a wrong offset feeds the recogniser
     * misaligned bytes that decode as silence. The format is read from
     * `fmt ` for the same reason — a guess has to match what was written.
     */
    private fun parseWav(wav: File): Pcm? = try {
        val bytes = wav.readBytes()
        if (bytes.size < 12 ||
            String(bytes, 0, 4) != "RIFF" ||
            String(bytes, 8, 4) != "WAVE"
        ) {
            null
        } else {
            var sampleRate = 16000
            var channels = 1
            var dataOffset = -1
            var dataSize = 0

            var cursor = 12
            while (cursor + 8 <= bytes.size) {
                val id = String(bytes, cursor, 4)
                val size = readIntLE(bytes, cursor + 4)
                val body = cursor + 8
                if (size < 0 || body + size > bytes.size) {
                    // Truncated / streaming placeholder — take what's there.
                    if (id == "data") {
                        dataOffset = body
                        dataSize = bytes.size - body
                    }
                    break
                }
                when (id) {
                    "fmt " -> if (size >= 16) {
                        channels = readShortLE(bytes, body + 2)
                        sampleRate = readIntLE(bytes, body + 4)
                    }
                    "data" -> {
                        dataOffset = body
                        dataSize = size
                    }
                }
                if (dataOffset >= 0 && id == "data") break
                // Chunks are word-aligned: odd sizes carry a pad byte.
                cursor = body + size + (size and 1)
            }

            if (dataOffset < 0 || dataSize <= 0 || channels <= 0 || sampleRate <= 0) {
                null
            } else {
                val out = File.createTempFile("speech_", ".pcm", wav.parentFile)
                out.outputStream().use { it.write(bytes, dataOffset, dataSize) }
                if (out.length() > 0) {
                    Pcm(out, sampleRate, channels)
                } else {
                    out.delete()
                    null
                }
            }
        }
    } catch (e: Exception) {
        null
    }

    private fun readIntLE(b: ByteArray, at: Int): Int =
        (b[at].toInt() and 0xFF) or
            ((b[at + 1].toInt() and 0xFF) shl 8) or
            ((b[at + 2].toInt() and 0xFF) shl 16) or
            ((b[at + 3].toInt() and 0xFF) shl 24)

    private fun readShortLE(b: ByteArray, at: Int): Int =
        (b[at].toInt() and 0xFF) or ((b[at + 1].toInt() and 0xFF) shl 8)
}
