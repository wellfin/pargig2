import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Fetches and stores the offline speech-recognition model.
///
/// The model is downloaded once rather than shipped in the APK: at ~98 MB
/// it would more than double the install size for every user, including
/// the ones who never post a job by voice. Downloading on first use keeps
/// the app small and, once fetched, recognition runs entirely on the
/// device with no network and no service.
///
/// Files land in the app's support directory (not the cache) so the OS
/// won't reclaim them under storage pressure and force a re-download.
class SpeechModel {
  SpeechModel._();

  static const _base =
      'https://huggingface.co/csukuangfj/sherpa-onnx-whisper-tiny/resolve/main';

  // Whisper tiny, int8-quantised: the smallest model in sherpa-onnx's
  // catalogue that handles Hindi as well as English, which matters for
  // the Hinglish these descriptions are spoken in.
  static const _files = <String, int>{
    'tiny-encoder.int8.onnx': 13 * 1024 * 1024,
    'tiny-decoder.int8.onnx': 86 * 1024 * 1024,
    'tiny-tokens.txt': 800 * 1024,
  };

  static Directory? _dir;

  static Future<Directory> _modelDir() async {
    if (_dir != null) return _dir!;
    final support = await getApplicationSupportDirectory();
    final d = Directory('${support.path}/speech-model');
    if (!d.existsSync()) d.createSync(recursive: true);
    _dir = d;
    return d;
  }

  static Future<String> encoderPath() async =>
      '${(await _modelDir()).path}/tiny-encoder.int8.onnx';

  static Future<String> decoderPath() async =>
      '${(await _modelDir()).path}/tiny-decoder.int8.onnx';

  static Future<String> tokensPath() async =>
      '${(await _modelDir()).path}/tiny-tokens.txt';

  /// Approximate download size, for the confirmation prompt.
  static int get downloadBytes =>
      _files.values.fold(0, (sum, bytes) => sum + bytes);

  /// True when every file is present and plausibly complete. Size is
  /// checked, not just existence, so a download interrupted midway is
  /// re-fetched instead of handed to the recogniser as a corrupt model.
  static Future<bool> isReady() async {
    final dir = await _modelDir();
    for (final entry in _files.entries) {
      final f = File('${dir.path}/${entry.key}');
      if (!f.existsSync()) return false;
      // Allow generous slack: the constants above are rounded.
      if (f.lengthSync() < entry.value * 0.6) return false;
    }
    return true;
  }

  /// Downloads whatever is missing, reporting 0..1 progress.
  ///
  /// Each file streams to a `.part` and is renamed only once complete, so
  /// an interrupted download can never leave a half-file that looks valid
  /// on the next launch.
  static Future<bool> download({
    void Function(double progress)? onProgress,
    void Function(String message)? onError,
  }) async {
    try {
      final dir = await _modelDir();
      final total = downloadBytes;
      var completed = 0;

      for (final entry in _files.entries) {
        final target = File('${dir.path}/${entry.key}');
        if (target.existsSync() && target.lengthSync() >= entry.value * 0.6) {
          completed += entry.value;
          onProgress?.call((completed / total).clamp(0.0, 1.0));
          continue;
        }

        final part = File('${target.path}.part');
        if (part.existsSync()) part.deleteSync();

        final req = http.Request('GET', Uri.parse('$_base/${entry.key}'));
        final res = await http.Client().send(req);
        if (res.statusCode != 200) {
          onError?.call('Download failed (HTTP ${res.statusCode})');
          return false;
        }

        final expected = res.contentLength ?? entry.value;
        var written = 0;
        final sink = part.openWrite();
        await for (final chunk in res.stream) {
          sink.add(chunk);
          written += chunk.length;
          final fraction = (completed + written * (entry.value / expected)) / total;
          onProgress?.call(fraction.clamp(0.0, 1.0));
        }
        await sink.flush();
        await sink.close();

        if (part.lengthSync() < entry.value * 0.6) {
          part.deleteSync();
          onError?.call('Download was incomplete');
          return false;
        }
        part.renameSync(target.path);
        completed += entry.value;
        onProgress?.call((completed / total).clamp(0.0, 1.0));
      }
      return true;
    } catch (e) {
      if (kDebugMode) debugPrint('[SpeechModel] $e');
      onError?.call('Download failed: $e');
      return false;
    }
  }
}
