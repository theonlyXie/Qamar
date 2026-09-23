// The app's real fonts, for tests that measure layout on a phone-sized
// screen. The default test font draws every glyph a full em wide, so a line
// that fits on a phone overflows under it; these tests need the real widths.
//
// Call once per file, from setUpAll.

import 'dart:io';

import 'package:flutter/services.dart';

Future<void> loadAppFonts() async {
  final icons = File('/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData()))).load();
  }
  final families = <String, FontLoader>{};
  for (final f in Directory('assets/fonts').listSync().whereType<File>()) {
    final family = f.path.contains('Noto') ? 'Noto Sans Arabic' : 'Inter';
    families.putIfAbsent(family, () => FontLoader(family)).addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
  }
  for (final loader in families.values) {
    await loader.load();
  }
}
