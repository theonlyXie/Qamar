// Beside Arabic-Indic digits a middle dot is a zero: "١٦ · وجبة" reads as
// "١٦٠ وجبة", 160 meals, since ٠ is drawn as a dot (the mono-glass skill,
// references/arabic.md). Where English separates with " · ", Arabic copy
// uses the Arabic comma. This holds every Arabic string in lib/ to it: no
// "·" beside a number, written or computed.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _literal = RegExp(r"'(?:[^'\\]|\\.)*'");
final _arabicLetter = RegExp('[ء-ي]');

/// A middle dot touching a digit, or the edge of an interpolated value (a
/// number the app computes), on either side.
final _dotByNumber = RegExp(r'(\}|[0-9٠-٩])\s*·|·\s*(\$\{|\$[a-z]|[0-9٠-٩])');

void main() {
  test('no Arabic copy puts a middle dot beside a number', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        for (final m in _literal.allMatches(lines[i])) {
          final text = m.group(0)!;
          if (_arabicLetter.hasMatch(text) && _dotByNumber.hasMatch(text)) found.add('${f.path}:${i + 1}: $text');
        }
      }
    }
    expect(found, isEmpty, reason: 'use "، " in Arabic:\n${found.join('\n')}');
  });

  test('the check catches the case it is for', () {
    expect(_dotByNumber.hasMatch("'\${iso('16')} · وجبة'"), isTrue);
    expect(_dotByNumber.hasMatch('١٦ · وجبة'), isTrue);
    expect(_dotByNumber.hasMatch('دوس بره للخروج · استمر ضاغط'), isFalse, reason: 'between words the dot is harmless');
  });
}
