import 'dart:io';

import 'package:image_picker/image_picker.dart';

/// One camera setting for the whole app.
///
/// The blueprint budgets photos at about 200 KB: enough for a plate, a menu
/// or an InBody printout to be read, small enough for a 3G upload to finish
/// before the person loses interest. 1280 px on the long side at JPEG
/// quality 72 lands a phone photo in that range; the gateway's 5 MB backstop
/// is never approached.
const int kPhotoMaxWidth = 1280;
const int kPhotoQuality = 72;

Future<XFile?> pickCompressedPhoto(ImageSource source) {
  return ImagePicker().pickImage(
    source: source,
    imageQuality: kPhotoQuality,
    maxWidth: kPhotoMaxWidth.toDouble(),
    maxHeight: kPhotoMaxWidth.toDouble() * 1.5,
  );
}

/// Removes a shot the picker cached, once its verdict is in. The picture was
/// only ever needed for the length of one call; nothing keeps it. Best
/// effort — a file already gone is not an error.
Future<void> discardPhoto(String? path) async {
  if (path == null || path.isEmpty) return;
  try {
    final f = File(path);
    if (await f.exists()) await f.delete();
  } catch (_) {
    // Nothing to do: the cache is the OS's to clear if this failed.
  }
}
