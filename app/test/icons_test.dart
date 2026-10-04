// One icon family (the qamar-design skill, .claude/skills/qamar-design): every
// glyph the app draws is named by what it means in QIcons (lib/theme/icons.dart)
// and drawn from Iconsax, the Nutri AI kit's family, through QIcon. No screen
// reaches for a Material glyph (Icons.*), or for an Iconsax or Cupertino one
// by its own name, or draws a bare Icon, so the family can change in one
// place; the only glyphs from outside it are other people's marks (Apple's,
// Facebook's), named once, in icons.dart. The glyphs that point the way the
// reading goes mirror in Arabic, and no thing does. Iconsax draws no plain ×:
// close is its add, turned an eighth by QIcon.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconsax_plus/iconsax_plus.dart';

import 'package:qamar/theme/icons.dart';

Iterable<File> _lib() => Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'));

String _path(File f) => f.path.replaceAll(r'\', '/');

void main() {
  test('no screen draws a Material glyph, a family glyph by its own name, or a bare Icon', () {
    final material = RegExp(r'(?<![A-Za-z])Icons\.[a-z_]');
    final family = RegExp(r'(CupertinoIcons|IconsaxPlus(Linear|Bold|Broken))\.[a-z_]');
    final bare = RegExp(r'(?<![A-Za-z_])Icon\(');
    final found = <String>[];
    for (final f in _lib()) {
      final path = _path(f);
      if (path == 'lib/theme/icons.dart') continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].trimLeft().startsWith('//')) continue;
        if (material.hasMatch(lines[i]) || family.hasMatch(lines[i]) || bare.hasMatch(lines[i])) found.add('$path:${i + 1}: ${lines[i].trim()}');
      }
    }
    expect(found, isEmpty, reason: 'name the glyph in QIcons and draw it with QIcon instead:\n${found.join('\n')}');
  });

  test('the family is Iconsax, but for the two marks that are not ours', () {
    final source = File('lib/theme/icons.dart').readAsStringSync();
    final material = RegExp(r'(?<![A-Za-z])Icons\.(\w+)').allMatches(source).map((m) => m.group(1)).toSet();
    expect(material, {'apple', 'facebook'}, reason: 'only the sign-in marks come from outside the family');
    for (final g in [QIcons.send, QIcons.close, QIcons.water, QIcons.moon, QIcons.back, QIcons.forward, QIcons.signOut, QIcons.done, QIcons.stop]) {
      expect(g.fontFamily, anyOf('IconsaxPlusLinear', 'IconsaxPlusBold'), reason: '$g');
      expect(g.fontPackage, 'iconsax_plus', reason: '$g');
    }
  });

  test('linear at rest, bold for the page on show', () {
    for (final g in [QIcons.today, QIcons.review, QIcons.plan, QIcons.me, QIcons.moon]) {
      expect(g.fontFamily, 'IconsaxPlusLinear');
      final on = QIcons.onFor(g);
      expect(on.fontFamily, 'IconsaxPlusBold', reason: 'the chosen tab’s glyph is the bold one');
      expect(on.codePoint, isNot(0));
    }
    expect(QIcons.onFor(QIcons.send), QIcons.send, reason: 'a glyph with no chosen state stays as it is');
  });

  test('back, forward and sign-out mirror in Arabic; no thing does', () {
    for (final g in [QIcons.back, QIcons.forward, QIcons.signOut]) {
      expect(g.matchTextDirection, isTrue, reason: '$g points the way the reading goes');
    }
    for (final g in [QIcons.send, QIcons.repeat, QIcons.check, QIcons.camera, QIcons.moon, QIcons.time, QIcons.share, QIcons.add]) {
      expect(g.matchTextDirection, isFalse, reason: '$g is a thing, not a direction');
    }
  });

  test('back and forward are the family’s own chevrons, sign-out its logout', () {
    expect(QIcons.back.codePoint, IconsaxPlusLinear.arrow_left_1.codePoint);
    expect(QIcons.forward.codePoint, IconsaxPlusLinear.arrow_right_3.codePoint);
    expect(QIcons.signOut.codePoint, IconsaxPlusLinear.logout.codePoint);
  });

  test('close is the family’s add, but its own glyph, so the turn is never lost', () {
    expect(QIcons.close.codePoint, QIcons.add.codePoint, reason: 'Iconsax draws no plain ×');
    expect(QIcons.close == QIcons.add, isFalse, reason: 'a constant of its own (a cross looks the same mirrored)');
  });

  testWidgets('QIcon turns the close mark an eighth, and nothing else', (tester) async {
    await tester.pumpWidget(const Directionality(
      textDirection: TextDirection.ltr,
      child: Row(children: [QIcon(QIcons.close, key: ValueKey('close')), QIcon(QIcons.add, key: ValueKey('add'))]),
    ));
    final turned = tester.widget<Transform>(find.descendant(of: find.byKey(const ValueKey('close')), matching: find.byType(Transform)));
    final angle = math.atan2(turned.transform.entry(1, 0), turned.transform.entry(0, 0));
    expect(angle, closeTo(math.pi / 4, 1e-6), reason: 'the add, turned into a ×');
    expect(find.descendant(of: find.byKey(const ValueKey('add')), matching: find.byType(Transform)), findsNothing);
  });
}
