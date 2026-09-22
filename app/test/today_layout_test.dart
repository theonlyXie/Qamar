// Today's layout contract (O15). Every seat that adds to Today builds inside
// this test: it is a list of slot cards and a list of zones, not one fixed
// screenshot.
//
//  * Zones, top to bottom: header, Qamar's card, numbers, the one slot,
//    water, the slot's runners-up, next meal, movement, quest, meals.
//  * The slot holds exactly one card, chosen by todayFocus in priority
//    order; every other card that is due moves below the fold, in order.
//    Never a stack.
//  * Above the fold on a 390x844 phone, whatever is due: "Log a meal"
//    (seat 2's non-negotiable) and Qamar's sentence (seat 3's).
//
// To extend it: a new slot card is a TodayCard value plus a case in
// [slotCases] saying how to make it due (seat 3: the week card, the quest).
// The switch-off variant of "Points and streaks" is a value in [scoreModes]
// (seat 4). The height budgets are seat 6's, in [fold] below.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/plan.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/screens/today_screen.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/state/today_focus.dart';
import 'package:qamar/theme/layout.dart';
import 'package:qamar/widgets/common.dart';

import 'support/app_fonts.dart';

/// A gateway whose plan is always refused by the daily cap.
class _PlanCapped implements AiGateway {
  @override
  Future<DayPlan> generatePlan({required String date, required String lang, bool force = false, String? instruction}) async =>
      throw AiQuotaException('Today’s plan has been rewritten enough.', const AiQuota(bucket: 'plan', used: 4, limit: 4, extra: 0, remaining: 0));
  @override
  Future<AiQuotas> quotaStatus() async => AiQuotas.empty;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// Four days before the first fast of 1448, so the season's question is due.
final _now = DateTime(2027, 2, 4, 9);

/// How to make each slot card due. Every TodayCard needs one.
final slotCases = <({TodayCard card, void Function(AppState s) arrange})>[
  (card: TodayCard.safety, arrange: (s) => s.profile = s.profile.copyWith(safety: SafetyAnswer.pregnant)),
  (card: TodayCard.tutorial, arrange: (_) {}), // due from the first launch until the first hold
  (
    card: TodayCard.billing,
    arrange: (s) => s
      ..plusActive = true
      ..plusIsTrial = true
      ..plusUntil = _now.add(const Duration(hours: 20)),
  ),
  (card: TodayCard.fasting, arrange: (_) {}), // the clock is in the season's lead week
  (card: TodayCard.earnedMonth, arrange: (s) => s.earnedMonthJustGranted = true),
];

/// "Points and streaks" on and off. Seat 4 adds `false` with the switch.
final scoreModes = <bool>[true];

/// The phone, and the line nothing that must be seen may cross: the orb's
/// band sits under it.
const _phone = Size(390, 844);
final fold = _phone.height - QLayout.orbBand;

AppState _state(AppLang lang, {Iterable<TodayCard> due = const []}) {
  final s = AppState(clock: () => _now)..setLang(lang);
  s.profile = s.profile.copyWith(name: 'Basel');
  for (final c in slotCases) {
    if (due.contains(c.card)) c.arrange(s);
  }
  // A card that is not asked for is kept from being due.
  if (!due.contains(TodayCard.fasting)) s.setFasting(false);
  if (!due.contains(TodayCard.tutorial)) s.dismissOrbTutorial();
  s.go(AppScreen.today);
  return s;
}

Future<void> _pump(WidgetTester tester, AppState s, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Rect? _rectOf(WidgetTester t, Key key) {
  final f = find.byKey(key);
  return f.evaluate().isEmpty ? null : t.getRect(f);
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  group('todayFocus', () {
    test('every slot card has a case saying how to make it due', () {
      expect(slotCases.map((c) => c.card).toSet(), TodayCard.values.toSet());
    });

    test('the arrangements do what they say, one card at a time', () {
      for (final c in slotCases) {
        final s = _state(AppLang.en, due: [c.card]);
        expect(todayCardsDue(s), [c.card], reason: '${c.card} alone');
        expect(todayFocus(s), c.card);
      }
      expect(todayFocus(_state(AppLang.en)), isNull, reason: 'nothing due, no card');
    });

    test('picks the highest that is due, in the agreed order', () {
      expect(TodayCard.values, [TodayCard.safety, TodayCard.tutorial, TodayCard.billing, TodayCard.fasting, TodayCard.earnedMonth]);
      // Take cards away from the top one by one: the next one takes the slot.
      for (var i = 0; i < TodayCard.values.length; i++) {
        final due = TodayCard.values.sublist(i);
        final s = _state(AppLang.en, due: due);
        expect(todayFocus(s), due.first, reason: 'due: $due');
        expect(todayCardsDue(s), due, reason: 'the rest keep their order');
      }
    });

    test('the tutorial keeps the slot until the first hold, then waits below', () {
      final s = _state(AppLang.en, due: [TodayCard.tutorial]);
      s.orbTap(); // the tap is learned; the tree opens
      s.closeTree();
      expect(todayFocus(s), TodayCard.tutorial, reason: 'a tap does not end it');
      s.holdOrb();
      expect(todayFocus(s), isNull, reason: 'the hold does');
    });
  });

  for (final lang in AppLang.values) {
    for (final score in scoreModes) {
      for (final withSafety in [false, true]) {
        final due = withSafety ? TodayCard.values : TodayCard.values.where((c) => c != TodayCard.safety).toList();
        final label = '${lang.name}, score ${score ? 'on' : 'off'}, ${withSafety ? 'with' : 'without'} a safety answer';

        testWidgets('above the fold, every card due: "Log a meal" and Qamar’s sentence ($label)', (tester) async {
          final s = _state(lang, due: due);
          await _pump(tester, s, _phone);
          expect(tester.takeException(), isNull, reason: 'nothing overflows on a phone');

          final log = tester.getRect(find.byKey(QamarCard.logKey));
          expect(log.bottom, lessThanOrEqualTo(fold), reason: '"Log a meal" stays above the fold, whatever is due');
          expect(log.height, greaterThanOrEqualTo(48));
          final sentence = tester.getRect(find.byKey(const ValueKey('today-sentence')));
          expect(sentence.bottom, lessThanOrEqualTo(fold), reason: 'Qamar’s sentence stays above the fold');
        });

        testWidgets('the zones in order, one card in the slot, the rest below in order ($label)', (tester) async {
          final s = _state(lang, due: due);
          // As wide as the phone and tall enough that every zone is built.
          await _pump(tester, s, Size(_phone.width, 5000));
          expect(tester.takeException(), isNull);

          final present = [
            for (final z in TodayZone.values)
              if (_rectOf(tester, TodayScreen.zoneKey(z)) case final r?) (z, r),
          ];
          for (var i = 1; i < present.length; i++) {
            expect(present[i].$2.top, greaterThanOrEqualTo(present[i - 1].$2.bottom),
                reason: '${present[i].$1} comes after ${present[i - 1].$1}, never beside or over it');
          }
          final zones = {for (final (z, _) in present) z};
          expect(zones.contains(TodayZone.numbers), !withSafety, reason: 'no target on the general-guidance route, so no numbers');

          // Exactly one card in the slot: the highest due.
          final slot = tester.getRect(find.byKey(TodayScreen.zoneKey(TodayZone.slot)));
          final runners = tester.getRect(find.byKey(TodayScreen.zoneKey(TodayZone.runnersUp)));
          final inSlot = [
            for (final c in TodayCard.values)
              if (_rectOf(tester, TodayScreen.cardKey(c)) case final r? when slot.contains(r.center)) c,
          ];
          expect(inSlot, [due.first]);

          // Every other due card below the fold, in the runners-up zone, in
          // priority order, each shown once.
          var lastTop = runners.top - 1;
          for (final c in due.skip(1)) {
            final f = find.byKey(TodayScreen.cardKey(c));
            expect(f, findsOneWidget, reason: '$c is shown once');
            final r = tester.getRect(f);
            expect(runners.contains(r.center), isTrue, reason: '$c moves below the fold, not into a stack above');
            expect(r.top, greaterThan(lastTop), reason: '$c keeps its place in the order');
            lastTop = r.top;
          }
        });
      }
    }
  }

  // The fasting card's second state (O10): the question answered, and the
  // plan's cap kept today's plan from following. Still one card in the
  // slot, a line now, and the fold holds.
  for (final lang in AppLang.values) {
    testWidgets('the fasting answer the plan could not follow is one line in the slot, and the fold holds (${lang.name})', (tester) async {
      final s = AppState(clock: () => _now, ai: _PlanCapped())..setLang(lang);
      s.profile = s.profile.copyWith(name: 'Basel');
      s.dismissOrbTutorial();
      s.aiQuota = const AiQuota(bucket: 'chat', used: 1, limit: 3, extra: 0, remaining: 2);
      const lunch = (id: 'lunch', slotAr: 'الغدا', slotEn: 'Lunch', nameAr: 'كشري', nameEn: 'Koshary', noteAr: '', noteEn: '', portions: <PlanPortion>[]);
      s.plan = const DayPlan(date: '2027-02-04', slots: [(lunch, lunch)]);
      s.planDate = DateTime.now().toIso8601String().substring(0, 10);
      s.go(AppScreen.today);
      await s.setFasting(true);
      expect(todayCardsDue(s), [TodayCard.fasting]);

      await _pump(tester, s, _phone);
      expect(tester.takeException(), isNull, reason: 'nothing overflows on a phone');
      final slot = tester.getRect(find.byKey(TodayScreen.zoneKey(TodayZone.slot)));
      final card = find.byKey(TodayScreen.cardKey(TodayCard.fasting));
      expect(slot.contains(tester.getRect(card).center), isTrue, reason: 'in the slot, where the question was');
      expect(find.descendant(of: card, matching: find.byType(QStateLine)), findsOneWidget);
      expect(find.byType(QStateCard), findsNothing, reason: 'not a second card fighting the slot');
      expect(tester.getRect(find.byKey(QamarCard.logKey)).bottom, lessThanOrEqualTo(fold));
      expect(tester.getRect(find.byKey(const ValueKey('today-sentence'))).bottom, lessThanOrEqualTo(fold));
    });
  }

  group('Qamar’s card', () {
    testWidgets('"Log a meal" opens the tree already on Log, and the tree names the moon', (tester) async {
      final s = _state(AppLang.en);
      await _pump(tester, s, _phone);
      await tester.tap(find.byKey(QamarCard.logKey));
      await tester.pump();
      expect(s.treeOpen, isTrue);
      expect(s.treeLogExpanded, isTrue, reason: 'the ways to log, already fanned out');
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Next time, tap the moon to find this.'), findsOneWidget);

      // Once the moon has been tapped, the tree no longer needs to say it.
      s.closeTree();
      s.orbTap();
      s.closeTree();
      s.openTreeOnLog();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Next time, tap the moon to find this.'), findsNothing);
    });

    testWidgets('in the morning the night note is the sentence, with its link; there is no second card', (tester) async {
      final s = _state(AppLang.ar);
      s.nightNote = NightNote(day: _now, ar: 'خطة النهارده فيها عشا خفيف.', en: 'Today’s plan has a light dinner.', planKcal: 2100, todayKcal: 0);
      await _pump(tester, s, _phone);
      expect(find.text('خطة النهارده فيها عشا خفيف.'), findsOneWidget);
      expect(find.text('الخطة الكاملة في قمر+'), findsOneWidget, reason: 'the free tier meets the wall here, as before');
      expect(find.text('من الليل'), findsNothing, reason: 'the night card is merged into Qamar’s card');
      await tester.tap(find.text('الخطة الكاملة في قمر+'));
      await tester.pump();
      expect(s.screen, AppScreen.subscription);
    });

    testWidgets('the billing moment is the card seat 1 built, which never says "cancel"', (tester) async {
      final s = _state(AppLang.en, due: [TodayCard.billing]);
      await _pump(tester, s, _phone);
      expect(find.textContaining('nothing renews on its own'), findsOneWidget);
      expect(find.textContaining('cancel'), findsNothing, reason: 'there is nothing to cancel: nothing renews');
    });
  });
}
