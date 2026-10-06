import 'package:flutter/services.dart';

/// Transcribes a finished recording using the phone's own speech
/// recogniser, over a platform channel.
///
/// This is what makes one spoken take produce both outputs: the audio is
/// recorded to a file (the microphone's only consumer), uploaded as-is,
/// and then that same file is handed to the OS recogniser for the text.
/// Nothing is sent to a server or an AI service.
///
/// Availability differs by platform:
///   - Android 13+ (API 33) via SpeechRecognizer EXTRA_AUDIO_SOURCE
///   - iOS via SFSpeechURLRecognitionRequest
/// Anywhere else [isSupported] is false and [transcribe] returns null, so
/// callers must keep a fallback (live dictation, or just typing).
class SpeechFile {
  SpeechFile._();

  static const MethodChannel _channel = MethodChannel('pargig/speech_file');

  /// Whether this device can transcribe a recorded file at all.
  static Future<bool> isSupported() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isSupported');
      return ok ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Transcribes [path], returning the text or — when there isn't any —
  /// a short reason why. Never throws: a missing transcript must not
  /// break the recording, but it must be explainable, otherwise "the
  /// model isn't installed" is indistinguishable from "you said nothing".
  static Future<({String? text, String? error})> transcribe(String path) async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>(
        'transcribeFile',
        {'path': path},
      );
      if (res == null) return (text: null, error: 'No response from device');
      final text = (res['text'] as String?)?.trim() ?? '';
      final err = (res['error'] as String?)?.trim() ?? '';
      if (text.isNotEmpty) return (text: text, error: null);
      return (text: null, error: err.isEmpty ? 'No text recognised' : err);
    } on MissingPluginException {
      return (text: null, error: 'Not supported on this platform');
    } catch (e) {
      return (text: null, error: e.toString());
    }
  }
}
