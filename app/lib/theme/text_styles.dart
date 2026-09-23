import 'package:flutter/material.dart';
import 'colors.dart';

/// Three font families from the prototype, each exposed as a sized builder
/// so call sites read like the original `font: weight size/lineHeight family`.
///
/// The families are bundled in the app (see pubspec.yaml) rather than fetched
/// from Google Fonts at runtime: the first launch of an Arabic-first app must
/// not depend on a download landing, or the entire UI is tofu boxes until it
/// does.
class QText {
  QText._();

  /// Neither the serif nor Inter carries Arabic. Any Arabic word or Eastern
  /// digit set in those styles falls back to the bundled Noto rather than to
  /// whatever the phone happens to have, so a streak count, an EGP price or a
  /// greeting looks the same on every device.
  static const _arabicFallback = ['Noto Sans Arabic'];

  /// Cormorant Garamond — display/serif headers ("Qamar", screen titles).
  static TextStyle display({
    required double size,
    double? height,
    FontWeight weight = FontWeight.w300,
    Color color = QColors.textPrimary,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: 'Cormorant Garamond',
        fontFamilyFallback: _arabicFallback,
        fontSize: size,
        height: height != null ? height / size : null,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// Noto Sans Arabic — primary bilingual body/UI text, renders both scripts.
  static TextStyle body({
    required double size,
    double? height,
    FontWeight weight = FontWeight.w400,
    Color color = QColors.textPrimary,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: 'Noto Sans Arabic',
        fontSize: size,
        height: height != null ? height / size : null,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );

  /// Inter — numerals, kcal/macro figures, latin UI labels.
  static TextStyle number({
    required double size,
    double? height,
    FontWeight weight = FontWeight.w400,
    Color color = QColors.textPrimary,
    double? letterSpacing,
  }) =>
      TextStyle(
        fontFamily: 'Inter',
        fontFamilyFallback: _arabicFallback,
        fontSize: size,
        height: height != null ? height / size : null,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );
}
