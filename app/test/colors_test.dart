// The palette, seat 6's part: four steps of text, each passing AA on every
// surface the app draws (the faint fifth step, at 3.7:1 on a card, is gone);
// white words on the brand gradient pass AA at both its ends; every
// translucent token is a surface of the palette at an alpha; no hex is
// written outside lib/theme (the moon's own shading aside); and no token is
// kept that nothing draws.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/theme/colors.dart';

import 'support/contrast.dart';

const _surfaces = {
  'bgTop': QColors.bgTop,
  'bgMid': QColors.bgMid,
  'bgBottom': QColors.bgBottom,
  'bgScan': QColors.bgScan,
  'cardDeep': QColors.cardDeep,
  'cardMid': QColors.cardMid,
};

const _text = {
  'textPrimary': QColors.textPrimary,
  'textHigh': QColors.textHigh,
  'textMid': QColors.textMid,
  'textMuted': QColors.textMuted,
  'goldPale': QColors.goldPale,
  'goldMuted': QColors.goldMuted,
};

Iterable<File> _libSources() => Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

void main() {
  test('every step of text passes AA on every surface, and over the glass', () {
    final grounds = {
      ..._surfaces,
      'glass': over(QColors.glass, QColors.bgBottom),
      'glassHigh': over(QColors.glassHigh, QColors.bgBottom),
      'sheet top': over(QColors.sheet.colors.first, QColors.bgBottom),
    };
    for (final t in _text.entries) {
      for (final g in grounds.entries) {
        expect(contrastRatio(t.value, g.value), greaterThanOrEqualTo(4.5), reason: '${t.key} on ${g.key}');
      }
    }
  });

  test('white words on the brand gradient pass AA at both its ends', () {
    for (final stop in QColors.brandGradient.colors) {
      expect(contrastRatio(QColors.onAccent, stop), greaterThanOrEqualTo(4.5), reason: 'on $stop');
    }
  });

  test('a disabled label sits below AA on purpose, and stays there to see', () {
    expect(contrastRatio(QColors.textDisabled, QColors.cardDeep), lessThan(4.5));
    expect(contrastRatio(QColors.textDisabled, QColors.cardDeep), greaterThanOrEqualTo(3), reason: 'still there to see');
  });

  test('two card surfaces and two edges, each pair a step apart', () {
    final palette = File('lib/theme/colors.dart').readAsStringSync();
    final names = RegExp(r'static const (\w+) =').allMatches(palette).map((m) => m.group(1)!).toList();
    expect(names.where((n) => n.startsWith('card')).toList(), ['cardDeep', 'cardMid']);
    expect(names.where((n) => n.startsWith('border')).toList(), ['borderSoft', 'borderStrong']);
    expect(contrastRatio(QColors.cardMid, QColors.cardDeep), greaterThan(1.03), reason: 'raised is a step up, as on the phone: a card lifted by a lighter fill, not a shadow');
    final soft = contrastRatio(QColors.borderSoft, QColors.cardDeep), strong = contrastRatio(QColors.borderStrong, QColors.cardDeep);
    expect(soft, greaterThan(1.2), reason: 'the hairline is there');
    expect(strong - soft, greaterThan(0.25), reason: 'the strong edge is a clear step above it');
  });

  test('every translucent token is a surface of the palette at an alpha', () {
    expect(QColors.scrim.withAlpha(255), QColors.bgScan);
    expect(QColors.glass.withAlpha(255), QColors.cardMid);
    expect(QColors.glassHigh.withAlpha(255), QColors.bgTop);
    expect(QColors.sheet.colors.first.withAlpha(255), QColors.cardMid);
    expect(QColors.sheet.colors.last, QColors.bgBottom);
    for (final c in [QColors.scrim, QColors.glass, QColors.glassHigh, QColors.sheet.colors.first]) {
      expect(c.a, inExclusiveRange(0, 1));
    }
  });

  test('no colour is written outside the theme: tokens, or tokens at an alpha', () {
    final raw = RegExp(r'Color\(0x|Color\.from(ARGB|RGBO)|\bColors\.(?!transparent\b)\w+');
    final found = <String>[];
    for (final f in _libSources()) {
      final path = f.path.replaceAll(r'\', '/');
      if (path.startsWith('lib/theme/')) continue;
      // The moon's own shading: an illustration's gradient stops, not UI.
      if (path == 'lib/widgets/moon.dart') continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (raw.hasMatch(lines[i])) found.add('$path:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('no token is kept that nothing draws', () {
    final palette = File('lib/theme/colors.dart').readAsStringSync();
    final names = RegExp(r'static const (\w+) =').allMatches(palette).map((m) => m.group(1)!).toList();
    expect(names, isNot(contains('textFaint')));
    final elsewhere = _libSources().where((f) => !f.path.endsWith('colors.dart')).map((f) => f.readAsStringSync()).join('\n');
    final unused = [
      for (final n in names)
        if (!RegExp('QColors\\.$n\\b').hasMatch(elsewhere) && RegExp('\\b$n\\b').allMatches(palette).length < 2) n,
    ];
    expect(unused, isEmpty, reason: 'drawn by nothing: $unused');
  });

  test('the palette never gives text a colour below AA to fall back on', () {
    // QText's defaults: display and body alike start at textPrimary.
    final styles = File('lib/theme/text_styles.dart').readAsStringSync();
    expect(RegExp(r'Color color = QColors\.(\w+)').allMatches(styles).map((m) => m.group(1)).toSet(), {'textPrimary'});
  });
}
