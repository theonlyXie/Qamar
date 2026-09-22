// The streak line under the name on Today (O4): one sentence in Qamar's
// voice, from the second day of a run, and never about loss.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/streak.dart';
import 'package:qamar/screens/today_screen.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';

import 'support/app_fonts.dart';

final _now = DateTime(2027, 2, 5, 13);

AppState _state(AppLang lang) {
  final s = AppState(clock: () => _now)..setLang(lang);
  s.profile = s.profile.copyWith(name: 'Basel');
  s.setFasting(false);
  s.dismissOrbTutorial();
  s.go(AppScreen.today);
  return s;
}

Streak _run(int n, {bool today = true}) => Streak(current: n, best: n, todayCounted: today);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  group('streakSentence', () {
    final ar = _state(AppLang.ar);
    final en = _state(AppLang.en);
    String? say(AppState s, Streak k) => streakSentence(k, ar: s.isAr, iso: s.iso);

    test('from the second day of a run, as the agreed sentence', () {
      expect(say(en, _run(0)), isNull);
      expect(say(en, _run(1)), isNull, reason: 'one day is not a run');
      expect(say(en, _run(2)), 'Second day running.');
      expect(say(en, _run(4)), 'Fourth day running.');
      expect(say(ar, _run(4)), 'رابع يوم ورا بعض.');
      expect(say(en, _run(10)), 'Tenth day running.');
      expect(say(ar, _run(10)), 'عاشر يوم ورا بعض.');
    });

    test('past ten it is a number, in Eastern digits in Arabic', () {
      expect(say(en, _run(11)), '11 days running.');
      final line = say(ar, _run(11))!;
      expect(line, contains('١١'));
      expect(line, isNot(contains('11')));
      expect(line, endsWith('يوم ورا بعض.'));
    });

    test('only once today has joined the run: it is never a reminder to keep one', () {
      for (final n in [2, 5, 30]) {
        expect(say(en, _run(n, today: false)), isNull, reason: 'a run waiting for today says nothing ($n)');
        expect(say(ar, _run(n, today: false)), isNull);
      }
    });

    test('never speaks of loss, risk or a deadline', () {
      final loss = RegExp(r'risk|midnight|before|keep|lose|lost|break|miss|خطر|نص الليل|قبل|تخسر|يضيع|تقطع|يفوت', caseSensitive: false);
      for (var n = 2; n <= 60; n++) {
        for (final s in [ar, en]) {
          final line = say(s, _run(n))!;
          expect(loss.hasMatch(line), isFalse, reason: line);
        }
      }
    });
  });

  group('on Today', () {
    Future<void> pump(WidgetTester tester, AppState s) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('the header says the run once today’s meal has joined it', (tester) async {
      final s = _state(AppLang.en);
      s.serverStreak = _run(3, today: false);
      await pump(tester, s);
      expect(find.byType(TodayStreakLine), findsNothing, reason: 'nothing logged today: no line, nothing to keep');

      s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 500, p: 15, c: 80, f: 12, at: _now));
      s.go(AppScreen.today);
      await tester.pump();
      expect(find.text('Fourth day running.'), findsOneWidget, reason: 'today’s meal joins a three-day run');
    });

    testWidgets('in Arabic, from the local days alone', (tester) async {
      final s = _state(AppLang.ar);
      final day = DateTime(_now.year, _now.month, _now.day);
      s.dayHistory.add(DayTotals(day: day.subtract(const Duration(days: 1)), kcal: 1800, meals: 2));
      s.meals.add(LoggedMeal(name: 'كشري', sub: '', kcal: 500, p: 15, c: 80, f: 12, at: _now));
      await pump(tester, s);
      expect(find.text('تاني يوم ورا بعض.'), findsOneWidget);
    });
  });
}
