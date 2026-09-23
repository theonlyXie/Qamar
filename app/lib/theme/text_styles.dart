import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'colors.dart';

/// Type, the liquid-glass way (.claude/skills/liquid-glass): one grotesk, sized
/// on Apple's text styles, with Arabic in its own face.
///
/// Latin is set in Inter, the open face closest to Apple's San Francisco;
/// Arabic, and the Arabic-Indic digits, in Noto Sans Arabic. Every style names
/// Inter first and Noto Sans Arabic as its fallback, so a line in either
/// language — or both, like a dish name in an English sentence — draws each
/// script in its own face with nothing to decide at the call site. Both are
/// bundled (pubspec.yaml): an Arabic-first app must not wait on a download to
/// draw its words.
///
/// ## The scale
///
/// Apple's Dynamic Type styles at the default size, and nowhere between (each
/// builder asserts it, so a test that draws an off-scale size fails):
///
///  * reading and controls, [textSizes]: 11 caption 2, 12 caption, 13
///    footnote, 15 subheadline, 16 callout, 17 body and headline — the
///    conversation, rows, buttons. Nothing under 11.
///  * titles, [displaySizes], each with its line height: 20 title 3, 22 title
///    2, 28 title 1, 34 large title (a page's name).
///  * figures, [figureSizes]: 20, 28, 34, 48, and 56 for a screen's one hero
///    figure (HeroNumber) — tabular, so a changing number does not shuffle
///    its neighbours.
///
/// ## Tracking
///
/// Set by size, never by the call site ([tracking]): none at reading sizes,
/// tighter as type grows past 20, the way SF and Inter's own metrics run.
/// Arabic is never tracked: space between joined letters breaks the word.
/// Titles say whether they are Arabic ([display]'s `ar`); body text is never
/// tracked (it carries both scripts); figures are digits, which do not join.
class QText {
  QText._();

  static const textSizes = <double>[11, 12, 13, 15, 16, 17];

  /// Apple's line height for each reading size, used when a call site does
  /// not set its own.
  static final _leading = <double, double>{11: 13, 12: 16, 13: 18, 15: 20, 16: 21, 17: 22};

  static final displaySizes = <double, double>{20: 25, 22: 28, 28: 34, 34: 41};
  static const figureSizes = <double>[20, 28, 34, 48, 56];

  /// Tracking for Latin type at [size], in points: 0 under 20, then
  /// size × (−0.0223 + 0.185·e^(−0.1745·size)), about −1.7% at 20 and
  /// −2.2% at 34.
  static double tracking(double size) => size < 20 ? 0 : size * (-0.0223 + 0.185 * math.exp(-0.1745 * size));

  /// Whether [text] has an Arabic letter in it (Arabic-Indic digits do not
  /// count: they do not join), for [display]'s `ar` when the words are not
  /// the interface's own, like a person's name.
  static bool arabic(String text) => _arabicLetter.hasMatch(text);
  static final _arabicLetter = RegExp('[ء-يٮ-ۓۺ-ۿݐ-ݿﭐ-﷿ﹰ-ﻼ]');

  static const _family = 'Inter';
  static const _fallback = ['Noto Sans Arabic'];

  /// A title: a page's name (34), a sheet's (22), a card's lead figure line
  /// (20), at one of [displaySizes] and its line height. Bold, as Apple's
  /// large titles are. [ar]: the text is Arabic, so it is not tracked.
  static TextStyle display({
    required double size,
    required bool ar,
    FontWeight weight = FontWeight.w700,
    Color color = QColors.ink,
  }) {
    assert(displaySizes.containsKey(size), 'display at $size is off the scale: ${displaySizes.keys}');
    return TextStyle(
      fontFamily: _family,
      fontFamilyFallback: _fallback,
      fontSize: size,
      height: (displaySizes[size] ?? size * 1.2) / size,
      fontWeight: weight,
      color: color,
      letterSpacing: ar ? 0 : tracking(size),
    );
  }

  /// Reading and control text at one of [textSizes]. Never tracked: it
  /// carries both scripts, and Arabic must not be.
  static TextStyle body({
    required double size,
    double? height,
    FontWeight weight = FontWeight.w400,
    Color color = QColors.ink,
  }) {
    assert(textSizes.contains(size), 'body at $size is off the scale: $textSizes');
    return TextStyle(
      fontFamily: _family,
      fontFamilyFallback: _fallback,
      fontSize: size,
      height: (height ?? _leading[size] ?? size * 1.3) / size,
      fontWeight: weight,
      color: color,
      // Zero, not null: left null it inherits Material's bodyMedium +0.25,
      // which would track every line of the app, Arabic included.
      letterSpacing: 0,
    );
  }

  /// A figure: a count, a price, a macro, at a reading size or one of
  /// [figureSizes], with tabular digits. [ar]: a figure that carries an
  /// Arabic word ("٢ لتر"), so it is not tracked.
  static TextStyle number({
    required double size,
    double? height,
    FontWeight weight = FontWeight.w500,
    Color color = QColors.ink,
    bool ar = false,
  }) {
    assert(textSizes.contains(size) || figureSizes.contains(size), 'number at $size is off the scale: $textSizes, $figureSizes');
    return TextStyle(
      fontFamily: _family,
      fontFamilyFallback: _fallback,
      fontSize: size,
      height: (height ?? _leading[size] ?? size * 1.15) / size,
      fontWeight: weight,
      color: color,
      letterSpacing: ar ? 0 : tracking(size),
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// A small label over a group or a figure, the eyebrow: 12, semibold, in
  /// the third ink. Latin eyebrows are set in capitals with a little
  /// tracking so short words read as a label; Arabic has no capitals and is
  /// never tracked, so it is left as it is.
  static TextStyle eyebrow({required bool ar, Color color = QColors.inkTertiary}) => TextStyle(
        fontFamily: _family,
        fontFamilyFallback: _fallback,
        fontSize: 12,
        height: 16 / 12,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: ar ? 0 : 0.6,
      );

  /// [text] as an eyebrow shows it: in capitals for Latin, as written for
  /// Arabic.
  static String eyebrowText(String text, {required bool ar}) => ar ? text : text.toUpperCase();
}
