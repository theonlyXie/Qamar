// The palette (the mono-glass skill, .claude/skills/mono-glass): black, white,
// and the greys between them — nothing else. Every token is achromatic; each
// step of ink passes AA on every surface the app draws and on the glass; the
// disabled step sits below AA on purpose and stays there to see; the glass,
// the edges and the scrim are white or black at an alpha; no colour is
// written outside lib/theme (the moon's greys aside, which are greys too);
// the one hue in the app is Google's G, on the account sheet only; and no
// token is kept that nothing draws.

import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/theme/colors.dart';

import 'support/contrast.dart';

const _surfaces = {
  'canvas': QColors.canvas,
  'surface': QColors.surface,
  'surfaceRaised': QColors.surfaceRaised,
  'surfaceHigh': QColors.surfaceHigh,
};

const _ink = {
  'ink': QColors.ink,
  'inkSecondary': QColors.inkSecondary,
  'inkTertiary': QColors.inkTertiary,
};

Iterable<File> _libSources() => Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

String _path(File f) => f.path.replaceAll(r'\', '/');

/// Every `Color(0x…)` literal in [source], as its 32-bit value.
Iterable<int> _literals(String source) => RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)').allMatches(source).map((m) => int.parse(m.group(1)!, radix: 16));

bool _grey(int argb) => (argb >> 16 & 0xFF) == (argb >> 8 & 0xFF) && (argb >> 8 & 0xFF) == (argb & 0xFF);

String _palette() {
  final all = File('lib/theme/colors.dart').readAsStringSync();
  return all.substring(0, all.indexOf('class QBrandMarks'));
}

