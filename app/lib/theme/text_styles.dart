import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'colors.dart';

/// Three font families from the prototype, each exposed as a sized builder
/// so call sites read like the original `font: weight size/lineHeight family`.
///
/// The families are bundled in the app (see pubspec.yaml) rather than fetched
/// from Google Fonts at runtime: the first launch of an Arabic-first app must
/// not depend on a download landing, or the entire UI is tofu boxes until it
/// does.
///
/// ## The scale
///
/// Text is set at a size on the scale and nowhere between (each builder
/// asserts it, so any test that draws an off-scale size fails):
///
///  * reading and controls, [textSizes]: 11 caption (eyebrows, fine print),
///    12 footnote (secondary lines), 13 label (controls, metadata), 14 body
///    (paragraphs in cards), 15 lead (card titles, the conversation), 17
///    headline (buttons, sheet headlines). Nothing under 11.
///  * the serif display, [displaySizes], each with its own line height: 20
///    (a header's name), 24 (a sheet's title), 30 (a page's title), 40 (the
///    hero: the welcome, the paywall).
///  * figures, [figureSizes]: 20, 28, 34, 40.
///
/// ## Tracking
///
/// Set by size, never by the call site ([tracking]): none at reading sizes,
/// where the families' own spacing is drawn for them, and tighter as type
/// grows past 20, the way Inter's dynamic metrics run, so a 40pt title does
/// not fall apart into letters. Arabic is never tracked: space between
/// joined letters breaks the word. Display text says whether it is Arabic
/// ([display]'s `ar`), body text is never tracked (it carries both
/// scripts), and figures are digits, which do not join.
class QText {
  QText._();

  static const textSizes = <double>[11, 12, 13, 14, 15, 17];
  static final displaySizes = <double, double>{20: 24, 24: 30, 30: 38, 40: 48};
  static const figureSizes = <double>[20, 28, 34, 40];

  /// Tracking for Latin type at [size], in points: 0 under 20, then
  /// size × (−0.0223 + 0.185·e^(−0.1745·size)), about −1.7% at 20 and
  /// −2.2% at 40.
  static double tracking(double size) => size < 20 ? 0 : size * (-0.0223 + 0.185 * math.exp(-0.1745 * size));

  /// Whether [text] has an Arabic letter in it (Arabic-Indic digits do not
  /// count: they do not join), for [display]'s `ar` when the words are not
  /// the interface's own, like a person's name.
  static bool arabic(String text) => _arabicLetter.hasMatch(text);
  static final _arabicLetter = RegExp('[\u0621-\u064A\u066E-\u06D3\u06FA-\u06FF\u0750-\u077F\uFB50-\uFDFF\uFE70-\uFEFC]');

  /// Neither the serif nor Inter carries Arabic. Any Arabic word or Eastern
  /// digit set in those styles falls back to the bundled Noto rather than to
  /// whatever the phone happens to have, so a streak count, an EGP price or a
  /// greeting looks the same on every device.
  static const _arabicFallback = ['Noto Sans Arabic'];

  /// Cormorant Garamond — display/serif headers ("Qamar", screen titles), at
  /// one of [displaySizes] and its line height. [ar]: the text is Arabic
  /// (it falls back to Noto Sans Arabic), so it is not tracked.
  static TextStyle display({
    required double size,
    required bool ar,
    FontWeight weight = FontWeight.w300,
    Color color = QColors.textPrimary,
  }) {
    assert(displaySizes.containsKey(size), 'display at $size is off the scale: ${displaySizes.keys}');
    return TextStyle(
      fontFamily: 'Cormorant Garamond',
      fontFamilyFallback: _arabicFallback,
      fontSize: size,
      height: (displaySizes[size] ?? size * 1.25) / size,
      fontWeight: weight,
      color: color,
      letterSpacing: ar ? 0 : tracking(size),
    );
  }

  /// Noto Sans Arabic — primary bilingual body/UI text, renders both scripts.
  /// Never tracked. What Noto does not carry (the arrows in You's "Settings →
  /// Accessibility" and its Arabic "←", which drew as boxes) falls back to
  /// the bundled Inter.
  static const _bodyFallback = ['Inter'];
  static TextStyle body({
    required double size,
    double? height,
    FontWeight weight = FontWeight.w400,
    Color color = QColors.textPrimary,
  }) {
    assert(textSizes.contains(size), 'body at $size is off the scale: $textSizes');
    return TextStyle(
      fontFamily: 'Noto Sans Arabic',
      fontFamilyFallback: _bodyFallback,
      fontSize: size,
      height: height != null ? height / size : null,
      fontWeight: weight,
      color: color,
      // Zero, not null: left null it inherits Material's bodyMedium +0.25,
      // which tracked every line of the app, Arabic included.
      letterSpacing: 0,
    );
  }

  /// Inter — numerals, kcal/macro figures, latin UI labels: at a reading
  /// size, or at one of [figureSizes], where it is tracked tighter. [ar]: a
  /// figure that carries an Arabic word ("٢ لتر"), so it is not tracked.
  static TextStyle number({
    required double size,
    double? height,
    FontWeight weight = FontWeight.w400,
    Color color = QColors.textPrimary,
    bool ar = false,
  }) {
    assert(textSizes.contains(size) || figureSizes.contains(size), 'number at $size is off the scale: $textSizes, $figureSizes');
    return TextStyle(
      fontFamily: 'Inter',
      fontFamilyFallback: _arabicFallback,
      fontSize: size,
      height: height != null ? height / size : null,
      fontWeight: weight,
      color: color,
      letterSpacing: ar ? 0 : tracking(size),
    );
  }
}
