// The palette (the liquid-glass skill, .claude/skills/liquid-glass): black,
// white, the greys between them, and one colour of ours, burgundy. Every
// token is achromatic or burgundy; each step of ink passes AA on every
// surface, on the glass and on a glass pane over the page's burgundy light;
// white on burgundy passes, pressed and lit; burgundy as a mark passes on
// every pane; the disabled step sits below AA on purpose and stays there to
// see; the glass, its rims and the scrim are white or black at an alpha; no
// colour is written outside lib/theme (the moon's greys aside, which are
// greys too); the one hue that is not ours is Google's G, on the account
// sheet only; and no token is kept that nothing draws.

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

/// The hue of [argb], in degrees.
double _hue(int argb) => HSLColor.fromColor(Color(argb | 0xFF000000)).hue;

/// Burgundy: a red leaning to purple, 340°–356°.
bool _burgundy(int argb) => !_grey(argb) && _hue(argb) >= 340 && _hue(argb) <= 356;

/// The page's light where content can sit: the glow is centred above the
/// top of the screen (QDecor.ambient), and by the top of the first card —
/// under the status bar and a header — it is at most 80% of its strength
/// on a phone (about 52% on a 390-point one) and 73% on a tablet. Words
/// directly on the page, above the cards, are checked on the full glow.
final _lightUnderContent = Color.lerp(QColors.canvas, QColors.ambient, 0.8)!;

/// A glass pane and a raised one at their brightest, in that light: where
/// the words have the least contrast.
final _paneInTheLight = over(QColors.glassPanelTop, _lightUnderContent);
final _raisedInTheLight = over(QColors.glassRaised, _lightUnderContent);

String _palette() {
  final all = File('lib/theme/colors.dart').readAsStringSync();
  return all.substring(0, all.indexOf('class QBrandMarks'));
}

