import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// Saves a generated file to where the user expects a download to land.
///
/// Android goes through a platform channel into the public Downloads
/// folder, because Dart has no way to reach it: `path_provider` offers
/// no Downloads directory on mobile, and the share sheet asks the user
/// to choose a destination for something they already said to download.
///
/// iOS has no shared Downloads folder. The file goes to the app's own
/// Documents directory instead, which the Files app exposes under
/// "On My iPhone > Pargig" thanks to the two keys in Info.plist.
class FileSaver {
  FileSaver._();

  static const _channel = MethodChannel('pargig/save_file');

  /// Writes [bytes] as [fileName] and returns where it landed, in words
  /// fit to show the user ("Downloads/INV-44BDA0.pdf").
  ///
  /// Returns null when the save failed, so the caller can fall back to
  /// the share sheet rather than leaving the user with nothing.
  static Future<String?> saveToDownloads(
    Uint8List bytes,
    String fileName, {
    String mimeType = 'application/pdf',
  }) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        final where = await _channel.invokeMethod<String>('saveToDownloads', {
          'bytes': bytes,
          'fileName': fileName,
          'mimeType': mimeType,
        });
        return (where == null || where.isEmpty) ? null : where;
      } on PlatformException {
        return null;
      } on MissingPluginException {
        // An older build of the app without the channel registered.
        return null;
      }
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$fileName');
      await file.writeAsBytes(bytes, flush: true);
      return 'Files > Pargig > $fileName';
    } catch (_) {
      return null;
    }
  }
}
