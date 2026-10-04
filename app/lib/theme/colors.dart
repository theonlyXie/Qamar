import 'package:flutter/material.dart';

/// Qamar's palette (the qamar-design skill, .claude/skills/qamar-design): the
/// Nutri AI kit's flat near-black ground and its four pastels, with Qamar's
/// burgundy where the kit has its orange.
///
/// The ground is one grey, and everything that sits on it is a step lighter:
/// a card, then a control, then a control's circle. Content that matters
/// most sits on a pastel card in black ink: the day's calories on lavender,
/// protein on mint, carbs on lime, fat on coral. Burgundy marks what a finger
/// does and what has been chosen: the primary button, the chosen segment, a
/// switch that is on, the tab the person is on. It never says how something
/// went; the one other colour, [error], is a field's own complaint and
/// nothing else (colors_test.dart holds all of it).
///
/// No hex is written outside lib/theme (the moon's own greys in
/// widgets/moon.dart aside), and no token is kept that nothing draws.
class QColors {
  QColors._();

  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);

  /// The page's ground: the kit's grey 600, a black that is not quite.
  static const canvas = Color(0xFF121212);

  /// What sits on the ground, a step lighter each: a card, a grouped list, a
  /// row, a sheet, a dialog (grey 500); a control on the ground or on a card —
  /// the tab bar, a back button, a sign-in button, a field's edge (grey 400);
  /// a circle on a control, a track, a pressed control (grey 300). Flat: no
  /// shadow and no glass.
  static const surface = Color(0xFF232220);
  static const surfaceRaised = Color(0xFF2F2F2F);
  static const surfaceHigh = Color(0xFF474747);

  /// Three steps of ink on the dark, each passing AA (4.5:1) on the ground,
  /// the card and the control (colors_test.dart): the words, then what
  /// supports them (grey 200), then captions and hints. Past the third step
  /// hierarchy comes from size and weight.
  static const ink = white;
  static const inkSecondary = Color(0xFFC3C3C3);
  static const inkTertiary = Color(0xFF9A9A9A);

  /// The label of a control with nothing to do: below AA on purpose, and
  /// still at least 3:1 on the card and the control so it is there to see.
  static const inkDisabled = Color(0xFF7A7A7A);

  /// Words on white and on a pastel: the kit's black.
  static const onInk = canvas;

  /// The four pastels, the kit's accents. A pastel is a card's whole ground,
  /// with [onPastel] words on it, never a line or a word on the dark.
  static const lavender = Color(0xFFDDC0FF);
  static const lime = Color(0xFFF5F378);
  static const mint = Color(0xFF45C588);
  static const coral = Color(0xFFFF6F43);

  /// Ink on a pastel: black for the words, 80% black for what supports them
  /// (4.5:1 or better on all four), and black at 12% for a bar's unlit track
  /// and a glyph's circle.
  static const onPastel = canvas;
  static const onPastelSecondary = Color(0xCC121212);
  static const pastelTrack = Color(0x1F121212);

  /// Burgundy, Qamar's own: the fill of what a finger does. White on it
  /// reads at 8.9:1. One burgundy action to a screen.
  static const accent = Color(0xFF8E1B34);

  /// The fill while it is pressed: a step deeper.
  static const accentPressed = Color(0xFF751529);

  /// Burgundy as a word or a line on the dark: a text action, a bar filling
  /// on a dark card, a chosen radio's ring. Lighter than the fill so it
  /// reads on the ground and the card.
  static const accentInk = Color(0xFFE8768D);

  /// Burgundy washed into a surface: a chosen row.
  static const accentWash = Color(0x478E1B34);

  /// Words and glyphs on burgundy.
  static const onAccent = white;

  /// Two edges: a field's and a divider's (grey 400), and a strong one for
  /// a control that must read as a boundary on the card (grey 300). A focused
  /// field takes the ink itself.
  static const hairline = surfaceRaised;
  static const hairlineStrong = surfaceHigh;

  /// A field that has something wrong with it: its edge, the kit's red. The
  /// words under it stay in the full ink: this red passes 3:1 as a mark on
  /// the ground and the card, not AA as text.
  static const error = Color(0xFFC93838);

  /// A control over a photo or the camera (the scan screen's tiles, a close
  /// button on a picture): the ground at half strength, so the picture still
  /// shows round it, and a step stronger while pressed.
  static const overPhoto = Color(0x80121212);
  static const overPhotoPressed = Color(0xB3121212);

  /// What a sheet or a dialog dims the page with: black at 50%, as the kit
  /// takes #121212 to #090909 behind a dialog. One strength for every modal.
  static const scrim = Color(0x80000000);
}

/// Other people's marks, drawn the way their owners require. Google's sign-in
/// branding asks for the "G" in its four colours; a grey G reads as a letter,
/// not as "sign in with Google". These are the only colours in the app that
/// are not ours, and they appear on the account sheet's Google button and
/// nowhere else (colors_test.dart holds both).
class QBrandMarks {
  QBrandMarks._();

  static const googleBlue = Color(0xFF4285F4);
  static const googleRed = Color(0xFFEA4335);
  static const googleYellow = Color(0xFFFBBC05);
  static const googleGreen = Color(0xFF34A853);
}
