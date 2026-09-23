// What to avoid, after the consultation (gap 4). The reveal says it can be
// changed in Me at any time, and a new allergy has to reach every plan, so
// Me asks the consultation's own question, with its own choices, the current
// ones picked.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/avoid_editor.dart';
import 'package:qamar/widgets/common.dart';

import 'support/arabic_digits.dart';

Future<void> _pump(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(const Size(900, 3000)); // words, not layout
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

bool _picked(WidgetTester tester, String value) => tester.widget<QPillChip>(find.byKey(AvoidEditor.chipKey(value))).selected;

void main() {
  setUpAll(() {
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  for (final lang in AppLang.values) {
    testWidgets('from Me, what to avoid is changed with the consultation’s own question, and Me follows (${lang.name})', (tester) async {
      final isAr = lang == AppLang.ar;
      final s = AppState()..setLang(lang);
      s.profile = s.profile.copyWith(prefs: ['meat']);
      s.go(AppScreen.you);
      await _pump(tester, s);

      await tester.tap(find.byKey(YouScreen.avoidEntryKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // the sheet rises
      expect(find.byType(AvoidEditor), findsOneWidget);
      expect(find.text(AppState.avoidStep.ask(isAr)), findsOneWidget, reason: 'the consultation’s own question');
      expect(_picked(tester, 'meat'), isTrue, reason: 'what is avoided now is picked');
      expect(_picked(tester, 'nuts'), isFalse);
      expect(_picked(tester, 'none'), isFalse);

      await tester.tap(find.byKey(AvoidEditor.chipKey('nuts')));
      await tester.pump();
      await tester.tap(find.byKey(AvoidEditor.saveKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500)); // the sheet goes
      expect(s.profile.prefs, ['nuts', 'meat']);
      expect(find.byType(AvoidEditor), findsNothing);
      expect(find.text(s.avoidNotice!), findsOneWidget, reason: 'what the change did is said on Me');
      final readOut = find.byKey(YouScreen.readOutKey);
      String name(String value) {
        final o = AppState.avoidStep.options.firstWhere((o) => o.value == value);
        return isAr ? o.ar : o.en;
      }
      expect(find.descendant(of: readOut, matching: find.text('${name('nuts')} · ${name('meat')}')), findsOneWidget,
          reason: 'the read-out names both (seat 2: a bare "2" said nothing)');
      if (isAr) expectNoLatinDigits(tester, within: readOut);
    });
  }

  testWidgets('"Nothing" clears every choice, and saving it leaves nothing to avoid', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.profile = s.profile.copyWith(prefs: ['nuts', 'lactose']);
    s.go(AppScreen.you);
    await _pump(tester, s);
    await tester.tap(find.byKey(YouScreen.avoidEntryKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(AvoidEditor.chipKey('none')));
    await tester.pump();
    expect(_picked(tester, 'none'), isTrue);
    expect(_picked(tester, 'nuts'), isFalse);
    await tester.tap(find.byKey(AvoidEditor.saveKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(s.profile.prefs, isEmpty);
  });
}
