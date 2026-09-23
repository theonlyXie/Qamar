import 'package:flutter/material.dart';

/// Qamar's palette: black, white, the greys between them, and one colour of
/// ours, burgundy (the liquid-glass skill, .claude/skills/liquid-glass).
///
/// Black is the ground and white is the ink. Every grey is white laid over
/// black at some strength, written here as the solid grey it makes so a
/// contrast ratio can be checked exactly. Burgundy marks what a finger can do
/// and what has been chosen: the primary button, the send button, a chosen
/// answer, a switch that is on, a bar filling. It never says how something
/// went: there are no success, warning or error colours, and state is said
/// with a glyph, a word or a weight (colors_test.dart holds all of it).
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

  /// Words and glyphs on a white fill (the camera's shutter): black.
  static const onInk = black;

  /// Burgundy, the fill of what a finger does: the primary button, the send
  /// button, a chosen chip, a switch that is on. White on it reads at 8.9:1.
  /// One burgundy fill to a screen at most, so the one thing to do is the
  /// warmest thing there.
  static const accent = Color(0xFF8E1B34);

  /// The fill while it is pressed: a step deeper, as a lit button gives.
  static const accentPressed = Color(0xFF751529);

  /// Burgundy as a line or a mark on the dark: a bar filling, the streak's
  /// ring, a text action, a chosen radio. Lighter than the fill so it reads
  /// against black and glass (at least 4.8:1 on every panel), and never the
  /// colour of reading text.
  static const accentInk = Color(0xFFE8768D);

  /// Burgundy washed into a surface: a chosen row, a tinted panel.
  static const accentWash = Color(0x478E1B34);

  /// Words and glyphs on burgundy.
  static const onAccent = white;

  /// A sheet's frosted ground: the surface at 78%, over the blurred page, so
  /// its words never depend on what is behind it.
  static const glassSheet = Color(0xC7121212);

  /// The page's light: a burgundy glow from above the top of the screen,
  /// fading to black by about the middle (QDecor.ambient). The glass panels
  /// scroll over it, so glass has something to show. Dim enough that the
  /// third ink still passes AA on the brightest panel in it.
  static const ambient = Color(0xFF2A0912);

  /// Two edges: the hairline every card, row and field draws, and a strong one
  /// for what must read as a boundary (a selected control, a focused field).
  static const hairline = Color(0x24FFFFFF);
  static const hairlineStrong = Color(0x47FFFFFF);

  /// Liquid Glass, as panels (QDecor.card, sheets): a card, a grouped list,
  /// a sheet. White over the page's light, brighter at the top as light
  /// caught in a curved surface is, with a rim bright along the top that
  /// fades to the hairline down the sides (QGlassRim). A shape inside a panel
  /// takes the inset step over it.
  static const glassPanel = Color(0x12FFFFFF);
  static const glassPanelTop = Color(0x1AFFFFFF);
  static const glassInset = Color(0x0DFFFFFF);
  static const glassRim = Color(0x47FFFFFF);

  /// A pane raised: pressed, or a pane standing inside another. Flat, a step
  /// over the plain pane's top.
  static const glassRaised = Color(0x24FFFFFF);

  /// Liquid Glass, the floating control layer (QGlass): the orb, the tree's
  /// buttons, the composer, a floating back button, a sheet's grabber bar.
  /// A breath of white over whatever is behind it, blurred; a specular edge
  /// that is bright at the top and fades down the sides; and, when the phone
  /// asks for more contrast, a solid fallback.
  static const glassFill = Color(0x1FFFFFFF);
  static const glassFillPressed = Color(0x2EFFFFFF);
  static const glassFillClear = Color(0x0FFFFFFF);
  static const glassEdgeTop = Color(0x66FFFFFF);

  /// The rim of burgundy glass, catching more of the light.
  static const glassRimTinted = Color(0x8CFFFFFF);
  static const glassEdgeBottom = Color(0x14FFFFFF);
  static const glassSolid = surfaceRaised;

  /// The glass's lens: the upper part of a piece of glass is this much
  /// brighter, fading to nothing half way down, as light caught in a curved
  /// surface is.
  static const glassLens = Color(0x14FFFFFF);

  /// What a sheet or an overlay dims the page with: black at 64%. One
  /// strength for every modal, so opening one always reads the same.
  static const scrim = Color(0xA3000000);
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
