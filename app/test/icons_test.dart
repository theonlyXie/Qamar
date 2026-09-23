// One icon family (the mono-glass skill, .claude/skills/mono-glass): every
// glyph the app draws is named by what it means in QIcons (lib/theme/icons.dart)
// and drawn from the Cupertino family. No screen reaches for a Material glyph
// (Icons.*), or for a Cupertino one by its own name, so the family can change
// in one place; the only glyphs from outside it are other people's marks
// (Apple's, Facebook's), named once, in icons.dart. The glyphs that point
// the way the reading goes mirror in Arabic, and nothing else does.

import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/theme/icons.dart';

Iterable<File> _lib() => Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

/// Screens still being redesigned, whose last Material glyphs go with their
/// redesign: owed, the way strings_test keeps its owed strings. A file comes
/// off this list the moment it is clean (the test below says so), and the
/// list ends empty.
const _owed = {
  'lib/screens/onboarding_screen.dart',
  'lib/screens/scan_screen.dart',
  'lib/screens/subscription_screen.dart',
  'lib/screens/welcome_screen.dart',
  'lib/screens/you_screen.dart',
  'lib/widgets/account_sheet.dart',
};

String _path(File f) => f.path.replaceAll(r'\', '/');

void main() {
  test('no screen draws a Material glyph, or a Cupertino one by its own name, but those owed', () {
    final material = RegExp(r'(?<![A-Za-z])Icons\.[a-z_]');
    final cupertino = RegExp(r'CupertinoIcons\.[a-z_]');
    final found = <String>[];
    final stillOwing = <String>{};
    for (final f in _lib()) {
      final path = _path(f);
      if (path == 'lib/theme/icons.dart') continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (material.hasMatch(lines[i]) || cupertino.hasMatch(lines[i])) {
          if (_owed.contains(path)) {
            stillOwing.add(path);
          } else {
            found.add('$path:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(found, isEmpty, reason: 'name the glyph in QIcons instead:\n${found.join('\n')}');
    final paid = _owed.difference(stillOwing);
    expect(paid, isEmpty, reason: 'clean now, so no longer owed: take it off the list: $paid');
  });

  test('the family is Cupertino, but for the two marks that are not ours', () {
    final source = File('lib/theme/icons.dart').readAsStringSync();
    final material = RegExp(r'(?<![A-Za-z])Icons\.(\w+)').allMatches(source).map((m) => m.group(1)).toSet();
    expect(material, {'apple', 'facebook'}, reason: 'only the sign-in marks come from outside the family');
    for (final g in [QIcons.send, QIcons.close, QIcons.water, QIcons.moon, QIcons.back, QIcons.signOut]) {
      expect(g.fontFamily, CupertinoIcons.iconFont);
      expect(g.fontPackage, CupertinoIcons.iconFontPackage);
    }
  });

  test('back, forward and sign-out mirror in Arabic; nothing else does', () {
    for (final g in [QIcons.back, QIcons.forward, QIcons.signOut]) {
      expect(g.matchTextDirection, isTrue, reason: '$g points the way the reading goes');
    }
    for (final g in [QIcons.close, QIcons.send, QIcons.repeat, QIcons.check, QIcons.camera, QIcons.moon, QIcons.time, QIcons.share]) {
      expect(g.matchTextDirection, isFalse, reason: '$g is a thing, not a direction');
    }
  });

  test('back and forward are the family’s own chevrons', () {
    expect(QIcons.back.codePoint, CupertinoIcons.chevron_back.codePoint);
    expect(QIcons.forward.codePoint, CupertinoIcons.chevron_forward.codePoint);
    expect(QIcons.signOut.codePoint, CupertinoIcons.square_arrow_right.codePoint);
  });
}
