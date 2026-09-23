// Characters, seat 6's part: no copy carries an emoji, which the bundled
// fonts do not draw (the Arabic greeting's 👋 rendered as a box at the start
// of the first thing the app says), and a trailing "..." is the ellipsis
// character, one glyph with its own spacing, not three full stops.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

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
}
