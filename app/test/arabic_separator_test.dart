// Beside Arabic-Indic digits a middle dot is a zero: "١٦ · وجبة" reads as
// "١٦٠ وجبة", 160 meals, since ٠ is drawn as a dot (the liquid-glass skill,
// references/arabic.md). Where English separates with " · ", Arabic copy
// uses the Arabic comma. This holds every Arabic string in lib/ to it: no
// "·" beside a number, written or computed.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/activity.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/messages.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/state/app_state.dart';

import 'support/app_fonts.dart';

final _literal = RegExp(r"'(?:[^'\\]|\\.)*'");
final _arabicLetter = RegExp('[ء-ي]');

/// A middle dot touching a digit, or the edge of an interpolated value (a
/// number the app computes), on either side.
final _dotByNumber = RegExp(r'(\}|[0-9٠-٩])\s*·|·\s*(\$\{|\$[a-z]|[0-9٠-٩])');

/// The same, in what is on screen: a dot beside a drawn Arabic-Indic digit,
/// across the spaces and the direction isolates (U+2066…U+2069) a number is
/// set in.
final _shownDotByDigit = RegExp('[٠-٩][\\s\u2066-\u2069]*·|·[\\s\u2066-\u2069]*[٠-٩]');

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

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
    expect(_shownDotByDigit.hasMatch('ذكر · \u2066١٧٢\u2069 سم'), isTrue, reason: 'a number set in its isolate is still beside the dot');
    expect(_shownDotByDigit.hasMatch('\u2066٢٩\u2069 سنة، ذكر'), isFalse);
  });

  // The literal check cannot see a line put together from parts ("٢٩ سنة" and
  // "١٧٢ سم", joined): this reads what every screen actually shows.
  testWidgets('nothing on screen puts a middle dot beside an Arabic digit: every screen, the reveal, the tree, the conversation, the sheets', (tester) async {
    tester.view.devicePixelRatio = 3;
    tester.view.physicalSize = const Size(390, 2400) * 3;
    addTearDown(tester.view.reset);
    final s = AppState()..setLang(AppLang.ar);
    s.meals.add(LoggedMeal(name: 'كشري', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
    s.msgs.add(const ObMessage.target());
    await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
    final found = <String>[];
    Future<void> check(String where) async {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      for (final r in tester.widgetList<RichText>(find.byType(RichText))) {
        final text = r.text.toPlainText();
        if (_shownDotByDigit.hasMatch(text)) found.add('$where: $text');
      }
    }

    for (final screen in AppScreen.values) {
      s.go(screen);
      await check('$screen');
    }
    s.go(AppScreen.today);
    s.orbTap();
    await check('the tree');
    s.closeTree();
    s.quickLog(QuickLog.text);
    s.proposal = const MealAnalysis([
      ConfirmItemDef(ar: 'كشري', en: 'Koshary', portionAr: 'طبق وسط', portionEn: '1 medium bowl', conf: Confidence.high, kcal: 640, p: 19, c: 118, f: 11),
    ]);
    s.proposalQty = [1];
    await check('a reading to confirm');
    s.confirmProposal();
    await check('the conversation, after a log');
    s.closeChat();
    s.openWhy();
    await check('the Why sheet');
    s.closeWhy();
    s.chooseActivity(ActivityKind.walk);
    await check('the activity sheet');
    expect(found, isEmpty, reason: found.join('\n'));
  });
}
