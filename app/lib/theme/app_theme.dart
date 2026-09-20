import 'package:flutter/material.dart';
import 'colors.dart';

class QRadii {
  QRadii._();
  static const pill = 999.0;
  static const sm = 12.0;
  static const md = 14.0;
  static const lg = 16.0;
  static const xl = 18.0;
  static const xxl = 20.0;
  static const xxxl = 22.0;
  static const sheet = 26.0;
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
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    dividerColor: QColors.borderFaint,
  );
}

/// Shared card/pill decorations so screens don't hand-roll BoxDecoration.
class QDecor {
  QDecor._();

  static BoxDecoration card({
    Color color = QColors.cardDeep,
    Gradient? gradient,
    Color border = QColors.borderSoft,
    double radius = QRadii.lg,
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

  static BoxDecoration gradientButton({Gradient gradient = QColors.brandGradient, double radius = QRadii.lg}) =>
      BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(color: QColors.blue.withOpacity(0.32), blurRadius: 26, offset: const Offset(0, 10)),
        ],
      );
}

extension QTextStyleShortcuts on BuildContext {
  bool get isArabicDir => Directionality.of(this) == TextDirection.rtl;
}
