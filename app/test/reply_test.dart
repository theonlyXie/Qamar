// Qamar's words after a log, and Today's sentence once something is logged
// (O3): one sentence about this meal against this day, variable because the
// day is, and never about points.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/messages.dart';
import 'package:qamar/models/nudge.dart';
import 'package:qamar/models/reply.dart';
import 'package:qamar/models/streak.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/state/app_state.dart';

import 'support/app_fonts.dart';

LoggedMeal _meal(int kcal, {int p = 20}) => LoggedMeal(name: 'x', sub: '', kcal: kcal, p: p, c: 0, f: 0);

/// The meals still ahead by the clock, as the app has them on a day with
/// nothing yet eaten in them.
List<MealSlot> _aheadAt(int hour) => hour < 11 ? const [MealSlot.lunch, MealSlot.dinner] : hour < 17 ? const [MealSlot.dinner] : const [];

DayNumbers _day({int kcal = 1000, int target = 2000, int protein = 40, int targetProtein = 140, int hour = 13, ({String nameAr, String nameEn, int kcal})? next}) =>
    DayNumbers(kcal: kcal, targetKcal: target, protein: protein, targetProtein: targetProtein, hour: hour, next: next, ahead: _aheadAt(hour));

const _dinner = (nameAr: 'فراخ مشوية بالسلطة', nameEn: 'Grilled chicken with salad', kcal: 600);

final _ar = AppState()..setLang(AppLang.ar);
final _en = AppState()..setLang(AppLang.en);

String _reply(AppState s, LoggedMeal m, DayNumbers d) => replyFor(m, d, ar: s.isAr, iso: s.iso);
String _line(AppState s, DayNumbers d) => dayLineFor(d, ar: s.isAr, iso: s.iso);

/// Every shape, and around its edges, for the sweeps below.
Iterable<(LoggedMeal, DayNumbers)> _sweep() sync* {
  for (final kcal in [0, 400, 900, 1500, 1900, 2000, 2080, 2150, 2300, 2480, 2600, 3400]) {
    for (final protein in [10, 60, 120, 139, 140, 190]) {
      for (final hour in [8, 13, 16, 21]) {
        for (final next in [null, _dinner, (nameAr: 'كشري', nameEn: 'Koshary', kcal: 1400)]) {
          for (final m in [_meal(300, p: 5), _meal(700, p: 45)]) {
            yield (m, _day(kcal: kcal, protein: protein, hour: hour, next: next));
          }
        }
      }
    }
  }
}

