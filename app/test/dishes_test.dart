// The first moment of value (O5): one real Egyptian dish, costed against the
// new target, before the calorie card. The dishes ship with the app, so this
// works with no backend at all, and they must be the food graph's own: its
// slugs, its household portions, its per-100 g numbers.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/models/dishes.dart';
import 'package:qamar/models/nudge.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/widgets/dish_card.dart';

final _seed = File('supabase/migrations/0017_egyptian_food_seed.sql').readAsStringSync();

/// foods.slug values the seed creates.
final _seedSlugs = RegExp(r"^\('([a-z_]+)','[^']*','[^']*','[^']*','[a-z]+','[a-z]+',", multiLine: true)
    .allMatches(_seed)
    .map((m) => m.group(1)!)
    .toSet();

/// (slug → portion grams) the seed defines.
final _seedPortions = () {
  final out = <String, Set<int>>{};
  for (final m in RegExp(r"\('([a-z_]+)','[^']*','[^']*',(\d+),(?:true|false)\)").allMatches(_seed)) {
    out.putIfAbsent(m.group(1)!, () => {}).add(int.parse(m.group(2)!));
  }
  return out;
}();

/// The recipes the seed builds from ingredients.
final _seedRecipes = RegExp(r"^\s+\('([a-z_]+)', [\d.]+, '[a-z]+', [\d.]+,", multiLine: true).allMatches(_seed).map((m) => m.group(1)!).toSet();

String _iso(String s) {
  const w = '0123456789', e = '٠١٢٣٤٥٦٧٨٩';
  return s.split('').map((c) => w.contains(c) ? e[w.indexOf(c)] : c).join();
}

EgyptianDish _dish(String id) => kEgyptianDishes.firstWhere((d) => d.id == id);

