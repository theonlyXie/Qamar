import 'package:flutter/material.dart';
import 'colors.dart';
import 'text_styles.dart';

/// The corners (the qamar-design skill), the Nutri AI kit's: four radii and
/// the pill, each shape taking the corner of what it is, and a shape inside
/// another keeping the outer corner less the space between them, so the two
/// stay concentric (radii_test.dart).
class QRadii {
  QRadii._();

  /// A chip, a segmented control and its chosen segment, the tab bar, a bar
  /// of progress: drawn as a capsule (StadiumBorder) whatever its height.
  static const pill = 999.0;

  /// Something a finger presses or types into, drawn as a rounded rectangle:
  /// a button, a field, a notice, the selection band of a wheel.
  static const control = 12.0;

  /// A shape inside a card: a tile inside a pastel card, a photo, a bubble in
  /// the conversation, a group of rows.
  static const inset = 16.0;

  /// A card: a pastel card, a list, a photo card, a dialog.
  static const card = 24.0;

  /// The top corners of a sheet rising from the bottom.
  static const sheet = 32.0;

  /// The corner of a shape [inset] points inside one with corner [outer]:
  /// concentric, never smaller than the control corner.
  static double inside(double outer, double inset) => (outer - inset).clamp(control, outer).toDouble();
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

  /// The page's side margin: the kit's 20.
  static const page = 20.0;
}

ThemeData buildQamarTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  OutlineInputBorder edge(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(QRadii.control)),
        borderSide: BorderSide(color: c, width: w),
      );
  return base.copyWith(
    scaffoldBackgroundColor: QColors.canvas,
    canvasColor: QColors.canvas,
    colorScheme: base.colorScheme.copyWith(
      primary: QColors.accent,
      onPrimary: QColors.onAccent,
      secondary: QColors.accentInk,
      onSecondary: QColors.onInk,
      surface: QColors.surface,
      onSurface: QColors.ink,
      error: QColors.error,
      onError: QColors.ink,
      outline: QColors.hairlineStrong,
    ),
    textTheme: base.textTheme.apply(
      fontFamily: QText.family,
      fontFamilyFallback: QText.fallback,
      bodyColor: QColors.ink,
      displayColor: QColors.ink,
    ),
    // The kit's field: the ground inside a grey edge, the edge white while it
    // is being typed in and red when something is wrong with it.
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: QColors.canvas,
      hintStyle: QText.body(size: 15, color: QColors.inkTertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: edge(QColors.hairlineStrong),
      enabledBorder: edge(QColors.hairlineStrong),
      focusedBorder: edge(QColors.ink),
      errorBorder: edge(QColors.error),
      focusedErrorBorder: edge(QColors.error),
      // The red is the edge's: the words under it are the full ink, which
      // passes AA where the red would not.
      errorStyle: QText.body(size: 13, color: QColors.ink),
    ),
    // The kit's switch: on is a burgundy track under a white thumb, off the
    // raised grey with a white one.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled) ? QColors.inkDisabled : QColors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? QColors.accent : QColors.surfaceHigh),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    textSelectionTheme: const TextSelectionThemeData(
      cursorColor: QColors.ink,
      selectionColor: QColors.accentWash,
      selectionHandleColor: QColors.accentInk,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: QColors.accentInk, linearTrackColor: QColors.hairline, circularTrackColor: QColors.hairline),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: QColors.hairline,
  );
}

/// Shared decorations, so screens don't hand-roll BoxDecoration.
class QDecor {
  QDecor._();

  /// A card on the dark (the qamar-design skill): the kit's grey 500, flat,
  /// with an edge a step lighter so it holds its shape on the ground. No
  /// shadow and no glass.
  ///
  /// [color] asks for a raised card (surfaceRaised: pressed, or a shape on a
  /// card); [border] as hairlineStrong for one that must read as a boundary
  /// (chosen), accent for the chosen one of several.
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

  /// A pastel card (the kit's lavender, lime, mint, coral), with black words
  /// on it: where the figures that matter most sit. No edge.
  static BoxDecoration pastel(Color color, {double radius = QRadii.card}) => BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      );

  /// A capsule drawn by its edge: a tag, a quiet chip. [fill] shows while it
  /// is pressed or selected.
  static BoxDecoration capsule({Color edge = QColors.hairlineStrong, Color fill = Colors.transparent}) => BoxDecoration(
        color: fill,
        border: Border.all(color: edge),
        borderRadius: const BorderRadius.all(Radius.circular(QRadii.pill)),
      );

  /// A segmented control's track: the kit's white capsule.
  static const segmentTrack = BoxDecoration(
    color: QColors.white,
    borderRadius: BorderRadius.all(Radius.circular(QRadii.pill)),
  );

  /// The chosen segment: a burgundy capsule with white words on it, as the
  /// kit fills its chosen segment with its own colour.
  ///
  /// Its edge is a plain Border, as [segmentRest]'s is, so the segment can
  /// animate between the two.
  static const segmentThumb = BoxDecoration(
    color: QColors.accent,
    border: Border.fromBorderSide(BorderSide(color: QColors.accent)),
    borderRadius: BorderRadius.all(Radius.circular(QRadii.pill)),
  );

  /// A segment not chosen: nothing drawn, the same shape; black words on the
  /// white track.
  static const segmentRest = BoxDecoration(
    color: Colors.transparent,
    border: Border.fromBorderSide(BorderSide(color: Colors.transparent)),
    borderRadius: BorderRadius.all(Radius.circular(QRadii.pill)),
  );
}

extension QTextStyleShortcuts on BuildContext {
  bool get isArabicDir => Directionality.of(this) == TextDirection.rtl;
}
