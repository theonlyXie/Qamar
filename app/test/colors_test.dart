// The palette (the qamar-design skill, .claude/skills/qamar-design): the
// Nutri AI kit's greys, its four pastels, one colour of ours, burgundy, and
// a field's error red. Every token is one of those; each step of ink passes
// AA on every surface it sits on, and black passes AA on every pastel; white
// on burgundy passes, pressed and chosen; burgundy as a word passes on the
// ground, the card and the control; the disabled step sits below AA on
// purpose and stays there to see; the tints are the ground or black at an
// alpha; no colour is written outside lib/theme (the moon's greys aside,
// which are greys too); the one hue that is not ours is Google's G, on the
// account sheet only; and no token is kept that nothing draws.

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

const _pastels = {
  'lavender': QColors.lavender,
  'lime': QColors.lime,
  'mint': QColors.mint,
  'coral': QColors.coral,
};

Iterable<File> _libSources() => Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

String _path(File f) => f.path.replaceAll(r'\', '/');

/// Every `Color(0x…)` literal in [source], as its 32-bit value.
Iterable<int> _literals(String source) => RegExp(r'Color\(0x([0-9A-Fa-f]{8})\)').allMatches(source).map((m) => int.parse(m.group(1)!, radix: 16));

/// One of the kit's greys: the three channels within 3 of each other, since
/// its card grey (grey 500, #232220) is a hair warm.
bool _grey(int argb) {
  final r = argb >> 16 & 0xFF, g = argb >> 8 & 0xFF, b = argb & 0xFF;
  return [r, g, b].reduce((a, c) => a > c ? a : c) - [r, g, b].reduce((a, c) => a < c ? a : c) <= 3;
}

/// The hue of [argb], in degrees.
double _hue(int argb) => HSLColor.fromColor(Color(argb | 0xFF000000)).hue;

/// Burgundy: a red leaning to purple, 340°–356°.
bool _burgundy(int argb) => !_grey(argb) && _hue(argb) >= 340 && _hue(argb) <= 356;

String _palette() {
  final all = File('lib/theme/colors.dart').readAsStringSync();
  return all.substring(0, all.indexOf('class QBrandMarks'));
}

void main() {
  test('every token is a grey, burgundy, one of the kit\'s four pastels, or the error red', () {
    final values = _literals(_palette()).toList();
    expect(values, isNotEmpty);
    final pastels = {for (final c in _pastels.values) c.toARGB32()};
    for (final v in values) {
      expect(_grey(v) || _burgundy(v) || pastels.contains(v) || v == QColors.error.toARGB32(), isTrue, reason: '0x${v.toRadixString(16)} is none of them');
    }
    for (final c in [QColors.accent, QColors.accentPressed, QColors.accentInk, QColors.accentWash]) {
      expect(_burgundy(c.toARGB32()), isTrue, reason: '$c');
    }
    expect(pastels, {0xFFDDC0FF, 0xFFF5F378, 0xFF45C588, 0xFFFF6F43}, reason: "the kit's own values");
  });

  test('every step of ink passes AA on the ground, the card and the control; the full ink on the circle grey too', () {
    for (final t in _ink.entries) {
      for (final g in ['canvas', 'surface', 'surfaceRaised']) {
        expect(contrastRatio(t.value, _surfaces[g]!), greaterThanOrEqualTo(4.5), reason: '${t.key} on $g');
      }
    }
    // The tab bar's circles and the round buttons carry white glyphs only.
    expect(contrastRatio(QColors.ink, QColors.surfaceHigh), greaterThanOrEqualTo(4.5));
    // A control over a photo is the ground at half strength: over a white
    // picture it is at its lightest.
    expect(contrastRatio(QColors.ink, over(QColors.overPhoto, QColors.white)), greaterThanOrEqualTo(3), reason: 'a glyph over a bright photo');
  });

  test('black passes AA on every pastel, and so does its second step', () {
    for (final p in _pastels.entries) {
      expect(contrastRatio(QColors.onPastel, p.value), greaterThanOrEqualTo(4.5), reason: 'onPastel on ${p.key}');
      expect(contrastRatio(over(QColors.onPastelSecondary, p.value), p.value), greaterThanOrEqualTo(4.5), reason: 'onPastelSecondary on ${p.key}');
    }
    // A nested tile's bar on its track is a mark: 3:1 for graphics.
    for (final p in _pastels.entries) {
      expect(contrastRatio(QColors.onPastel, over(QColors.pastelTrack, p.value)), greaterThanOrEqualTo(3), reason: 'a bar on ${p.key}');
    }
  });

  test('white on burgundy passes, pressed and chosen', () {
    expect(QColors.onAccent, QColors.white);
    expect(contrastRatio(QColors.onAccent, QColors.accent), greaterThanOrEqualTo(7), reason: 'the primary button, a chosen segment');
    expect(contrastRatio(QColors.onAccent, QColors.accentPressed), greaterThanOrEqualTo(7), reason: 'pressed');
    expect(contrastRatio(QColors.onAccent, over(QColors.accentWash, QColors.canvas)), greaterThanOrEqualTo(7), reason: 'a chosen row');
  });

  test('burgundy as a word reads on the ground, the card and the control; as a bar on its track at 3:1', () {
    for (final g in ['canvas', 'surface', 'surfaceRaised']) {
      expect(contrastRatio(QColors.accentInk, _surfaces[g]!), greaterThanOrEqualTo(4.5), reason: 'accentInk on $g');
    }
    expect(contrastRatio(QColors.accentInk, QColors.hairline), greaterThanOrEqualTo(3), reason: 'a bar on its track');
  });

  test('a burgundy fill stands off the page, and its pressed step is deeper', () {
    expect(contrastRatio(QColors.accent, QColors.canvas), greaterThanOrEqualTo(2), reason: 'the button is there to see');
    expect(QColors.accentPressed.computeLuminance(), lessThan(QColors.accent.computeLuminance()));
  });

  test('words on white are the kit\'s black, well past AA', () {
    expect(QColors.onInk, QColors.canvas);
    expect(contrastRatio(QColors.onInk, QColors.white), greaterThanOrEqualTo(15));
  });

  test('a field\'s error red reads on the ground, as its message does', () {
    expect(contrastRatio(QColors.error, QColors.canvas), greaterThanOrEqualTo(3), reason: 'the edge, a mark');
    expect(contrastRatio(QColors.error, QColors.surface), greaterThanOrEqualTo(3), reason: 'on a sheet');
  });

  test('a disabled label sits below AA on purpose, and stays there to see', () {
    for (final g in ['surface', 'surfaceRaised']) {
      expect(contrastRatio(QColors.inkDisabled, _surfaces[g]!), lessThan(4.5), reason: g);
      expect(contrastRatio(QColors.inkDisabled, _surfaces[g]!), greaterThanOrEqualTo(3), reason: 'still there to see on $g');
    }
  });

  test('the surfaces climb in steps you can see, and the two edges are a step apart', () {
    final ladder = _surfaces.values.toList();
    for (var i = 1; i < ladder.length; i++) {
      expect(contrastRatio(ladder[i], ladder[i - 1]), greaterThan(1.1), reason: '${_surfaces.keys.elementAt(i)} is a step above ${_surfaces.keys.elementAt(i - 1)}');
    }
    final soft = contrastRatio(QColors.hairline, QColors.surface);
    final strong = contrastRatio(QColors.hairlineStrong, QColors.surface);
    expect(soft, greaterThan(1.15), reason: 'the hairline is there');
    expect(strong - soft, greaterThan(0.25), reason: 'the strong edge is a clear step above it');
  });

  test('the tints are the ground or black at an alpha', () {
    expect(QColors.scrim.withAlpha(255), QColors.black);
    for (final c in [QColors.overPhoto, QColors.overPhotoPressed, QColors.onPastelSecondary, QColors.pastelTrack]) {
      expect(c.withAlpha(255), QColors.canvas, reason: '$c');
      expect(c.a, inExclusiveRange(0, 1), reason: '$c');
    }
    expect(QColors.overPhotoPressed.a, greaterThan(QColors.overPhoto.a), reason: 'pressed is a step stronger');
    expect(QColors.accentWash.withAlpha(255), QColors.accent, reason: 'a chosen row is burgundy, washed');
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

  test("the moon is drawn in greys: the orb keeps its shading and has no colour", () {
    final moon = File('lib/widgets/moon.dart').readAsStringSync();
    final values = _literals(moon).toList();
    expect(values, isNotEmpty);
    for (final v in values) {
      expect(_grey(v), isTrue, reason: 'the moon has a hue: 0x${v.toRadixString(16)}');
    }
  });

  test("the one hue that is not ours is Google's G, and only on the account sheet", () {
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
    // eyebrow, a label, starts a step down, at the second ink.
    final styles = File('lib/theme/text_styles.dart').readAsStringSync();
    final defaults = RegExp(r'Color color = QColors\.(\w+)').allMatches(styles).map((m) => m.group(1)).toSet();
    expect(defaults, {'ink', 'inkSecondary'});
  });

  test('the palette is the one the skill writes down', () {
    const expected = <String, int>{
      'canvas': 0xFF121212,
      'surface': 0xFF232220,
      'surfaceRaised': 0xFF2F2F2F,
      'surfaceHigh': 0xFF474747,
      'ink': 0xFFFFFFFF,
      'inkSecondary': 0xFFC3C3C3,
      'inkTertiary': 0xFF9A9A9A,
      'inkDisabled': 0xFF7A7A7A,
      'lavender': 0xFFDDC0FF,
      'lime': 0xFFF5F378,
      'mint': 0xFF45C588,
      'coral': 0xFFFF6F43,
      'accent': 0xFF8E1B34,
      'accentPressed': 0xFF751529,
      'accentInk': 0xFFE8768D,
      'error': 0xFFC93838,
    };
    final actual = <String, Color>{
      ..._surfaces,
      ..._ink,
      ..._pastels,
      'inkDisabled': QColors.inkDisabled,
      'accent': QColors.accent,
      'accentPressed': QColors.accentPressed,
      'accentInk': QColors.accentInk,
      'error': QColors.error,
    };
    for (final e in expected.entries) {
      expect(actual[e.key]!.toARGB32(), e.value, reason: e.key);
    }
    final skill = File('../.claude/skills/qamar-design/references/tokens.md');
    expect(skill.existsSync(), isTrue, reason: 'the skill writes the tokens down');
    final doc = skill.readAsStringSync();
    for (final e in expected.entries) {
      final hex = '#${(e.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
      expect(doc, contains(hex), reason: '${e.key} ($hex) is written in the skill');
    }
  });
}
