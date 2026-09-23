// The brand in Arabic copy, seat 6's part: running Arabic text names the
// product the way the Arabic paywall does, قمر+, not a Latin "Qamar+"
// dropped into the sentence (where its plus lands on the wrong side and the
// line switches script mid-word). Two Latin uses stay, each marked as such:
// a button's brand isolated between FSI and PDI (seat 2's, problem_test),
// and the Siri phrases a person has to say as written, in «».

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

final _arabicLetter = RegExp('[ء-ي]');
final _stringLiteral = RegExp(r"'(?:[^'\\]|\\.)*'");

void main() {
  test('no Latin Qamar inside a sentence of Arabic copy', () {
    final found = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in _stringLiteral.allMatches(lines[i])) {
          final text = m
              .group(0)!
              .replaceAll(RegExp(r'\$\{[^}]*\}'), '') // code, not copy
              .replaceAll(RegExp(r'\\u2066.*?\\u2069'), '') // an isolated Latin brand
              .replaceAll(RegExp('«[^»]*»'), ''); // words to be said as written
          if (_arabicLetter.hasMatch(text) && text.contains('Qamar')) found.add('${f.path}:${i + 1}: ${m.group(0)}');
        }
      }
    }
    expect(found, isEmpty, reason: found.join('\n'));
  });

  test('the Arabic name is the paywall’s own', () {
    final paywall = File('lib/screens/subscription_screen.dart').readAsStringSync();
    expect(paywall, contains('قمر+ بيقولك تاكل إيه بكرة'));
    final explain = File('lib/widgets/explain.dart').readAsStringSync();
    expect(explain, contains('ومع قمر+ +١٠'));
  });
}
