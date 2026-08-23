/// Opening the camera to scan a packet, from wherever the user asked.
///
/// Two widgets offer scanning — the held orb ring and the tap-out tree — and
/// the flow has two steps and several ways to fall back, so it lives here
/// rather than being written twice and drifting.
///
/// The order is barcode first, panel second, and that is not arbitrary. A
/// barcode lookup is exact, costs no model call when the food graph already
/// holds the packet, and returns micronutrients rather than four macros.
/// Photographing the panel is what you do when no database has ever seen the
/// packet — which for Egyptian brands is often — and it is the more expensive
/// path in every sense.
library;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../screens/barcode_screen.dart';
import '../state/app_state.dart';

/// Scans a packet: barcode, then the nutrition panel if nothing was found.
///
/// Returns without doing anything if the camera is not allowed — the state
/// object says why, and sends the user somewhere that explains it.
Future<void> startPacketScan(BuildContext context, AppState state) async {
  if (!state.barcodeScanAllowed) {
    state.refuseCameraFeature(
      ar: 'مسح الباركود بيستخدم الكاميرا، وده لـ Qamar+.',
      en: 'Scanning a barcode uses the camera, so it is Qamar+.',
    );
    return;
  }

  final code = await Navigator.of(context).push<String>(
    MaterialPageRoute(builder: (_) => BarcodeScreen(isAr: state.isAr)),
  );
  if (!context.mounted || code == null) return; // backed out

  await state.scanPacketBarcode(code);

  // A miss is not a dead end: the packet is simply not catalogued yet, and the
  // panel on the back is the catalogue entry. Offering the camera straight
  // away is the difference between "not found" and "hold it up to me".
  if (!context.mounted || !state.awaitingLabelPhoto) return;
  await photographPanel(context, state);
}

/// Photographs the nutrition panel and sends it to be read.
///
/// Used on its own from the log ring, and as the second step after a barcode
/// miss — in which case [AppState] already knows the code, and files the panel
/// under it so nobody has to photograph that packet again.
Future<void> photographPanel(BuildContext context, AppState state) async {
  if (!state.labelScanAllowed) {
    state.refuseCameraFeature(
      ar: 'قراءة جدول القيم الغذائية بتستخدم الكاميرا والموديل، وده لـ Qamar+.',
      en: 'Reading a nutrition panel uses the camera and the model, so it is Qamar+.',
    );
    return;
  }
  try {
    final shot = await ImagePicker().pickImage(
      source: ImageSource.camera,
      // A nutrition panel is small print. Compressing it the way a plate of
      // food can be compressed loses the digits, which is the only thing on
      // it that matters.
      imageQuality: 94,
      maxWidth: 2400,
    );
    if (!context.mounted || shot == null) return;
    await state.scanLabelPhoto(shot.path);
  } on Exception catch (e) {
    if (!context.mounted) return;
    state.reportScanProblem('$e');
  }
}
