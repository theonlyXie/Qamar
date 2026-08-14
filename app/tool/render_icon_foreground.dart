// Renders the adaptive-icon foreground layer from the app's own moon painter.
//
//     flutter test tool/render_app_icon.dart tool/render_icon_foreground.dart
//
// The icon has to be the same moon the app draws — a separately drawn
// lookalike would drift the first time the painter changes. So this pumps the
// real [QamarMoon] widget at icon size and captures it, and
// tool/make_icons.py slices the result into the platform densities.
//
// One capture per file: a second toImage() after a second pumpWidget in the
// same test never returns, which is why the adaptive foreground lives in its
// own file rather than a second test here.
//
// Run this again after any change to lib/widgets/moon.dart.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qamar/widgets/moon.dart';

const _size = 1024.0;

/// Fixed, so the icon is identical every time it is regenerated. Slightly
/// fuller than the app's drift band: at 48px on a home screen a thin crescent
/// loses the cratered surface that makes it read as a moon at all.
const _phase = 0.30;

void main() {
  testWidgets('render the adaptive foreground', (tester) async {
    final key = GlobalKey();
    tester.view
      ..physicalSize = const Size(_size, _size)
      ..devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      RepaintBoundary(
        key: key,
        child: const SizedBox(
          width: _size,
          height: _size,
          // Transparent, and drawn at 52% — Android crops an adaptive icon's
          // foreground to the middle 66% and shifts it as the launcher
          // parallaxes, so anything larger loses its limb.
          child: Center(child: QamarMoon(size: _size * 0.52, staticPhase: _phase)),
        ),
      ),
    );
    await tester.pump();

    await _capture(key, 'tool/app_icon_foreground_1024.png');
  });
}

Future<void> _capture(GlobalKey key, String path) async {
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final image = await boundary.toImage(pixelRatio: 1.0);
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
}
