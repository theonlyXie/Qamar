import 'package:flutter/material.dart';

/// Qamar's palette: black and white, and nothing else (the mono-glass skill,
/// .claude/skills/mono-glass).
///
/// Black is the ground and white is the ink. Every grey in between is white
/// laid over black at some strength — written here as the solid grey it makes,
/// so a contrast ratio can be checked exactly — and every token is achromatic
/// (colors_test.dart): no hue anywhere in the interface. What a hue used to
/// say (good news, a warning, an error, something selected), the app now says
/// with a glyph, a word, a weight or an inverted fill, which also reaches the
/// people a colour never did.
///
/// No hex is written outside lib/theme (the moon's own greys in
/// widgets/moon.dart aside), and no token is kept that nothing draws.
class QColors {
  QColors._();

  /// The two colours.
  static const black = Color(0xFF000000);
  static const white = Color(0xFFFFFFFF);

  /// The page's ground: pure black, which an OLED screen draws as off.
  static const canvas = black;

  /// Three surfaces, each a step lighter, for content that sits on the
  /// canvas: a card or a grouped list; something raised on it (a field, the
  /// person's own words in the conversation, a pressed row); and a control
  /// on a card or a selected row. Content is never drawn on glass; these are
  /// what content sits on.
  static const surface = Color(0xFF121212);
  static const surfaceRaised = Color(0xFF1E1E1E);
  static const surfaceHigh = Color(0xFF2C2C2C);

  /// Three steps of ink, each passing AA (4.5:1) on every surface above and
  /// on the glass (colors_test.dart): the words, then what supports them, then
  /// captions and hints. Hierarchy past the third step comes from size and
  /// weight, never from fading further.
  static const ink = white;
  static const inkSecondary = Color(0xFFC7C7C7);
  static const inkTertiary = Color(0xFF999999);

  /// The label of a control with nothing to do: the one place ink sits below
  /// AA, on purpose, and still at least 3:1 so it is there to see.
  static const inkDisabled = Color(0xFF666666);

  /// Words and glyphs on a white fill (the primary button, a selected chip,
  /// the send button): black.
  static const onInk = black;

  /// Two edges: the hairline every card, row and field draws, and a strong one
  /// for what must read as a boundary (a selected control, a focused field).
  static const hairline = Color(0x24FFFFFF);
  static const hairlineStrong = Color(0x47FFFFFF);

  /// Liquid Glass, the floating control layer (QGlass): the orb, the tree's
  /// buttons, the composer, a floating back button, a sheet's grabber bar.
  /// A breath of white over whatever is behind it, blurred; a specular edge
  /// that is bright at the top and fades down the sides; and, when the phone
  /// asks for more contrast, a solid fallback.
  static const glassFill = Color(0x1FFFFFFF);
  static const glassFillPressed = Color(0x2EFFFFFF);
  static const glassFillClear = Color(0x0FFFFFFF);
  static const glassEdgeTop = Color(0x66FFFFFF);
  static const glassEdgeBottom = Color(0x14FFFFFF);
  static const glassSolid = surfaceRaised;

  /// The glass's lens: the upper part of a piece of glass is this much
  /// brighter, fading to nothing half way down, as light caught in a curved
  /// surface is.
  static const glassLens = Color(0x14FFFFFF);

  /// A dot that is not lit, in a ring or a matrix: white at 11%, Nothing's
  /// own "0% brightness" (#1C1C1C on black). Faint, but there, so the shape
  /// of the whole is always seen and the lit dots read as a count of it.
  static const dotOff = Color(0x1CFFFFFF);

  /// What a sheet or an overlay dims the page with: black at 64%. One
  /// strength for every modal, so opening one always reads the same.
  static const scrim = Color(0xA3000000);
}

/// Other people's marks, drawn the way their owners require. Google's sign-in
/// branding asks for the "G" in its four colours; a grey G reads as a letter,
/// not as "sign in with Google". This is the only colour in the app, it is
/// not ours, and it appears on the account sheet's Google button and nowhere
/// else (colors_test.dart holds both).
class QBrandMarks {
  QBrandMarks._();

  static const googleBlue = Color(0xFF4285F4);
  static const googleRed = Color(0xFFEA4335);
  static const googleYellow = Color(0xFFFBBC05);
  static const googleGreen = Color(0xFF34A853);
}
