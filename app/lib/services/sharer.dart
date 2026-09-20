import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';

/// The phone's share sheet, behind a seam: the card is rendered by the app,
/// the OS does the sending. Null in tests and wherever there is no sheet.
abstract class Sharer {
  Future<void> shareImage(Uint8List png, {required String text, required String fileName});

  /// A message with no picture — an invitation, for instance.
  Future<void> shareText(String text);
}

class PlatformSharer implements Sharer {
  @override
  Future<void> shareImage(Uint8List png, {required String text, required String fileName}) async {
    try {
      await SharePlus.instance.share(ShareParams(
        files: [XFile.fromData(png, mimeType: 'image/png', name: fileName)],
        text: text,
        fileNameOverrides: [fileName],
      ));
    } catch (e) {
      debugPrint('Qamar share: $e');
    }
  }

  @override
  Future<void> shareText(String text) async {
    try {
      await SharePlus.instance.share(ShareParams(text: text));
    } catch (e) {
      debugPrint('Qamar share: $e');
    }
  }
}

/// Records what would have gone to the sheet.
class MemorySharer implements Sharer {
  final List<({Uint8List png, String text, String fileName})> shared = [];
  final List<String> texts = [];

  @override
  Future<void> shareText(String text) async {
    texts.add(text);
  }

  @override
  Future<void> shareImage(Uint8List png, {required String text, required String fileName}) async {
    shared.add((png: png, text: text, fileName: fileName));
  }
}
