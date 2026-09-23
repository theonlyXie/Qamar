// Today's layout contract (O15). Every seat that adds to Today builds inside
// this test: it is a list of slot cards and a list of zones, not one fixed
// screenshot.
//
//  * Zones, top to bottom: header, Qamar's card, numbers, the one slot,
//    water, the slot's runners-up, next meal, movement, meals. The quest
//    has no zone: it is the slot's last contender.
//  * The slot holds exactly one card, chosen by todayFocus in priority
//    order; every other card that is due moves below the fold, in order.
//    Never a stack.
//  * Above the fold on a 390x844 phone, whatever is due: "Log a meal"
//    (seat 2's non-negotiable) and Qamar's sentence (seat 3's). The phone is
//    a real one: drawn at 3x, with its status bar and home indicator, and
//    the fold is wherever the orb really is ([expectAboveFold]).
//
// To extend it: a new slot card is a TodayCard value plus a case in
// [slotCases] saying how to make it due. The switch-off variant of "Points
// and streaks" is a value in [scoreModes] (seat 4). The height budgets are
// seat 6's, against [expectAboveFold] below.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/plan.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/models/quest.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/streak.dart';
import 'package:qamar/screens/today_screen.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/state/today_focus.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/theme/layout.dart';
import 'package:qamar/widgets/ask_qamar_overlay.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/living_orb.dart';
import 'package:qamar/widgets/orb_nav.dart';
import 'package:qamar/widgets/quest_card.dart';

import 'support/app_fonts.dart';
import 'support/contrast.dart';

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

/// A Friday, review day, three days before the first fast of 1448, so the
/// week card can be due and so is the season's question.
final _now = DateTime(2027, 2, 5, 9);

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
  (
    card: TodayCard.weekCard,
    // Three days of the week logged, so the card has something to say.
    arrange: (s) => s.dayHistory.addAll([
      for (final back in [1, 2, 3])
        DayTotals(day: DateTime(_now.year, _now.month, _now.day).subtract(Duration(days: back)), kcal: 1800 + back * 150, meals: 2),
    ]),
  ),
  (card: TodayCard.earnedMonth, arrange: (s) => s.earnedMonthJustGranted = true),
  // What the server chose from what the day lacks (O2, 0061).
  (card: TodayCard.quest, arrange: (s) => s.quest = DayQuest(kind: QuestKind.proteinDinner, done: false, expiresAt: _now.add(const Duration(hours: 12)))),
];

/// "Points and streaks" on and off (O4). Off, nothing on Today keeps score:
/// no Su chip, no streak line, no quest, no ring on the orb, and the header
/// closes up behind them.
final scoreModes = <bool>[true, false];

/// The phone: 390x844pt (the iPhone 12 to 14), drawn at 3x, with its
/// status bar and home indicator. The shell lays out inside that safe area,
/// so the screen starts under the status bar and the orb's band sits above
/// the home indicator.
const _phone = Size(390, 844);
const _statusBar = 47.0;
const _homeIndicator = 34.0;

/// The top of the orb's band inside the safe area.
const insetFold = 844 - _homeIndicator - QLayout.orbBand;

/// Nothing that must be seen may reach under the orb: not the top of its
/// band inside the safe area, and not the orb's own top wherever it really
/// rests. Keyed to the orb's rect, so it keeps holding when the orb moves.
void expectAboveFold(WidgetTester tester, Finder what, String name) {
  final orb = find.byKey(OrbNav.orbKey);
  expect(orb, findsOneWidget, reason: 'the orb is on Today');
  final bottom = tester.getRect(what).bottom;
  expect(bottom, lessThanOrEqualTo(insetFold), reason: '$name stays above the orb’s band ($insetFold), whatever is due');
  final orbTop = tester.getRect(orb).top;
  expect(bottom, lessThanOrEqualTo(orbTop), reason: '$name stays above the orb itself ($orbTop), whatever is due');
}

/// Seat 6's height budgets above the fold (O15): the header about 110,
/// Qamar's card about 130 — up to 200 in the morning, when the night note
/// carries its link to the plan and the header has no streak line yet (190
/// before the sentence took Apple's 17-point body) — the calorie card at
/// most 290, the slot 120, for every slot card. What they protect is the
/// fold: whatever is in the slot is whole above the band.
const budgets = (header: 110.0, qamar: 140.0, qamarMorning: 200.0, numbers: 290.0, slot: 120.0);

