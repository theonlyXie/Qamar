// The app's real fonts, for tests that measure layout on a phone-sized
// screen. The default test font draws every glyph a full em wide, so a line
// that fits on a phone overflows under it; these tests need the real widths.
// The icon family (Iconsax, from the iconsax_plus package) is loaded too, so
// a glyph is drawn as itself.
//
// Call once per file, from setUpAll.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

Future<void> loadAppFonts() async {
  final icons = File('/opt/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (icons.existsSync()) {
    await (FontLoader('MaterialIcons')..addFont(Future.value(icons.readAsBytesSync().buffer.asByteData()))).load();
  }
  final families = <String, FontLoader>{};
  for (final f in Directory('assets/fonts').listSync().whereType<File>().where((f) => f.path.endsWith('.ttf'))) {
    final name = f.uri.pathSegments.last;
    final family = name.startsWith('Noto')
        ? 'Noto Sans Arabic'
        : name.startsWith('SpaceGrotesk')
            ? 'Space Grotesk'
            : 'Inter';
    families.putIfAbsent(family, () => FontLoader(family)).addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
  }
  final iconsax = iconsaxDir();
  if (iconsax != null) {
    for (final style in const ['Linear', 'Bold']) {
      final f = File('${iconsax.path}/fonts/IconsaxPlus$style.ttf');
      if (!f.existsSync()) continue;
      families
          .putIfAbsent('packages/iconsax_plus/IconsaxPlus$style', () => FontLoader('packages/iconsax_plus/IconsaxPlus$style'))
          .addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
    }
  }
  for (final loader in families.values) {
    await loader.load();
  }
}

/// Where the iconsax_plus package is on this machine, from the package
/// config pub wrote.
Directory? iconsaxDir() {
  final config = File('.dart_tool/package_config.json');
  if (!config.existsSync()) return null;
  final packages = (jsonDecode(config.readAsStringSync()) as Map<String, dynamic>)['packages'] as List<dynamic>;
  for (final p in packages.cast<Map<String, dynamic>>()) {
    if (p['name'] != 'iconsax_plus') continue;
    final root = Uri.parse(p['rootUri'] as String);
    return Directory.fromUri(root.isAbsolute ? root : Uri.file('${Directory.current.path}/.dart_tool/').resolveUri(root));
  }
  return null;
}
