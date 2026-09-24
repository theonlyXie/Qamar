// The season's day counts go through the app's one count rule (Counted.day,
// seat 3's), seat 2's part: the fasting question on Today, the Ramadan
// screen's first-fast line and its month's log, and the Eid report. Arabic
// had "١ يوم", "٢ يوم", "٣ يوم": one, two and three to ten each take their
// own form (يوم واحد، يومين، ٣ أيام), and eleven on the singular.

import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/ramadan.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';

/// The first fast of 1448 is Monday 8 February 2027.
final _firstFast = DateTime(2027, 2, 8);

Future<AppState> _show(WidgetTester tester, AppLang lang, DateTime now, AppScreen screen, {int logged = 0}) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final s = AppState(clock: () => now)..setLang(lang);
  s.profile = s.profile.copyWith(name: 'Basel');
  s.dismissOrbTutorial();
  for (var d = 0; d < logged; d++) {
    s.dayHistory.add(DayTotals(day: _firstFast.add(Duration(days: d)), kcal: 1800, meals: 2));
  }
  s.go(AppScreen.today);
  if (screen != AppScreen.today) s.go(screen);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  return s;
}

/// Drawn text that says [text] once iso()'s isolates are taken out, whole
/// or, with [part], as a part of it.
Finder _says(String text, {bool part = false}) => find.byWidgetPredicate((w) {
      if (w is! RichText) return false;
      final t = w.text.toPlainText().replaceAll(RegExp('[\u2066-\u2069]'), '');
      return part ? t.contains(text) : t == text;
    });

void main() {
  setUpAll(() {
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  // Days before the first fast, and how each language says them.
  const until = {
    1: (ar: 'يوم واحد', en: '1 day'),
    2: (ar: 'يومين', en: '2 days'),
    3: (ar: '٣ أيام', en: '3 days'),
  };

  for (final MapEntry(key: n, value: says) in until.entries) {
    final now = _firstFast.subtract(Duration(days: n)).add(const Duration(hours: 9));

    testWidgets('Today’s fasting question, $n before the first fast', (tester) async {
      await _show(tester, AppLang.ar, now, AppScreen.today);
      expect(_says('رمضان بعد ${says.ar}.', part: true), findsOneWidget);
      await _show(tester, AppLang.en, now, AppScreen.today);
      expect(_says('Ramadan is ${says.en} away.', part: true), findsOneWidget);
    });

    testWidgets('the Ramadan screen’s first fast, $n before it', (tester) async {
      await _show(tester, AppLang.ar, now, AppScreen.ramadan);
      expect(_says('أول يوم صيام بعد ${says.ar}.'), findsOneWidget);
      await _show(tester, AppLang.en, now, AppScreen.ramadan);
      expect(_says('The first fast is ${says.en} away.'), findsOneWidget);
    });
  }

  // Days logged in the month, on the Ramadan screen.
  const logged = {1: 'يوم واحد', 2: 'يومين', 3: '٣ أيام', 11: '١١ يوم'};
  for (final MapEntry(key: n, value: ar) in logged.entries) {
    testWidgets('the month’s log, $n logged', (tester) async {
      final during = DateTime(2027, 2, 28, 12);
      await _show(tester, AppLang.ar, during, AppScreen.ramadan, logged: n);
      expect(_says('سجّلت $ar من ٢٩'), findsOneWidget);
      await _show(tester, AppLang.en, during, AppScreen.ramadan, logged: n);
      expect(_says('Logged $n of 29 days'), findsOneWidget, reason: 'in English the month’s days take the noun');
    });
  }

  group('the Eid report', () {
    final s = AppState()..setLang(AppLang.ar);
    EidReport report(int days) => EidReport.build(
          season: Season.ramadan1448,
          history: [for (var d = 0; d < days; d++) DayTotals(day: _firstFast.add(Duration(days: d)), kcal: 2000, meals: 2)],
          weights: const [],
          targetKcal: 2000,
          iso: s.iso,
        );
    String plain(String x) => x.replaceAll(RegExp('[\u2066-\u2069]'), '');

    test('the days logged, counted as each language counts', () {
      for (final MapEntry(key: n, value: ar) in logged.entries) {
        final first = report(n).lines.first;
        expect(plain(first.ar), 'سجّلت $ar من ٢٩.', reason: '$n logged');
        expect(first.en, 'You logged $n of 29 days.');
      }
    });

    test('the longest run, counted as each language counts', () {
      for (final (n, ar, en) in [(3, '٣ أيام', '3 days'), (11, '١١ يوم', '11 days')]) {
        final run = report(n).lines.firstWhere((l) => l.en.startsWith('Longest run'));
        expect(plain(run.ar), 'أطول سلسلة: $ar ورا بعض.');
        expect(run.en, 'Longest run: $en in a row.');
      }
    });
  });
}
