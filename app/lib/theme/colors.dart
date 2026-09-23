import 'package:flutter/material.dart';

/// Qamar's moonlit palette — navy/violet/cyan glass over near-black,
/// ported 1:1 from the Claude Design prototype's inline hex values.
class QColors {
  QColors._();

  static const bgTop = Color(0xFF1A2338);
  static const bgMid = Color(0xFF0B1324);
  static const bgBottom = Color(0xFF070C19);
  static const bgScan = Color(0xFF05080F);

  static const pageBgTop = Color(0xFF121B33);
  static const pageBgMid = Color(0xFF070C19);
  static const pageBgBottom = Color(0xFF05070E);

  static const textPrimary = Color(0xFFF8FAFC);
  static const textBrand = Color(0xFFF5F7FF);
  static const textHigh = Color(0xFFE7ECF3);
  static const textMid = Color(0xFFCBD5E1);
  static const textMuted = Color(0xFF94A3B8);
  static const textFaint = Color(0xFF64748B);

  /// The label of a control that has nothing to do (O11). Disabled controls
  /// are the one place a label may sit below AA contrast: it is meant to read
  /// as not available.
  static const textDisabled = Color(0xFF64748B);

  static const cardDeep = Color(0xFF111827);
  static const cardMid = Color(0xFF141C2E);
  static const cardSlate = Color(0xFF0F172A);
  static const cardNavy = Color(0xFF0B1324);

  static const borderSoft = Color(0xFF263044);
  static const borderFaint = Color(0xFF1F2940);
  static const borderStrong = Color(0xFF2B3450);
  static const borderStep = Color(0xFF2A354D);

  /// Mangata — the moon's road on water. Everything the moon throws off is
  /// this one cool white at varying strength, rather than a different hue per
  /// destination.
  static const moonlight = Color(0xFFE8EEFF);
  static const moonbeam = Color(0xFFC3D2F5);

  static const blue = Color(0xFF4F7CFF);
  static const violet = Color(0xFF7B6CFF);
  static const violetSoft = Color(0xFFA78BFA);
  static const cyan = Color(0xFF22D3EE);
  static const skyBlue = Color(0xFF60A5FA);

  static const green = Color(0xFF10B981);
  static const amber = Color(0xFFFBBF24);
  static const amberSoft = Color(0xFFF6C97A);
  static const red = Color(0xFFF87171);

  static const gold = Color(0xFFE8C275);
  static const goldPale = Color(0xFFF2E4C6);
  static const goldDeep = Color(0xFFB98B3C);
  static const goldMuted = Color(0xFFB9A57C);

  static const providerApple = Color(0xFFF8FAFC);
  static const providerGoogle = Color(0xFFEA4335);
  static const providerFacebook = Color(0xFF4F8BF5);

  static const brandGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [blue, violet],
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

  static const goldGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [gold, goldDeep],
  );

  static const greenCyanGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [green, cyan],
  );

  static const deviceBg = RadialGradient(
    center: Alignment(0.4, -0.76),
    radius: 1.35,
    colors: [bgTop, bgMid, bgBottom],
    stops: [0.0, 0.45, 1.0],
  );

  static const pageBg = RadialGradient(
    center: Alignment(0, -1),
    radius: 1.3,
    colors: [pageBgTop, pageBgMid, pageBgBottom],
    stops: [0.0, 0.6, 1.0],
  );
}
