import 'package:flutter/material.dart';
import 'colors.dart';

/// The corners (the mono-glass skill). Controls are round-ended; everything
/// that holds content takes one of three corners, by what it is, and a shape
/// inside another keeps the outer corner less the space between them, so the
/// two stay concentric (radii_test.dart).
class QRadii {
  QRadii._();

  /// Anything a finger presses: buttons, chips, the composer, toggles. Drawn
  /// as a capsule (StadiumBorder) whatever its height.
  static const pill = 999.0;

  /// A small shape inside another: a thumbnail, a bar, a wash.
  static const inset = 12.0;

  /// A field, a notice, a bubble: something inside a card or on the page.
  static const control = 18.0;

  /// A card: anything that holds content on the canvas.
  static const card = 24.0;

  /// The top corners of a sheet rising from the bottom.
  static const sheet = 32.0;

  /// The corner of a shape [inset] points inside one with corner [outer]:
  /// concentric, never smaller than the inset corner.
  static double inside(double outer, double inset) => (outer - inset).clamp(inset, outer).toDouble();
}

/// The spacing steps, on a 4-point grid.
class QSpace {
  QSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const xxxl = 32.0;

  /// The page's side margin.
  static const page = 20.0;
}

ThemeData buildQamarTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: QColors.canvas,
    canvasColor: QColors.canvas,
    colorScheme: base.colorScheme.copyWith(
      primary: QColors.ink,
      onPrimary: QColors.onInk,
      secondary: QColors.ink,
      onSecondary: QColors.onInk,
      surface: QColors.surface,
      onSurface: QColors.ink,
      error: QColors.ink,
      onError: QColors.onInk,
      outline: QColors.hairlineStrong,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: QColors.ink,
      displayColor: QColors.ink,
    ),
    // The switch, inverted rather than coloured: on is a white track under a
    // black thumb, off a raised grey track with a white one.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled)
          ? QColors.inkDisabled
          : s.contains(WidgetState.selected)
              ? QColors.onInk
              : QColors.ink),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? QColors.ink : QColors.surfaceHigh),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.transparent : QColors.hairlineStrong),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: QColors.ink,
      selectionColor: QColors.hairlineStrong,
      selectionHandleColor: QColors.ink,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: QColors.ink, linearTrackColor: QColors.surfaceHigh, circularTrackColor: QColors.surfaceHigh),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: QColors.hairline,
  );
}

/// Shared card and pill decorations so screens don't hand-roll BoxDecoration.
class QDecor {
  QDecor._();

  /// A card on the canvas: a solid surface and a hairline. No shadow: on
  /// black a shadow has nothing to darken; a lighter surface is the lift.
  static BoxDecoration card({
    Color color = QColors.surface,
    Color border = QColors.hairline,
    double radius = QRadii.card,
  }) =>
      BoxDecoration(
        color: color,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(radius),
      );

  /// The one filled button: white, round-ended, black words. The brightest
  /// thing on the screen, and so the one thing to do.
  static const inkButton = BoxDecoration(color: QColors.ink, borderRadius: BorderRadius.all(Radius.circular(QRadii.pill)));

  /// A capsule drawn by its edge: an outline button, a chip, a tag. [fill]
  /// shows while it is pressed or selected.
  static BoxDecoration capsule({Color edge = QColors.hairlineStrong, Color fill = Colors.transparent}) => BoxDecoration(
        color: fill,
        border: Border.all(color: edge),
        borderRadius: const BorderRadius.all(Radius.circular(QRadii.pill)),
      );
}

extension QTextStyleShortcuts on BuildContext {
  bool get isArabicDir => Directionality.of(this) == TextDirection.rtl;
}