void main() {
  group('the shapes of a day', () {
    test('over the target, where the orb’s halo warms: said without blame, and tomorrow starts fresh', () {
      final d = _day(kcal: 2600);
      expect(shapeOf(d), DayShape.over);
      expect(_reply(_en, _meal(700), d), '700 kcal, which takes today about 600 past your target — nothing to make up, tomorrow starts fresh.');
      expect(_reply(_ar, _meal(700), d), contains('مفيش حاجة تتعوّض'));
      final blame = RegExp(r'too much|bad|exceed|careful|should not|shouldn’t|guilt|مش كويس|كتير|غلط|خلي بالك|ما كانش', caseSensitive: false);
      for (final day in [d, _day(kcal: 2300)]) {
        for (final s in [_ar, _en]) {
          expect(blame.hasMatch(_reply(s, _meal(700), day)), isFalse);
          expect(blame.hasMatch(_line(s, day)), isFalse);
        }
      }
    });

    test('a little past the target, within what an estimate can tell apart: said as both', () {
      // At a 2,000 target the moon warms only past 2,500 (25%, never under
      // 400); between 2,100 and 2,500 it reads the day as at the target.
      for (final kcal in [2101, 2300, 2500]) {
        expect(shapeOf(_day(kcal: kcal)), DayShape.nearOver, reason: '$kcal');
      }
      expect(shapeOf(_day(kcal: 2501)), DayShape.over);
      expect(_line(_en, _day(kcal: 2300)), 'About 300 kcal past your target — within what an estimate can tell apart.');
      expect(_reply(_en, _meal(500), _day(kcal: 2300)), '500 kcal; about 300 past your target — within what an estimate can tell apart.');
      expect(_line(_ar, _day(kcal: 2300)), 'النهارده فوق هدفك بحوالي ${_ar.iso('300')} سعرة — وده جوّه هامش التقدير.');
      expect(_reply(_ar, _meal(500), _day(kcal: 2300)), contains('جوّه هامش التقدير'));
      expect(_line(_en, _day(kcal: 2300)), isNot(contains('make up')), reason: 'nothing to make up is the over line; here there is nothing to say sorry for at all');
    });

    test('at the target, within 5% (and never under 100 kcal)', () {
      expect(shapeOf(_day(kcal: 1950)), DayShape.atTarget);
      expect(shapeOf(_day(kcal: 2090)), DayShape.atTarget);
      expect(_line(_en, _day(kcal: 1950)), 'Today is right at your target.');
      expect(_line(_ar, _day(kcal: 1950)), 'النهارده وصل لهدفك بالظبط.');
    });

    test('protein reached by this meal is news; reached earlier it is not the reply', () {
      final d = _day(kcal: 1500, protein: 150);
      expect(shapeOf(d, meal: _meal(600, p: 30)), DayShape.proteinDone, reason: '120 before, 150 after');
      expect(shapeOf(d, meal: _meal(600, p: 5)), isNot(DayShape.proteinDone), reason: 'it was already done');
      expect(_reply(_en, _meal(600, p: 30), d), '600 kcal, and with it today’s protein is done, with 500 kcal left.');
      expect(_line(_en, d), 'Today’s protein is done, with 500 kcal left.');
    });

    test('short on protein from the afternoon on, with room left', () {
      expect(shapeOf(_day(protein: 40, hour: 16)), DayShape.proteinShort);
      expect(shapeOf(_day(protein: 40, hour: 11)), isNot(DayShape.proteinShort), reason: 'the day is young');
      expect(_line(_en, _day(protein: 40, hour: 16)), '1000 kcal left, and today still wants about 100 g of protein.');
      expect(_line(_ar, _day(protein: 40, hour: 16)), contains('جم بروتين'));
    });

    test('the plan’s next meal: it fits, or it wants a smaller plate', () {
      expect(shapeOf(_day(next: _dinner)), DayShape.nextFits);
      expect(_line(_en, _day(next: _dinner)), '1000 kcal left, so the plan’s Grilled chicken with salad (600 kcal) still fits.');
      expect(_line(_ar, _day(next: _dinner)), contains('فراخ مشوية بالسلطة'));
      final big = _day(kcal: 1600, next: _dinner);
      expect(shapeOf(big), DayShape.nextLarge);
      expect(_line(_en, big), '400 kcal left, so the plan’s Grilled chicken with salad would want a smaller plate.');
    });

    test('otherwise the room left, said as what it is for', () {
      expect(shapeOf(_day()), DayShape.room);
      expect(_reply(_en, _meal(520), _day()), '520 kcal; 1000 kcal left — room for a full dinner.');
      expect(_reply(_ar, _meal(520), _day()), startsWith(_ar.iso('520')));
      expect(_line(_en, _day()), '1000 kcal left — room for a full dinner.');
      expect(_line(_ar, _day()), 'فاضل ${_ar.iso('1000')} سعرة — فيه مكان لعشا كامل.');
      expect(_line(_en, _day(kcal: 1600)), '400 kcal left — room for a light dinner.', reason: 'under a quarter of the day left');
      expect(_line(_en, _day(hour: 9, kcal: 400)), '1600 kcal left, with lunch and dinner still ahead.');
      expect(_line(_ar, _day(hour: 9, kcal: 400)), 'فاضل ${_ar.iso('1600')} سعرة، ولسه قدامك غدا وعشا.');
      expect(_line(_en, _day(hour: 21, kcal: 1500, protein: 120)), 'About 500 kcal left tonight — something light fits, if you want it.');
      expect(_reply(_en, _meal(300), _day(hour: 21, kcal: 1500, protein: 120)), '300 kcal; about 500 kcal left tonight — something light fits, if you want it.');
    });
  });

  group('across every day', () {
    test('the same day always reads the same way, and different days read differently', () {
      // Two days read alike only when the meal, the shape of the day and the
      // room left are alike: the words follow the day, and nothing else.
      final readings = <String, Set<(int, DayShape, int)>>{};
      for (final (m, d) in _sweep()) {
        expect(_reply(_en, m, d), _reply(_en, m, d), reason: 'no dice');
        final shape = shapeOf(d, meal: m);
        // "Right at your target" covers the whole tolerance, so it does not report the room left.
        readings.putIfAbsent(_reply(_en, m, d), () => {}).add((m.kcal, shape, shape == DayShape.atTarget ? 0 : d.left));
      }
      for (final e in readings.entries) {
        expect(e.value, hasLength(1), reason: '"${e.key}" was said of different days: ${e.value}');
      }
      final shapes = {for (final (m, d) in _sweep()) shapeOf(d, meal: m)};
      expect(shapes, DayShape.values.toSet(), reason: 'every shape is reachable');
    });

    test('the words and the moon read every day the same way', () {
      // One reading of the day: the orb's (OrbState.dayFor). Over only where
      // the halo warms, at or a little past wherever the moon reads "at".
      for (final target in [1500, 2000, 2800]) {
        for (var kcal = 25; kcal <= 4500; kcal += 25) {
          final d = _day(kcal: kcal, target: target);
          final moon = OrbState.dayFor(consumedKcal: kcal, targetKcal: target, logged: true);
          for (final shape in [shapeOf(d), shapeOf(d, meal: _meal(300))]) {
            final reason = '$kcal of $target: moon $moon, words $shape';
            expect(shape == DayShape.over, moon == OrbDay.over, reason: reason);
            expect(shape == DayShape.atTarget || shape == DayShape.nearOver, moon == OrbDay.at, reason: reason);
          }
        }
      }
    });

    test('no reply and no day line ever says Su, points or earned, in either language', () {
      final score = RegExp(r'\bsu\b|point|earn|reward|coin|نقط|نقاط|كسب|مكافأ', caseSensitive: false);
      for (final (m, d) in _sweep()) {
        for (final s in [_ar, _en]) {
          expect(score.hasMatch(_reply(s, m, d)), isFalse, reason: _reply(s, m, d));
          expect(score.hasMatch(_line(s, d)), isFalse, reason: _line(s, d));
        }
      }
    });

    test('Arabic draws every number in Eastern digits', () {
      for (final (m, d) in _sweep()) {
        expect(RegExp(r'[0-9]').hasMatch(_reply(_ar, m, d)), isFalse, reason: _reply(_ar, m, d));
        expect(RegExp(r'[0-9]').hasMatch(_line(_ar, d)), isFalse, reason: _line(_ar, d));
      }
    });
  });

  group('in the app', () {
    final now = DateTime(2027, 2, 5, 13, 30);

    AppState state(AppLang lang) {
      final s = AppState(clock: () => now)..setLang(lang);
      s.setFasting(false);
      return s;
    }

    test('a confirmed meal gets the reply for this meal against this day', () {
      final s = state(AppLang.en);
      s.proposal = const MealAnalysis([
        ConfirmItemDef(ar: 'كشري', en: 'Koshary', portionAr: 'طبق', portionEn: 'a plate', conf: Confidence.low, kcal: 640, p: 20, c: 100, f: 18),
      ]);
      s.proposalQty = [1];
      s.confirmProposal();
      final said = s.chat.lastWhere((t) => t.who == ChatWho.q).text;
      expect(said, replyFor(s.meals.single, s.dayNumbers(), ar: false, iso: s.iso));
      expect(said, startsWith('640 kcal'));
      expect(said, isNot(contains('Logged:')), reason: 'the fixed line is gone');
    });

    test('under the reply sits the meal’s own receipt, never the points; the credit goes to the orb (O3)', () {
      final score = RegExp(r'\bsu\b|point|earn|reward|coin|نقط|نقاط|كسب|مكافأ', caseSensitive: false);
      for (final lang in AppLang.values) {
        final s = state(lang);
        s.proposal = const MealAnalysis([
          ConfirmItemDef(ar: 'كشري', en: 'Koshary', portionAr: 'طبق', portionEn: 'a plate', conf: Confidence.low, kcal: 640, p: 20, c: 100, f: 18),
        ]);
        s.proposalQty = [1];
        s.confirmProposal();
        final confirmed = s.chat.lastWhere((t) => t.who == ChatWho.q);
        expect(confirmed.sub, s.meals.last.sub, reason: 'the receipt is the meal’s own');
        expect(confirmed.sub, lang == AppLang.ar ? 'مسجّل بالكتابة · تقدير' : 'Logged by text · estimate');

        s.repeatMeal(s.meals.last);
        final repeated = s.chat.lastWhere((t) => t.who == ChatWho.q);
        expect(repeated.sub, lang == AppLang.ar ? 'مكرر' : 'Repeated');

        for (final turn in [confirmed, repeated]) {
          expect(score.hasMatch('${turn.text} ${turn.sub}'), isFalse, reason: '${turn.text} / ${turn.sub}');
        }
        // The points were still credited, and the orb's receipt carries them.
        expect(s.suReceipt?.amount, SuEconomy.mealLogged);
      }
    });

    test('a repeat is read against the day as it now is, so the second one reads differently', () {
      final s = state(AppLang.ar);
      final koshary = LoggedMeal(name: 'كشري', sub: '', kcal: 900, p: 25, c: 150, f: 20, at: now);
      s.repeatMeal(koshary);
      final first = s.chat.last.text;
      s.repeatMeal(koshary);
      final second = s.chat.last.text;
      expect(first, replyFor(s.meals.first, (s..meals.removeLast()).dayNumbers(), ar: true, iso: s.iso));
      expect(second, isNot(first), reason: 'the same meal, a different day by then');
    });

    test('in the app, a day a little past the target: the orb reads at, and Today’s line says so, without the over words', () {
      final s = state(AppLang.en);
      final target = s.target().kcal;
      s.meals.add(LoggedMeal(name: 'Feteer', sub: '', kcal: target + 300, p: 40, c: 300, f: 90, at: now));
      expect(s.orbState().day, OrbDay.at, reason: 'within what an estimate can tell apart');
      expect(shapeOf(s.dayNumbers()), DayShape.nearOver);
      expect(dayLineFor(s.dayNumbers(), ar: false, iso: s.iso), 'About 300 kcal past your target — within what an estimate can tell apart.');
    });

    testWidgets('Today’s sentence after the first log is the day read in words', (tester) async {
      await loadAppFonts();
      for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
      }
      final s = state(AppLang.en)..dismissOrbTutorial();
      s.go(AppScreen.today);
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      expect(find.text('The one thing today: log your first meal. I’ll handle the rest with you.'), findsOneWidget);

      s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: now));
      s.go(AppScreen.today);
      await tester.pump();
      expect(find.text(dayLineFor(s.dayNumbers(), ar: false, iso: s.iso)), findsOneWidget);
      expect(find.textContaining('A light protein dinner closes the day well'), findsNothing, reason: 'the fixed line is gone');
    });
  });
}