/// Each zone within its budget, and the slot's card, whole, above the orb's
/// band and the orb.
void expectBudgets(WidgetTester tester, TodayCard? card, String label) {
  Rect? zone(TodayZone z) => _rectOf(tester, TodayScreen.zoneKey(z));
  expect(zone(TodayZone.header)!.height, lessThanOrEqualTo(budgets.header), reason: 'the header ($label)');
  final morning = label.contains('morning');
  expect(zone(TodayZone.qamar)!.height, lessThanOrEqualTo(morning ? budgets.qamarMorning : budgets.qamar), reason: 'Qamar’s card ($label)');
  if (zone(TodayZone.numbers) case final numbers?) {
    expect(numbers.height, lessThanOrEqualTo(budgets.numbers), reason: 'the calorie card ($label)');
  }
  if (card == null) return;
  final slot = zone(TodayZone.slot)!;
  final orbTop = tester.getRect(find.byKey(OrbNav.orbKey)).top;
  expect(slot.height, lessThanOrEqualTo(budgets.slot), reason: '$card keeps to the slot’s ${budgets.slot} points ($label)');
  expect(slot.bottom, lessThanOrEqualTo(insetFold), reason: 'the slot’s card is whole above the band: $card ($label)');
  expect(slot.bottom, lessThanOrEqualTo(orbTop), reason: 'and above the orb: $card ($label)');
}

/// Every control on screen meets the three tap-target guidelines (O11).
Future<void> expectTouchable(WidgetTester tester, String where) async {
  await expectLater(tester, meetsGuideline(androidTapTargetGuideline), reason: '48dp: $where');
  await expectLater(tester, meetsGuideline(iOSTapTargetGuideline), reason: '44pt: $where');
  await expectLater(tester, meetsGuideline(labeledTapTargetGuideline), reason: 'every control named: $where');
}

AppState _state(AppLang lang, {Iterable<TodayCard> due = const [], bool score = true}) {
  final s = AppState(clock: () => _now)..setLang(lang);
  s.profile = s.profile.copyWith(name: 'Basel');
  s.setShowScore(score);
  for (final c in slotCases) {
    if (due.contains(c.card)) c.arrange(s);
  }
  // A card that is not asked for is kept from being due.
  if (!due.contains(TodayCard.fasting)) s.setFasting(false);
  if (!due.contains(TodayCard.tutorial)) s.dismissOrbTutorial();
  s.go(AppScreen.today);
  return s;
}

/// Draws the app on the phone, [size] in points. The view itself is set, not
/// only the surface, so MediaQuery (the safe area, and anything laid out
/// from the screen's size) sees the same phone the layout does.
Future<void> _pump(WidgetTester tester, AppState s, Size size) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = size * 3;
  tester.view.padding = const FakeViewPadding(top: _statusBar * 3, bottom: _homeIndicator * 3);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(MediaQuery.sizeOf(tester.element(find.byType(Scaffold).first)), size, reason: 'MediaQuery sees the phone the test claims');
}

Rect? _rectOf(WidgetTester t, Key key) {
  final f = find.byKey(key);
  return f.evaluate().isEmpty ? null : t.getRect(f);
}

