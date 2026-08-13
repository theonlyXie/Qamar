import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

/// Three font families from the prototype, each exposed as a sized builder
/// so call sites read like the original `font: weight size/lineHeight family`.
class QText {
  QText._();

  /// Cormorant Garamond — display/serif headers ("Qamar", screen titles).
  static TextStyle display({
    required double size,
    double? height,
    FontWeight weight = FontWeight.w300,
    Color color = QColors.textBrand,
    double? letterSpacing,
  }) =>
      GoogleFonts.cormorantGaramond(
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
      GoogleFonts.notoSansArabic(
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
      GoogleFonts.inter(
        fontSize: size,
        height: height != null ? height / size : null,
        fontWeight: weight,
        color: color,
        letterSpacing: letterSpacing,
      );
}
