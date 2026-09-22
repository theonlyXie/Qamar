// The week card on Today (O15): on review day (Friday), once three days of
// the week are logged, the slot carries the week's one line the person did
// not expect, and the way to the whole card on Progress.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/services/device_prefs.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/state/today_focus.dart';
import 'package:qamar/widgets/week_glance_card.dart';

import 'support/app_fonts.dart';

final _friday = DateTime(2027, 1, 29, 10);

AppState _state(AppLang lang, {required DateTime now, int logged = 3}) {
  final s = AppState(clock: () => now)..setLang(lang);
  s.setFasting(false);
  s.dismissOrbTutorial();
  final today = DateTime(now.year, now.month, now.day);
  // A heavier Thursday, so the week has something to say.
  for (var back = 1; back <= logged; back++) {
    s.dayHistory.add(DayTotals(day: today.subtract(Duration(days: back)), kcal: back == 1 ? 2900 : 1800, meals: 2));
  }
  s.go(AppScreen.today);
  return s;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  test('due on Friday with three days logged, and not otherwise', () {
    expect(todayCardDue(_state(AppLang.en, now: _friday), TodayCard.weekCard), isTrue);
    expect(todayCardDue(_state(AppLang.en, now: _friday, logged: 2), TodayCard.weekCard), isFalse, reason: 'two days is not a week to read');
    expect(todayCardDue(_state(AppLang.en, now: _friday.add(const Duration(days: 1))), TodayCard.weekCard), isFalse, reason: 'Saturday is not review day');
  });

  Future<void> pump(WidgetTester tester, AppState s) async {
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  testWidgets('the card carries the week’s insight, and opening it leaves the slot for the day', (tester) async {
    final s = _state(AppLang.en, now: _friday);
    await pump(tester, s);
    expect(find.byType(WeekGlanceCard), findsOneWidget);
    expect(find.text(s.weekReview().insight.en), findsOneWidget);
    expect(s.weekReview().insight.en, contains('Thursday'), reason: 'the heavier day, read from the week');

    s.openWeekCard();
    expect(s.screen, AppScreen.progress);
    expect(todayCardDue(s, TodayCard.weekCard), isFalse, reason: 'seen: it leaves the slot');
  });

  test('opened, it stays away the rest of that Friday, across a restart; the next Friday it is back', () async {
    final prefs = MemoryDevicePrefs();
    AppState launch(DateTime now) {
      final s = AppState(prefs: prefs, clock: () => now)..setLang(AppLang.en);
      final today = DateTime(now.year, now.month, now.day);
      for (var back = 1; back <= 3; back++) {
        s.dayHistory.add(DayTotals(day: today.subtract(Duration(days: back)), kcal: 1800, meals: 2));
      }
      return s;
    }

    final first = launch(_friday);
    await Future<void>.delayed(Duration.zero);
    expect(first.weekCardDue, isTrue);
    first.openWeekCard();
    await Future<void>.delayed(Duration.zero);

    final restarted = launch(_friday.add(const Duration(hours: 3)));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(restarted.weekCardDue, isFalse, reason: 'the same Friday, after a restart');

    final nextWeek = launch(_friday.add(const Duration(days: 7)));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(nextWeek.weekCardDue, isTrue, reason: 'a new review day');
  });

  for (final lang in AppLang.values) {
    testWidgets('it fits the slot’s 120pt (${lang.name})', (tester) async {
      final s = _state(lang, now: _friday);
      await pump(tester, s);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(WeekGlanceCard)).height, lessThanOrEqualTo(120));
    });
  }
}