/// What keeps score on Today (O4): all of it while "Points and streaks" is
/// on, none of it while it is off, with the header closed up behind it: the
/// name is its last line, and nothing below it is held open.
void _expectScore(WidgetTester tester, bool score) {
  final keeping = {
    'the Su chip': find.byType(SuChip),
    'the quest': find.byType(QuestCard),
    'the orb’s streak ring': find.byWidgetPredicate((w) => w is CustomPaint && w.painter is StreakRingPainter),
    'the orb’s receipt': find.byType(SuReceiptChip),
  };
  if (score) {
    expect(keeping['the Su chip'], findsOneWidget);
    return;
  }
  for (final e in keeping.entries) {
    expect(e.value, findsNothing, reason: '${e.key} keeps score, so it goes with the switch');
  }
  expect(find.byType(TodayStreakLine), findsNothing);
  final header = tester.getRect(find.byKey(TodayScreen.zoneKey(TodayZone.header)));
  final name = tester.getRect(find.text('Basel'));
  expect(header.bottom, moreOrLessEquals(name.bottom, epsilon: 0.5), reason: 'the header closes up under the name');
  final qamar = tester.getRect(find.byKey(TodayScreen.zoneKey(TodayZone.qamar)));
  expect(qamar.top - header.bottom, moreOrLessEquals(14, epsilon: 0.5), reason: 'Qamar’s card follows at the usual gap, nothing held open');
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
      expect(TodayCard.values, [TodayCard.safety, TodayCard.tutorial, TodayCard.billing, TodayCard.fasting, TodayCard.weekCard, TodayCard.earnedMonth, TodayCard.quest]);
      // Take cards away from the top one by one: the next one takes the slot.
      for (var i = 0; i < TodayCard.values.length; i++) {
        final asked = TodayCard.values.sublist(i);
        // A safety answer means no target, and so never a quest (0068).
        final due = asked.contains(TodayCard.safety) ? asked.where((c) => c != TodayCard.quest).toList() : asked;
        final s = _state(AppLang.en, due: asked);
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
        final asked = withSafety ? TodayCard.values : TodayCard.values.where((c) => c != TodayCard.safety).toList();
        // With the score off the quest is never due: it keeps score (O4). With
        // a safety answer it is never due either: there is no target (0068).
        final due = score && !withSafety ? asked : asked.where((c) => c != TodayCard.quest).toList();
        final label = '${lang.name}, score ${score ? 'on' : 'off'}, ${withSafety ? 'with' : 'without'} a safety answer';

        // The top of the screen at its tallest, both ways it can be: in the
        // morning Qamar's card carries last night's note with its link; after
        // a log the header carries the streak line and the card the day line.
        for (final moment in const ['morning', 'after a log']) {
          testWidgets('above the fold, every card due, $moment: "Log a meal" and Qamar’s sentence ($label)', (tester) async {
            final s = _state(lang, due: asked, score: score);
            if (moment == 'morning') {
              s.nightNote = NightNote(
                day: _now,
                ar: 'بكرة جاهز: ٢١٨٠ سعرة على ٣ وجبات، مبني على هدفك — النهارده مفيش تسجيل.',
                en: 'Tomorrow is ready: 2180 kcal over 3 meals, built on your target — nothing was logged today.',
                planKcal: 2180,
                todayKcal: 0,
              );
            } else {
              s.serverStreak = const Streak(current: 3, best: 3, todayCounted: false);
              s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: _now));
            }
            await _pump(tester, s, _phone);
            expect(tester.takeException(), isNull, reason: 'nothing overflows on a phone');
            if (moment == 'morning') {
              expect(find.textContaining(lang == AppLang.ar ? 'بكرة جاهز' : 'Tomorrow is ready'), findsOneWidget, reason: 'the note is the sentence');
            } else {
              expect(find.byType(TodayStreakLine), score ? findsOneWidget : findsNothing, reason: 'the streak line is in the header while the score is shown');
            }
            _expectScore(tester, score);

            expect(tester.getTopLeft(find.byType(TodayScreen)).dy, _statusBar, reason: 'the screen starts under the status bar');
            expectAboveFold(tester, find.byKey(QamarCard.logKey), '"Log a meal"');
            expect(tester.getSize(find.byKey(QamarCard.logKey)).height, greaterThanOrEqualTo(48));
            expectAboveFold(tester, find.byKey(const ValueKey('today-sentence')), 'Qamar’s sentence');
          });
        }

        testWidgets('the zones in order, one card in the slot, the rest below in order ($label)', (tester) async {
          final s = _state(lang, due: asked, score: score);
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
          expect(todayCardsDue(s), due, reason: 'what is due, with the score ${score ? 'on' : 'off'}');
          _expectScore(tester, score);
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

      final semantics = tester.ensureSemantics();
      await _pump(tester, s, _phone);
      expect(tester.takeException(), isNull, reason: 'nothing overflows on a phone');
      final slot = tester.getRect(find.byKey(TodayScreen.zoneKey(TodayZone.slot)));
      final card = find.byKey(TodayScreen.cardKey(TodayCard.fasting));
      expect(slot.contains(tester.getRect(card).center), isTrue, reason: 'in the slot, where the question was');
      expect(find.descendant(of: card, matching: find.byType(QStateLine)), findsOneWidget);
      expect(find.byType(QStateCard), findsNothing, reason: 'not a second card fighting the slot');
      expectBudgets(tester, TodayCard.fasting, 'the fasting line, ${lang.name}');
      await expectTouchable(tester, 'the fasting line (${lang.name})');
      semantics.dispose();
      expectAboveFold(tester, find.byKey(QamarCard.logKey), '"Log a meal"');
      expectAboveFold(tester, find.byKey(const ValueKey('today-sentence')), 'Qamar’s sentence');
    });
  }

  // Seat 6's budgets, card by card: each slot card alone in the slot, at the
  // top of the screen's tallest (the morning's note, or a log with the
  // streak line), in both languages.
  for (final lang in AppLang.values) {
    for (final moment in const ['morning', 'after a log']) {
      for (final c in slotCases) {
        testWidgets('within the height budgets, ${c.card.name} in the slot, $moment (${lang.name})', (tester) async {
          final s = _state(lang, due: [c.card]);
          if (moment == 'morning') {
            s.nightNote = NightNote(
              day: _now,
              ar: 'بكرة جاهز: ٢١٨٠ سعرة على ٣ وجبات، مبني على هدفك — النهارده مفيش تسجيل.',
              en: 'Tomorrow is ready: 2180 kcal over 3 meals, built on your target — nothing was logged today.',
              planKcal: 2180,
              todayKcal: 0,
            );
          } else {
            s.serverStreak = const Streak(current: 3, best: 3, todayCounted: false);
            s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: _now));
          }
          await _pump(tester, s, _phone);
          expect(tester.takeException(), isNull);
          expect(todayFocus(s), c.card);
          expectBudgets(tester, c.card, '${c.card.name}, $moment, ${lang.name}');
        });
      }
    }

    // O11 on every slot card: each alone in the slot, on the phone, every
    // control a whole touch (48 on Android, 44 on iOS) with a name.
    for (final c in slotCases) {
      testWidgets('every control is a whole touch with a name, ${c.card.name} in the slot (${lang.name})', (tester) async {
        final s = _state(lang, due: [c.card]);
        final semantics = tester.ensureSemantics();
        await _pump(tester, s, _phone);
        expect(todayFocus(s), c.card);
        await expectTouchable(tester, '${c.card.name} in the slot (${lang.name})');
        semantics.dispose();
      });
    }

    testWidgets('the calorie card’s estimate note is one line, in a colour that passes AA (${lang.name})', (tester) async {
      final s = _state(lang);
      await _pump(tester, s, _phone);
      final note = find.byKey(TodayScreen.estimateKey);
      final paragraph = tester.renderObject<RenderParagraph>(note);
      expect(paragraph.didExceedMaxLines, isFalse, reason: 'the whole sentence, on one line');
      expect(tester.getSize(note).height, lessThanOrEqualTo(17));
      final colour = tester.widget<Text>(note).style!.color!;
      expect(contrastRatio(colour, QColors.surface), greaterThanOrEqualTo(4.5));
    });

    // At zero the chip shows the coin alone (su_display_test.dart); with a
    // balance its number is 15pt, a reading size, where 11 read the Arabic
    // digits as dots.
    testWidgets('the Su chip’s number is 15pt (${lang.name})', (tester) async {
      final s = _state(lang)..suAvailable = 100;
      await _pump(tester, s, _phone);
      expect(tester.widget<Text>(find.byKey(SuChip.amountKey)).style!.fontSize, 15);
    });
  }

  group('Qamar’s card', () {
    testWidgets('"Log a meal" opens the conversation on the meal question, with the keyboard up', (tester) async {
      final s = _state(AppLang.en);
      await _pump(tester, s, _phone);
      await tester.tap(find.byKey(QamarCard.logKey));
      await tester.pump();
      expect(s.treeOpen, isFalse, reason: 'straight to the question: no menu asking how first');
      expect(s.chatOpen, isTrue);
      expect(s.chat.last.text, 'Tell me what you ate.');
      expect(s.loggingMeal, isTrue, reason: 'what is typed next is the meal, and spends no question');
      await tester.pump(const Duration(milliseconds: 400));
      final field = tester.widget<TextField>(find.descendant(of: find.byType(AskQamarOverlay), matching: find.byType(TextField)));
      expect(field.focusNode!.hasFocus, isTrue, reason: 'the keyboard is up: the question is already asked');
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

    testWidgets('a returning line (no plan behind it) is the sentence, with no plan link', (tester) async {
      for (final lang in AppLang.values) {
        final s = _state(lang);
        s.nightNote = NightNote(day: _now, ar: 'لو كشري تاني النهارده، هتلاقيه في سجّل ← كرّر.', en: 'If it’s Koshary again today, you’ll find it under Log → Repeat.', planKcal: 0, todayKcal: 0);
        await _pump(tester, s, _phone);
        expect(find.text(lang == AppLang.ar ? 'لو كشري تاني النهارده، هتلاقيه في سجّل ← كرّر.' : 'If it’s Koshary again today, you’ll find it under Log → Repeat.'), findsOneWidget);
        for (final link in const ['الخطة الكاملة في قمر+', 'افتح خطة النهارده', 'The full plan is Qamar+', 'Open today’s plan']) {
          expect(find.text(link), findsNothing, reason: 'there is no plan to open');
        }
      }
    });

    testWidgets('the billing moment is the card seat 1 built, which never says "cancel"', (tester) async {
      final s = _state(AppLang.en, due: [TodayCard.billing]);
      await _pump(tester, s, _phone);
      expect(find.textContaining('nothing renews on its own'), findsOneWidget);
      expect(find.textContaining('cancel'), findsNothing, reason: 'there is nothing to cancel: nothing renews');
    });
  });
}
