// Characters, seat 6's part: no copy carries an emoji, which the bundled
// fonts do not draw (the Arabic greeting's 👋 rendered as a box at the start
// of the first thing the app says); a trailing "..." is the ellipsis
// character, one glyph with its own spacing, not three full stops; and every
// character of copy is one a bundled face draws: every style names Inter
// first and Noto Sans Arabic after it, so each script finds its face (You's
// arrows once drew as boxes).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/theme/text_styles.dart';

import 'support/font_cmap.dart';

final _emoji = RegExp('[\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}\u{200D}]', unicode: true);
final _literal = RegExp(r"'(?:[^'\\]|\\.)*'");

Iterable<(String, String)> _copy() sync* {
  for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
    final lines = f.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (lines[i].trimLeft().startsWith('//')) continue;
      for (final m in _literal.allMatches(lines[i])) {
        final text = m.group(0)!;
        if (text.startsWith("'package:") || text.startsWith("'dart:")) continue;
        yield ('${f.path}:${i + 1}', text);
      }
    }
  }
}

void main() {
  test('no copy carries an emoji the fonts cannot draw', () {
    final found = [for (final (where, t) in _copy()) if (_emoji.hasMatch(t)) '$where: $t'];
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('an ellipsis is one character', () {
    final found = [for (final (where, t) in _copy()) if (t.contains('...')) '$where: $t'];
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('every character of copy is drawn by a bundled face, and body text falls back to the one that has it', () {
    final noto = fontCharacters('assets/fonts/NotoSansArabic-400.ttf');
    final inter = fontCharacters('assets/fonts/Inter-400.ttf');
    for (final style in [QText.body(size: 15), QText.number(size: 15), QText.display(size: 22, ar: true), QText.eyebrow(ar: true)]) {
      expect(style.fontFamily, 'Inter', reason: 'Latin, and the arrows, in Inter');
      expect(style.fontFamilyFallback, contains('Noto Sans Arabic'), reason: 'Arabic, and its digits, in Noto Sans Arabic');
    }
    final escape = RegExp(r'\\u\{([0-9A-Fa-f]+)\}|\\u([0-9A-Fa-f]{4})');
    final found = <String>[];
    for (final (where, literal) in _copy()) {
      final text = literal
          .replaceAll(RegExp(r'\$\{[^}]*\}'), '')
          .replaceAllMapped(escape, (m) => String.fromCharCode(int.parse(m.group(1) ?? m.group(2)!, radix: 16)))
          .replaceAll(r'\n', ' ');
      for (final c in text.runes) {
        // Controls and bidi isolates are not drawn.
        if (c < 0x20 || (c >= 0x200B && c <= 0x200F) || (c >= 0x2066 && c <= 0x2069) || c == 0xFFFC) continue;
        if (!noto.contains(c) && !inter.contains(c)) found.add('$where: U+${c.toRadixString(16)} in $literal');
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
    // The arrows You uses are Inter's, not Noto's: the fallback is what
    // draws them.
    expect(noto.contains(0x2192), isFalse);
    expect(inter.contains(0x2192), isTrue);
  });
}
