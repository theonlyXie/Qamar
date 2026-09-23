import 'package:flutter/material.dart';
import 'colors.dart';

/// Four corners and the pill (the scorecard counted thirteen radii, 3 to
/// 28): each shape takes the corner of what it is, not of the screen it is
/// on (radii_test.dart).
class QRadii {
  QRadii._();

  /// Anything round-ended: chips, pills, toggles, the composer.
  static const pill = 999.0;

  /// A small shape inside another: a bar, a thumbnail, a hover wash.
  static const inset = 10.0;

  /// A control or a field: buttons, inputs, the wheels, a notice.
  static const control = 16.0;

  /// A card: anything that holds content, a bubble included.
  static const card = 20.0;

  /// The top corners of a sheet rising from the bottom.
  static const sheet = 28.0;
}

class QSpace {
  QSpace._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
}

ThemeData buildQamarTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: QColors.bgBottom,
    colorScheme: base.colorScheme.copyWith(
      primary: QColors.violet,
      secondary: QColors.cyan,
      surface: QColors.cardDeep,
      error: QColors.red,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: QColors.textPrimary,
      displayColor: QColors.textPrimary,
    ),
    // Switches in the palette, not Material's stock grey (scorecard 08):
    // on is the brand's deep violet under a white thumb, off a card-coloured
    // track with a visible edge and a muted thumb.
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.disabled)
          ? QColors.textDisabled
          : s.contains(WidgetState.selected)
              ? QColors.onAccent
              : QColors.textMuted),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? QColors.violetDeep : QColors.cardMid),
      trackOutlineColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.transparent : QColors.borderStrong),
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: QColors.borderSoft,
  );
}

/// Shared card/pill decorations so screens don't hand-roll BoxDecoration.
class QDecor {
  QDecor._();

  static BoxDecoration card({
    Color color = QColors.cardDeep,
    Gradient? gradient,
    Color border = QColors.borderSoft,
    double radius = QRadii.card,
    List<BoxShadow>? shadow,
  }) =>
      BoxDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(radius),
        boxShadow: shadow,
      );

  static BoxDecoration pillOutline({
    Color border = QColors.borderSoft,
    Color fill = Colors.transparent,
  }) =>
      BoxDecoration(
        color: fill,
        border: Border.all(color: border),
        borderRadius: BorderRadius.circular(QRadii.pill),
      );

  /// The one filled button. No shadow: on a near-black ground a cast shadow
  /// has nothing to darken, and under a Material it was clipped to the
  /// button's square bounds, which drew dark slabs at the rounded corners.
  /// The gradient is already the brightest thing on the screen; that is the
  /// elevation.
  static BoxDecoration gradientButton({Gradient gradient = QColors.brandGradient, double radius = QRadii.control}) =>
      BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
      );
}

extension QTextStyleShortcuts on BuildContext {
  bool get isArabicDir => Directionality.of(this) == TextDirection.rtl;
}
