// The day's quest (O2): real, or absent. The server chooses it from what the
// day lacks and pays it from the row that meets it (0061); the phone shows it
// and can put it away. These hold the phone's half and the kinds themselves.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/quest.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/state/today_focus.dart';
import 'package:qamar/widgets/quest_card.dart';

import 'support/app_fonts.dart';

final _now = DateTime(2027, 2, 5, 12);

AppState _state(AppLang lang, {DayQuest? quest}) {
  final s = AppState(clock: () => _now)..setLang(lang);
  s.setFasting(false);
  s.dismissOrbTutorial();
  s.quest = quest;
  s.go(AppScreen.today);
  return s;
}

DayQuest _q(QuestKind k, {bool done = false}) => DayQuest(kind: k, done: done, expiresAt: _now.add(const Duration(hours: 4)));

void main() {
  group('the kinds only ever add something', () {
    test('the Dart kinds are exactly the SQL enum in 0061', () {
      final sql = File('supabase/migrations/0061_daily_quests.sql').readAsStringSync();
      final m = RegExp(r"create type public\.quest_kind as enum \(([^)]*)\)").firstMatch(sql);
      expect(m, isNotNull, reason: 'the enum is declared in 0061');
      final values = RegExp(r"'([a-z0-9_]+)'").allMatches(m!.group(1)!).map((x) => x.group(1)).toList();
      expect(values, QuestKind.values.map((k) => k.wire).toList());
    });

    test('every kind is one that was reviewed as adding to the day', () {
      // A new kind goes here only once it is clear that it adds something:
      // a meal logged, protein, water. Never stay under, skip, or a deficit.
      const adding = {'lunch_by_16', 'protein_dinner', 'water_6'};
      for (final k in QuestKind.values) {
        expect(adding, contains(k.wire), reason: '${k.wire} is not a reviewed, adding kind');
      }
    });

    test('no kind, and no word a kind says, restricts', () {
      final restrict = RegExp(
        r'skip|under|less|fewer|cut|deficit|avoid|without|limit|stop|fast\b|no_|بلاش|قلل|قلّل|أقل|من غير|امتنع|تجنب|ما تاكلش|ماتاكلش|وقّف|وقف',
        caseSensitive: false,
      );
      final ar = AppState()..setLang(AppLang.ar);
      final en = AppState()..setLang(AppLang.en);
      for (final k in QuestKind.values) {
        expect(restrict.hasMatch(k.wire), isFalse, reason: k.wire);
        for (final s in [ar, en]) {
          final title = k.title(ar: s.isAr, iso: s.iso), why = k.why(ar: s.isAr);
          expect(restrict.hasMatch(title), isFalse, reason: title);
          expect(restrict.hasMatch(why), isFalse, reason: why);
        }
      }
    });

    test('Arabic titles draw their numbers the app’s way', () {
      final ar = AppState()..setLang(AppLang.ar);
      for (final k in QuestKind.values) {
        expect(RegExp(r'[0-9]').hasMatch(k.title(ar: true, iso: ar.iso)), isFalse, reason: k.wire);
      }
    });
  });

  group('the server’s answer', () {
    test('parses today’s quest, and treats anything else as none', () {
      final q = DayQuest.fromJson({'day': '2027-02-05', 'kind': 'protein_dinner', 'expires_at': '2027-02-05T22:00:00Z', 'done': false});
      expect(q?.kind, QuestKind.proteinDinner);
      expect(q?.done, isFalse);
      expect(DayQuest.fromJson({'kind': 'lunch_by_16', 'expires_at': '2027-02-05T14:00:00Z', 'done': true})?.done, isTrue);
      expect(DayQuest.fromJson(null), isNull, reason: 'a day with no gap');
      expect(DayQuest.fromJson({'kind': 'eat_less', 'expires_at': '2027-02-05T14:00:00Z'}), isNull, reason: 'an unknown kind is not shown');
    });
  });

  group('on Today', () {
    setUpAll(() async {
      await loadAppFonts();
      for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
      }
    });

    Future<void> pump(WidgetTester tester, AppState s) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    test('no quest from the server, no card', () {
      expect(todayCardDue(_state(AppLang.en), TodayCard.quest), isFalse);
      expect(todayCardDue(_state(AppLang.en, quest: _q(QuestKind.water6)), TodayCard.quest), isTrue);
    });

    testWidgets('the card says what the day lacks, with no Accept and no Replace', (tester) async {
      final s = _state(AppLang.en, quest: _q(QuestKind.proteinDinner));
      await pump(tester, s);
      expect(find.byType(QuestCard), findsOneWidget);
      expect(find.text('A dinner with 20 g of protein or more'), findsOneWidget);
      expect(find.text('Accept'), findsNothing);
      expect(find.text('Replace'), findsNothing);
      expect(find.text('+250'), findsOneWidget, reason: 'the score is shown');
    });

    testWidgets('"Not today" puts it away, and nothing is paid', (tester) async {
      final s = _state(AppLang.en, quest: _q(QuestKind.lunchBy16));
      await pump(tester, s);
      final before = s.suAvailable;
      // Scrolled up out of the orb's way, as a thumb would (the orb's resting
      // band is O1's, seat 6's).
      await tester.drag(find.byType(ListView).first, const Offset(0, -300));
      await tester.pump();
      await tester.tap(find.byKey(QuestCard.notTodayKey));
      await tester.pump();
      expect(find.byType(QuestCard), findsNothing);
      expect(s.suAvailable, before);
    });

    testWidgets('met, it shows done, with nothing left to press', (tester) async {
      final s = _state(AppLang.ar, quest: _q(QuestKind.water6, done: true));
      await pump(tester, s);
      expect(find.text('خلصت النهارده، واتسجّلت.'), findsOneWidget);
      expect(find.byKey(QuestCard.notTodayKey), findsNothing);
    });

    for (final lang in AppLang.values) {
      testWidgets('every kind fits the slot’s 120pt at 390pt wide (${lang.name})', (tester) async {
        for (final k in QuestKind.values) {
          for (final done in [false, true]) {
            final s = _state(lang, quest: _q(k, done: done));
            await pump(tester, s);
            expect(tester.takeException(), isNull);
            final h = tester.getSize(find.byType(QuestCard)).height;
            expect(h, lessThanOrEqualTo(120), reason: '${k.wire} ${done ? 'done' : 'open'}: $h');
          }
        }
      });
    }
  });
}
