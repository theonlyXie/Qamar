import 'package:flutter/material.dart';
import 'colors.dart';

/// Type, the Nutri AI kit's (the qamar-design skill): Space Grotesk for
/// Latin, on the kit's own scale, with Arabic in its own face.
///
/// Latin is set in Space Grotesk, the kit's grotesk; Arabic, and the
/// Arabic-Indic digits, in Noto Sans Arabic; Inter is the last fallback, for
/// the odd mark Space Grotesk does not draw (✓). Every style names all three,
/// so a line in either language — or both, like a dish name in an English
/// sentence — draws each script in its own face with nothing to decide at the
/// call site. All are bundled (pubspec.yaml): an Arabic-first app must not
/// wait on a download to draw its words.
///
/// ## The scale
///
/// The kit's type styles, and nowhere between (each builder asserts it, so a
/// test that draws an off-scale size fails):
///
///  * reading and controls, [textSizes], each with the kit's leading: 12 a
///    badge's word, 13 footnote, 15 subheadline and body 2, 16 callout (a
///    button's label), 17 body, 18 headline. Nothing under 12.
///  * titles, [displaySizes]: 20 title 3 (a card's title), 24 title 2 (a
///    page's or a sheet's name), 28 title 1, 34 large title. Bold.
///  * figures, [figureSizes]: 20, 24, 28, 34, 48, and 56 for a screen's one
///    hero figure (HeroNumber) — tabular, so a changing number does not
///    shuffle its neighbours.
///
/// Nothing is tracked: Space Grotesk is set as drawn, and Arabic must never
/// be (space between joined letters breaks the word).
class QText {
  QText._();

  static const textSizes = <double>[12, 13, 15, 16, 17, 18];

  /// The kit's line height for each reading size, used when a call site does
  /// not set its own.
  static final _leading = <double, double>{12: 16, 13: 19, 15: 22, 16: 24, 17: 24, 18: 27};

  static final displaySizes = <double, double>{20: 30, 24: 36, 28: 42, 34: 51};
  static const figureSizes = <double>[20, 24, 28, 34, 48, 56];

  /// Tracking at [size]: none. Kept as the one place a size's tracking is
  /// decided, so a future face can bring its own table.
  static double tracking(double size) => 0;

  /// Whether [text] has an Arabic letter in it (Arabic-Indic digits do not
  /// count: they do not join), for [display]'s `ar` when the words are not
  /// the interface's own, like a person's name.
  static bool arabic(String text) => _arabicLetter.hasMatch(text);
  static final _arabicLetter = RegExp('[ء-يٮ-ۓۺ-ۿݐ-ݿﭐ-﷿ﹰ-ﻼ]');

  static const family = 'Space Grotesk';
  static const fallback = ['Noto Sans Arabic', 'Inter'];

  /// A title: a page's name (24), a card's (20), a hero line (28, 34), at one
  /// of [displaySizes] and its line height. Bold, as the kit's titles are.
  /// [ar]: the text is Arabic (kept for the call sites that say so; nothing
  /// is tracked either way).
  static TextStyle display({
    required double size,
    required bool ar,
    FontWeight weight = FontWeight.w700,
    Color color = QColors.ink,
  }) {
    assert(displaySizes.containsKey(size), 'display at $size is off the scale: ${displaySizes.keys}');
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: size,
      height: (displaySizes[size] ?? size * 1.5) / size,
      fontWeight: weight,
      color: color,
      letterSpacing: 0,
    );
  }

  /// Reading and control text at one of [textSizes].
  static TextStyle body({
    required double size,
    double? height,
    FontWeight weight = FontWeight.w400,
    Color color = QColors.ink,
  }) {
    assert(textSizes.contains(size), 'body at $size is off the scale: $textSizes');
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: size,
      height: (height ?? _leading[size] ?? size * 1.4) / size,
      fontWeight: weight,
      color: color,
      // Zero, not null: left null it inherits Material's bodyMedium +0.25,
      // which would track every line of the app, Arabic included.
      letterSpacing: 0,
    );
  }

  /// A figure: a count, a price, a macro, at a reading size or one of
  /// [figureSizes], with tabular digits. [ar]: a figure that carries an
  /// Arabic word ("٢ لتر").
  static TextStyle number({
    required double size,
    double? height,
    FontWeight weight = FontWeight.w500,
    Color color = QColors.ink,
    bool ar = false,
  }) {
    assert(textSizes.contains(size) || figureSizes.contains(size), 'number at $size is off the scale: $textSizes, $figureSizes');
    return TextStyle(
      fontFamily: family,
      fontFamilyFallback: fallback,
      fontSize: size,
      height: (height ?? _leading[size] ?? size * 1.2) / size,
      fontWeight: weight,
      color: color,
      letterSpacing: 0,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
  }

  /// A small label over a group or a card's figure: the kit's caption 2, 15
  /// semibold, in sentence case (the kit sets no label in capitals), in the
  /// second ink on the dark or [color] on a pastel.
  static TextStyle eyebrow({required bool ar, Color color = QColors.inkSecondary}) => TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: 15,
        height: 22 / 15,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0,
      );

  /// [text] as an eyebrow shows it: as written, in both languages.
  static String eyebrowText(String text, {required bool ar}) => text;
}
