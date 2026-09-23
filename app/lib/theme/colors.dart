import 'package:flutter/material.dart';

/// Qamar's moonlit palette — navy/violet/cyan glass over near-black, first
/// ported from the Claude Design prototype's inline hex values.
///
/// Every colour the app draws is one of these, or one of these at an alpha
/// (`QColors.cardMid.withValues(alpha: 0.9)`): no hex is written anywhere
/// else, and no token is kept that nothing draws (colors_test.dart). The one
/// exception is the moon illustration's own shading (widgets/moon.dart).
class QColors {
  QColors._();

  static const bgTop = Color(0xFF1A2338);
  static const bgMid = Color(0xFF0B1324);
  static const bgBottom = Color(0xFF070C19);
  static const bgScan = Color(0xFF05080F);

  /// Four steps of text, every one at least 4.5:1 on every surface below
  /// (colors_test.dart). There is no fifth, fainter step: the one there was
  /// (0xFF64748B) read at 3.7:1 on a card, below AA, for captions, hints and
  /// the fine print people most need to be able to read. Hierarchy under
  /// textMuted comes from size and weight, not from fading further.
  static const textPrimary = Color(0xFFF8FAFC);
  static const textHigh = Color(0xFFE7ECF3);
  static const textMid = Color(0xFFCBD5E1);
  static const textMuted = Color(0xFF94A3B8);

  /// The label of a control that has nothing to do (O11). Disabled controls
  /// are the one place a label may sit below AA contrast: it is meant to read
  /// as not available.
  static const textDisabled = Color(0xFF64748B);

  /// Words and glyphs on the brand gradient (at least 4.5:1 on both its
  /// ends).
  static const onAccent = Color(0xFFFFFFFF);

  static const cardDeep = Color(0xFF111827);
  static const cardMid = Color(0xFF141C2E);
  static const cardSlate = Color(0xFF0F172A);
  static const cardNavy = Color(0xFF0B1324);

  static const borderSoft = Color(0xFF263044);
  static const borderFaint = Color(0xFF1F2940);
  static const borderStrong = Color(0xFF2B3450);

  /// What a sheet or a card over the page dims everything else with: the
  /// scan's black at 78%. One strength for every modal, so opening a sheet
  /// always reads the same.
  static const scrim = Color(0xC705080F);

  /// A surface floating over the sky (the tree's rings, the coach mark, the
  /// orb's receipt): cardMid at 92%, so the sky shows through a little.
  static const glass = Color(0xEB141C2E);

  /// The same, a step lighter: pressed, or the person's own words in the
  /// conversation. bgTop at 95%.
  static const glassHigh = Color(0xF21A2338);

  /// Mangata — the moon's road on water. Everything the moon throws off is
  /// this one cool white at varying strength, rather than a different hue per
  /// destination.
  static const moonlight = Color(0xFFE8EEFF);
  static const moonbeam = Color(0xFFC3D2F5);

  static const blue = Color(0xFF4F7CFF);
  static const violet = Color(0xFF7B6CFF);

  /// The brand's two hues a step deeper, for the gradient that carries
  /// white words: at blue and violet themselves white read at 3.7:1.
  static const blueDeep = Color(0xFF3F66EB);
  static const violetDeep = Color(0xFF6B58F0);
  static const violetSoft = Color(0xFFA78BFA);
  static const cyan = Color(0xFF22D3EE);
  static const skyBlue = Color(0xFF60A5FA);

  static const green = Color(0xFF10B981);
  static const amber = Color(0xFFFBBF24);
  static const amberSoft = Color(0xFFF6C97A);
  static const red = Color(0xFFF87171);

  static const gold = Color(0xFFE8C275);
  static const goldPale = Color(0xFFF2E4C6);
  static const goldMuted = Color(0xFFB9A57C);


  /// The orb's halo on a day that ran over: a warm glow instead of the cool
  /// one, never red.
  static const ember = Color(0xFFFFB36C);
  static const emberDeep = Color(0xFFFF7C4F);

  /// Google's four, for its mark on the sign-in button and nowhere else:
  /// Google's branding asks for the "G" in colour, and a grey glyph read as
  /// a letter, not as the way to sign in with Google.
  static const googleBlue = Color(0xFF4285F4);
  static const googleRed = Color(0xFFEA4335);
  static const googleYellow = Color(0xFFFBBC05);
  static const googleGreen = Color(0xFF34A853);

  static const brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [blueDeep, violetDeep],
  );

  static const cyanVioletGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [cyan, violet],
  );

  static const blueCyanGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [blue, cyan],
  );

  static const deviceBg = RadialGradient(
    center: Alignment(0.4, -0.76),
    radius: 1.35,
    colors: [bgTop, bgMid, bgBottom],
    stops: [0.0, 0.45, 1.0],
  );

  /// A sheet rising from the bottom: cardMid at 97% at its top, settling
  /// into the page's darkest ground.
  static const sheet = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xF7141C2E), bgBottom],
  );
}