void main() {
  test('every token is black, white, a grey between them, or burgundy: the one colour of ours', () {
    final values = _literals(_palette()).toList();
    expect(values, isNotEmpty);
    for (final v in values) {
      expect(_grey(v) || _burgundy(v), isTrue, reason: '0x${v.toRadixString(16)} is neither grey nor burgundy');
    }
    expect(values.where(_burgundy), isNotEmpty, reason: 'burgundy is there');
    for (final c in [QColors.accent, QColors.accentPressed, QColors.accentInk, QColors.accentWash, QColors.ambient]) {
      expect(_burgundy(c.toARGB32()), isTrue, reason: '$c');
    }
  });

  test('every step of ink passes AA on every surface, on the glass, and on a pane in the page\'s light', () {
    final grounds = {
      ..._surfaces,
      'glass over the canvas': over(QColors.glassFill, QColors.canvas),
      'glass over a card': over(QColors.glassFill, QColors.surface),
      'pressed glass': over(QColors.glassFillPressed, QColors.canvas),
      'solid glass': QColors.glassSolid,
      'the page\'s light at its brightest': QColors.ambient,
      'a pane at the top of the page\'s light': _paneInTheLight,
      'a raised pane in the light': _raisedInTheLight,
      'an inset in a pane in the light': over(QColors.glassInset, _paneInTheLight),
      'a sheet': over(QColors.glassPanelTop, over(QColors.glassSheet, QColors.canvas)),
    };
    for (final t in _ink.entries) {
      for (final g in grounds.entries) {
        expect(contrastRatio(t.value, g.value), greaterThanOrEqualTo(4.5), reason: '${t.key} on ${g.key}');
      }
    }
  });

  test('white on burgundy passes, lit by its lens and pressed', () {
    expect(QColors.onAccent, QColors.white);
    expect(contrastRatio(QColors.onAccent, QColors.accent), greaterThanOrEqualTo(7), reason: 'the primary button');
    expect(contrastRatio(QColors.onAccent, over(QColors.glassFill, QColors.accent)), greaterThanOrEqualTo(4.5), reason: 'under the lens');
    expect(contrastRatio(QColors.onAccent, QColors.accentPressed), greaterThanOrEqualTo(7), reason: 'pressed');
    expect(contrastRatio(QColors.onAccent, over(QColors.accentWash, QColors.canvas)), greaterThanOrEqualTo(7), reason: 'a chosen row');
  });

  test('burgundy as a mark reads on every pane and surface: 4.5:1 up to the raised surface, 3:1 for a bar on its track', () {
    final grounds = {
      'canvas': QColors.canvas,
      'surface': QColors.surface,
      'surfaceRaised': QColors.surfaceRaised,
      'a pane in the light': _paneInTheLight,
      'a raised pane in the light': _raisedInTheLight,
    };
    for (final g in grounds.entries) {
      expect(contrastRatio(QColors.accentInk, g.value), greaterThanOrEqualTo(4.5), reason: 'accentInk on ${g.key}');
    }
    // A bar and a ring are marks, not words: WCAG's 3:1 for graphics.
    expect(contrastRatio(QColors.accentInk, QColors.surfaceHigh), greaterThanOrEqualTo(3));
    expect(contrastRatio(QColors.accentInk, over(QColors.hairline, _paneInTheLight)), greaterThanOrEqualTo(3), reason: 'a bar on its track');
  });

  test('a burgundy fill stands off the page, and its pressed step is deeper', () {
    expect(contrastRatio(QColors.accent, QColors.canvas), greaterThanOrEqualTo(2), reason: 'the button is there to see');
    expect(QColors.accentPressed.computeLuminance(), lessThan(QColors.accent.computeLuminance()));
  });

  test('the page\'s light is a glow, not a colour: under 2% luminance', () {
    expect(QColors.ambient.computeLuminance(), lessThan(0.02));
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

  test('the glass, its panes and its rims are white at an alpha; the scrim is black at one', () {
    for (final c in [
      QColors.glassFill,
      QColors.glassFillPressed,
      QColors.glassFillClear,
      QColors.glassEdgeTop,
      QColors.glassEdgeBottom,
      QColors.glassLens,
      QColors.glassPanel,
      QColors.glassPanelTop,
      QColors.glassInset,
      QColors.glassRim,
      QColors.glassRimTinted,
      QColors.glassRaised,
      QColors.hairline,
      QColors.hairlineStrong,
    ]) {
      expect(c.withAlpha(255), QColors.white, reason: '$c');
      expect(c.a, inExclusiveRange(0, 1), reason: '$c');
    }
    expect(QColors.scrim.withAlpha(255), QColors.black);
    expect(QColors.glassFillClear.a, lessThan(QColors.glassFill.a), reason: 'clear glass is the thinner one');
    expect(QColors.glassFillPressed.a, greaterThan(QColors.glassFill.a), reason: 'pressed glass is a step brighter');
    expect(QColors.glassEdgeTop.a, greaterThan(QColors.glassEdgeBottom.a), reason: 'the edge catches light at the top');
    expect(QColors.glassPanelTop.a, greaterThan(QColors.glassPanel.a), reason: 'a pane is brighter at the top');
    expect(QColors.glassRim.a, greaterThan(QColors.hairline.a), reason: 'a pane\'s rim catches light at the top');
    expect(QColors.glassRimTinted.a, greaterThan(QColors.glassEdgeTop.a), reason: 'burgundy glass catches more');
    expect(QColors.glassSheet.withAlpha(255), QColors.surface, reason: 'a sheet is the surface, frosted');
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
      'accent': 0xFF8E1B34,
      'accentPressed': 0xFF751529,
      'accentInk': 0xFFE8768D,
      'ambient': 0xFF2A0912,
    };
    final actual = <String, Color>{
      ..._surfaces,
      ..._ink,
      'inkDisabled': QColors.inkDisabled,
      'accent': QColors.accent,
      'accentPressed': QColors.accentPressed,
      'accentInk': QColors.accentInk,
      'ambient': QColors.ambient,
    };
    for (final e in expected.entries) {
      expect(actual[e.key]!.toARGB32(), e.value, reason: e.key);
    }
    final skill = File('../.claude/skills/liquid-glass/references/tokens.md');
    if (skill.existsSync()) {
      final doc = skill.readAsStringSync();
      for (final e in expected.entries) {
        final hex = '#${(e.value & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
        expect(doc, contains(hex), reason: '${e.key} ($hex) is written in the skill');
      }
    }
  });
}