void main() {
  group('the table is the food graph’s', () {
    test('the seed parses: foods, portions and recipes are all there to check against', () {
      expect(_seedSlugs, containsAll(['koshary', 'foul_beans', 'baladi_bread', 'white_rice']));
      expect(_seedPortions['koshary'], {350, 550});
      expect(_seedRecipes, containsAll(['koshary', 'molokhia_dish', 'taameya', 'salata_baladi', 'mahshi_cabbage']));
    });

    test('about eight dishes, every part a graph slug with a graph portion', () {
      expect(kEgyptianDishes.length, inInclusiveRange(6, 10));
      for (final d in kEgyptianDishes) {
        for (final p in d.parts) {
          expect(_seedSlugs, contains(p.slug), reason: '${d.id}: ${p.slug} is not a food in 0017');
          final portions = _seedPortions[p.slug] ?? const <int>{};
          expect(portions.any((g) => p.grams % g == 0), isTrue,
              reason: '${d.id}: ${p.grams} g of ${p.slug} is not a whole number of a portion 0017 defines ($portions)');
        }
      }
    });

    test('a recipe’s numbers are derived from its ingredients; a single food’s are USDA’s, with the FDC id', () {
      for (final d in kEgyptianDishes) {
        for (final p in d.parts) {
          if (_seedRecipes.contains(p.slug)) {
            expect(p.source, 'derived_recipe', reason: p.slug);
          } else {
            expect(p.source, matches(RegExp(r'^usda_fdc:\d+$')), reason: p.slug);
          }
        }
      }
    });

    test('the totals are the portions times the graph’s per-100 g numbers', () {
      expect(_dish('koshary').facts(), (kcal: 507, protein: 16, carbs: 76, fat: 15, live: false));
      expect(_dish('ful_bread').facts().kcal, 338);
      expect(_dish('chicken_salad_bread').facts(), (kcal: 419, protein: 51, carbs: 33, fat: 11, live: false));
      expect(_dish('tilapia_rice_salad').facts().kcal, 500);
      expect(_dish('molokhia_rice').facts().kcal, 635);
    });

    test('the live graph’s numbers are preferred when it has every part — and never mixed with the shipped ones', () {
      const liveKoshary = (kcal: 150.0, protein: 5.0, carbs: 22.0, fat: 4.0);
      final k = _dish('koshary').facts(live: {'koshary': liveKoshary});
      expect(k.live, isTrue);
      expect(k.kcal, 525);

      final half = _dish('ful_bread').facts(live: {'foul_beans': (kcal: 999.0, protein: 0.0, carbs: 0.0, fat: 0.0)});
      expect(half.live, isFalse, reason: 'the bread is missing from the live answer, so none of it is used');
      expect(half.kcal, 338);
    });
  });

  group('the dish picked', () {
    const exclusionSets = [<String>[], ['nuts'], ['meat'], ['lactose'], ['budget'], ['meat', 'lactose'], ['nuts', 'meat', 'lactose', 'budget']];

    test('never one the person’s exclusions rule out, at any meal, for any goal', () {
      for (final ex in exclusionSets) {
        for (final slot in MealSlot.values) {
          for (final goal in Goal.values) {
            for (final t in [1500, 2180, 3200]) {
              final d = pickDish(targetKcal: t, goal: goal, exclusions: ex, slot: slot);
              expect(d, isNotNull, reason: 'something always fits: $ex $slot');
              expect(d!.ruledOutBy.intersection(ex.toSet()), isEmpty, reason: '${d.id} for $ex');
              expect(d.slots, contains(slot));
            }
          }
        }
      }
    });

    test('"no meat" rules out chicken as well as red meat, and "lactose" rules out cheese and ghee', () {
      final meatFree = kEgyptianDishes.where((d) => !d.ruledOutBy.contains('meat')).map((d) => d.id);
      expect(meatFree, isNot(contains('chicken_salad_bread')));
      expect(meatFree, isNot(contains('molokhia_rice')));
      final dairyFree = kEgyptianDishes.where((d) => !d.ruledOutBy.contains('lactose')).map((d) => d.id);
      expect(dairyFree, isNot(contains('eggs_areesh_bread')));
      expect(dairyFree, isNot(contains('molokhia_rice')), reason: 'cooked in samna');
    });

    test('a tight budget narrows to cheap dishes', () {
      for (final slot in [MealSlot.breakfast, MealSlot.lunch, MealSlot.dinner]) {
        expect(pickDish(targetKcal: 2500, goal: Goal.gain, exclusions: const ['budget'], slot: slot)!.budget, isTrue, reason: '$slot');
      }
    });

    test('sized to the target: lose picks no more than maintain, maintain no more than build', () {
      for (final slot in MealSlot.values) {
        for (final t in [1600, 2180, 3000]) {
          int kcal(Goal g) => pickDish(targetKcal: t, goal: g, exclusions: const [], slot: slot)!.facts().kcal;
          expect(kcal(Goal.lose), lessThanOrEqualTo(kcal(Goal.maintain)), reason: '$slot $t');
          expect(kcal(Goal.maintain), lessThanOrEqualTo(kcal(Goal.gain)), reason: '$slot $t');
        }
      }
    });

    test('the same answers always give the same dish', () {
      final a = pickDish(targetKcal: 2180, goal: Goal.lose, exclusions: const ['lactose'], slot: MealSlot.dinner);
      final b = pickDish(targetKcal: 2180, goal: Goal.lose, exclusions: const ['lactose'], slot: MealSlot.dinner);
      expect(a!.id, b!.id);
      expect(a.id, 'koshary', reason: 'dinner at 30% of 2180, a little under for "lose": 556 kcal; koshary is 507');
    });
  });

  group('the card', () {
    Future<Size> pump(WidgetTester tester, Widget card, {required bool ar}) async {
      await tester.pumpWidget(MaterialApp(
        home: Directionality(
          textDirection: ar ? TextDirection.rtl : TextDirection.ltr,
          child: Scaffold(body: Center(child: SizedBox(width: 340, child: card))),
        ),
      ));
      return tester.getSize(find.byWidget(card));
    }

    String allText(WidgetTester tester) => tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? '').join(' | ');

    testWidgets('names the dish and its portions, costs it against the target, and says it is an estimate', (tester) async {
      final d = _dish('chicken_salad_bread');
      await pump(tester, DishCard(dish: d, facts: d.facts(), targetKcal: 2180, slot: MealSlot.dinner, isAr: false, iso: (s) => s), ar: false);
      final text = allText(tester);
      expect(text, contains('Tonight, for example'));
      expect(text, contains('Grilled chicken breast with baladi salad'));
      expect(text, contains('a chicken breast + a plate of baladi salad + half a baladi loaf'));
      expect(text, contains('About 419 kcal · 19% of your 2180'));
      expect(text, contains('Protein 51 g · Carbs 33 g · Fat 11 g'));
      expect(text, contains('An estimate'));
    });

    testWidgets('in Arabic, right to left, with Eastern digits throughout', (tester) async {
      final d = _dish('koshary');
      await pump(tester, DishCard(dish: d, facts: d.facts(), targetKcal: 2180, slot: MealSlot.lunch, isAr: true, iso: _iso), ar: true);
      final text = allText(tester);
      expect(text, contains('كشري'));
      expect(text, contains('حوالي ٥٠٧ سعرة · ٢٣٪ من هدفك ٢١٨٠'));
      expect(text, contains('تقدير'));
      expect(RegExp('[0-9]').hasMatch(text), isFalse, reason: text);
    });

    testWidgets('with no target yet (the welcome entry), the numbers alone', (tester) async {
      final d = _dish('ful_bread');
      await pump(tester, DishCard(dish: d, facts: d.facts(), isAr: false, iso: (s) => s), ar: false);
      final text = allText(tester);
      expect(text, contains('About 338 kcal'));
      expect(text, isNot(contains('%')));
      expect(text, isNot(contains('for example')), reason: 'no slot given, no slot line');
    });
  });
}
