import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'indic_latin.dart';
import 'speech_model.dart';

/// Speech recognition that runs *inside this app*.
///
/// That in-process detail is the whole point. The platform recogniser
/// (`speech_to_text`) delegates to another app, which opens its own
/// microphone — and Android only lets one app capture at a time, so it
/// and the recorder could never run together. Because this decodes in
/// our own process, a single microphone session can feed both: the bytes
/// go to the .wav file and to the recogniser at once.
///
/// Everything is local. No audio leaves the device and there is no API
/// key or per-use cost.
class OfflineTranscriber {
  OfflineTranscriber._();

  static sherpa.OfflineRecognizer? _recognizer;
  static bool _initFailed = false;

  static bool get isLoaded => _recognizer != null;

  /// Loads the model into memory. Cheap to call repeatedly — the
  /// recogniser is built once and reused for every recording.
  static Future<bool> ensureLoaded() async {
    if (_recognizer != null) return true;
    if (_initFailed) return false;
    if (!await SpeechModel.isReady()) return false;

    try {
      sherpa.initBindings();
      final config = sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: await SpeechModel.encoderPath(),
            decoder: await SpeechModel.decoderPath(),
          ),
          tokens: await SpeechModel.tokensPath(),
          numThreads: 2,
          debug: false,
          modelType: 'whisper',
        ),
      );
      _recognizer = sherpa.OfflineRecognizer(config);
      return true;
    } catch (e) {
      // A corrupt or half-downloaded model lands here. Don't retry every
      // recording — one failure is enough to fall back for the session.
      if (kDebugMode) debugPrint('[OfflineTranscriber] load failed: $e');
      _initFailed = true;
      return false;
    }
  }

  /// Transcribes 16-bit PCM samples captured at [sampleRate].
  ///
  /// Returns null when the model isn't loaded or nothing was recognised;
  /// never throws, because a missing transcript must not cost the user
  /// their recording.
  static Future<String?> transcribePcm16(
    Int16List samples,
    int sampleRate,
  ) async {
    if (!await ensureLoaded()) return null;
    final recognizer = _recognizer;
    if (recognizer == null || samples.isEmpty) return null;

    try {
      // sherpa wants normalised floats in [-1, 1].
      final floats = Float32List(samples.length);
      for (var i = 0; i < samples.length; i++) {
        floats[i] = samples[i] / 32768.0;
      }

      final stream = recognizer.createStream();
      stream.acceptWaveform(samples: floats, sampleRate: sampleRate);
      recognizer.decode(stream);
      final result = recognizer.getResult(stream);
      stream.free();

      final text = result.text.trim();
      if (text.isEmpty) return null;
      // Indian languages come back in their own script. Convert the
      // script — not the words — so Hindi reads "ham ja rahe hain" and
      // Tamil reads "enakku pasikkirathu": the same sentence, in letters
      // anyone can read. Latin text is left alone, so English and mixed
      // writing pass through untouched.
      return IndicLatin.convert(text);
    } catch (e) {
      if (kDebugMode) debugPrint('[OfflineTranscriber] decode failed: $e');
      return null;
    }
  }

  static void dispose() {
    _recognizer?.free();
    _recognizer = null;
  }
}