void main() {
  test('every token is black, white, or a grey between them: no hue', () {
    final values = _literals(_palette()).toList();
    expect(values, isNotEmpty);
    for (final v in values) {
      expect(_grey(v), isTrue, reason: '0x${v.toRadixString(16)} has a hue');
    }
  });

  test('every step of ink passes AA on every surface, and on the glass', () {
    final grounds = {
      ..._surfaces,
      'glass over the canvas': over(QColors.glassFill, QColors.canvas),
      'glass over a card': over(QColors.glassFill, QColors.surface),
      'pressed glass': over(QColors.glassFillPressed, QColors.canvas),
      'solid glass': QColors.glassSolid,
    };
    for (final t in _ink.entries) {
      for (final g in grounds.entries) {
        expect(contrastRatio(t.value, g.value), greaterThanOrEqualTo(4.5), reason: '${t.key} on ${g.key}');
      }
    }
  });

  test('words on the white fill are black, at the full 21:1', () {
    expect(QColors.onInk, QColors.black);
    expect(contrastRatio(QColors.onInk, QColors.ink), closeTo(21, 0.01));
  });

  test('a disabled label sits below AA on purpose, and stays there to see', () {
    expect(contrastRatio(QColors.inkDisabled, QColors.surface), lessThan(4.5));
    expect(contrastRatio(QColors.inkDisabled, QColors.surface), greaterThanOrEqualTo(3), reason: 'still there to see');
  });

  test('the surfaces climb in steps you can see, and the two edges are a step apart', () {
    final ladder = _surfaces.values.toList();
    for (var i = 1; i < ladder.length; i++) {
      expect(contrastRatio(ladder[i], ladder[i - 1]), greaterThan(1.1), reason: '${_surfaces.keys.elementAt(i)} is a step above ${_surfaces.keys.elementAt(i - 1)}');
    }
    final soft = contrastRatio(over(QColors.hairline, QColors.surface), QColors.surface);
    final strong = contrastRatio(over(QColors.hairlineStrong, QColors.surface), QColors.surface);
    expect(soft, greaterThan(1.2), reason: 'the hairline is there');
    expect(strong - soft, greaterThan(0.25), reason: 'the strong edge is a clear step above it');
  });

  test('the glass, its edges and the dots are white at an alpha; the scrim is black at one', () {
    for (final c in [QColors.glassFill, QColors.glassFillPressed, QColors.glassFillClear, QColors.glassEdgeTop, QColors.glassEdgeBottom, QColors.glassLens, QColors.dotOff, QColors.hairline, QColors.hairlineStrong]) {
      expect(c.withAlpha(255), QColors.white, reason: '$c');
      expect(c.a, inExclusiveRange(0, 1), reason: '$c');
    }
    expect(QColors.scrim.withAlpha(255), QColors.black);
    expect(QColors.glassFillClear.a, lessThan(QColors.glassFill.a), reason: 'clear glass is the thinner one');
    expect(QColors.glassFillPressed.a, greaterThan(QColors.glassFill.a), reason: 'pressed glass is a step brighter');
    expect(QColors.glassEdgeTop.a, greaterThan(QColors.glassEdgeBottom.a), reason: 'the edge catches light at the top');
  });

  test('no colour is written outside the theme: tokens, or tokens at an alpha', () {
    final raw = RegExp(r'Color\(0x|Color\.from(ARGB|RGBO)|\bColors\.(?!transparent\b)\w+');
    final found = <String>[];
    for (final f in _libSources()) {
      final path = _path(f);
      if (path.startsWith('lib/theme/')) continue;
      // The moon's own shading: an illustration's greys, held below.
      if (path == 'lib/widgets/moon.dart') continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (raw.hasMatch(lines[i])) found.add('$path:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test("the moon is drawn in greys: the orb keeps its shading and loses its colour", () {
    final moon = File('lib/widgets/moon.dart').readAsStringSync();
    final values = _literals(moon).toList();
    expect(values, isNotEmpty);
    for (final v in values) {
      expect(_grey(v), isTrue, reason: 'the moon has a hue: 0x${v.toRadixString(16)}');
    }
  });

  test("the one hue in the app is Google's G, and only on the account sheet", () {
    final users = [
      for (final f in _libSources())
        if (!_path(f).startsWith('lib/theme/') && f.readAsStringSync().contains('QBrandMarks.')) _path(f),
    ];
    expect(users, ['lib/widgets/account_sheet.dart']);
    const g = [QBrandMarks.googleBlue, QBrandMarks.googleRed, QBrandMarks.googleYellow, QBrandMarks.googleGreen];
    expect(g.map((c) => c.toARGB32()).toList(), [0xFF4285F4, 0xFFEA4335, 0xFFFBBC05, 0xFF34A853], reason: "Google's own values");
  });

  test('no token is kept that nothing draws', () {
    final palette = _palette();
    final names = RegExp(r'static const (\w+) =').allMatches(palette).map((m) => m.group(1)!).toList();
    final elsewhere = _libSources().where((f) => !f.path.endsWith('colors.dart')).map((f) => f.readAsStringSync()).join('\n');
    final unused = [
      for (final n in names)
        if (!RegExp('QColors\\.$n\\b').hasMatch(elsewhere) && RegExp('\\b$n\\b').allMatches(palette).length < 2) n,
    ];
    expect(unused, isEmpty, reason: 'drawn by nothing: $unused');
  });

  test('text falls back to the full ink, never to a fainter step', () {
    // QText's defaults: display, body and figures start at ink; only the
    // eyebrow, a label, starts a step down, at the third ink, which passes AA.
    final styles = File('lib/theme/text_styles.dart').readAsStringSync();
    final defaults = RegExp(r'Color color = QColors\.(\w+)').allMatches(styles).map((m) => m.group(1)).toSet();
    expect(defaults, {'ink', 'inkTertiary'});
  });

  test('the palette is the one the skill writes down', () {
    const expected = <String, int>{
      'canvas': 0xFF000000,
      'surface': 0xFF121212,
      'surfaceRaised': 0xFF1E1E1E,
      'surfaceHigh': 0xFF2C2C2C,
      'ink': 0xFFFFFFFF,
      'inkSecondary': 0xFFC7C7C7,
      'inkTertiary': 0xFF999999,
      'inkDisabled': 0xFF666666,
    };
    final actual = <String, Color>{
      ..._surfaces,
      ..._ink,
      'inkDisabled': QColors.inkDisabled,
    };
    for (final e in expected.entries) {
      expect(actual[e.key]!.toARGB32(), e.value, reason: e.key);
    }
    final skill = File('../.claude/skills/mono-glass/references/tokens.md');
    if (skill.existsSync()) {
      final doc = skill.readAsStringSync();
      for (final e in expected.entries) {
        final hex = '#${(e.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
        expect(doc, contains(hex), reason: '${e.key} ($hex) is written in the skill');
      }
    }
  });
}
