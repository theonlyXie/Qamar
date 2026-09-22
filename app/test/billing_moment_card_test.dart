// The billing moment on Today: the free week or the paid month in its last
// 48 hours. Nothing renews on its own, so this card and its push are the
// only word before Qamar+ stops. It must fit the one contextual slot (O15),
// say that plainly in both languages, and never offer to "cancel" what does
// not renew.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/billing_moment_card.dart';

final _now = DateTime.utc(2026, 9, 21, 12);

AppState _endingIn(Duration left, {required bool trial, required AppLang lang}) {
  final s = AppState(clock: () => _now)
    ..plusActive = true
    ..plusIsTrial = trial
    ..plusUntil = _now.add(left);
  s.setLang(lang);
  return s;
}

Future<Size> _pump(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(MaterialApp(
    home: Directionality(
      textDirection: s.isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        body: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 60),
          child: Align(alignment: Alignment.topCenter, child: BillingMomentCard(state: s)),
        ),
      ),
    ),
  ));
  return tester.getSize(find.byType(BillingMomentCard));
}

List<String> _texts(WidgetTester tester) =>
    tester.widgetList<Text>(find.descendant(of: find.byType(BillingMomentCard), matching: find.byType(Text))).map((t) => t.data ?? '').toList();

void main() {
  for (final trial in [true, false]) {
    for (final lang in AppLang.values) {
      final what = '${trial ? 'the free week' : 'the paid month'} in ${lang.name}';

      testWidgets('$what fits the Today slot and says plainly that nothing renews', (tester) async {
        final s = _endingIn(const Duration(hours: 5), trial: trial, lang: lang);
        expect(s.billingMoment, trial ? BillingMoment.trialEnding : BillingMoment.membershipEnding);

        final size = await _pump(tester, s);
        expect(size.height, lessThanOrEqualTo(BillingMomentCard.maxHeight), reason: 'one slot, 120pt at most');
        expect(size.height, greaterThan(0));

        final all = _texts(tester).join(' | ');
        expect(all, contains(lang == AppLang.ar ? 'مفيش حاجة بتتجدد لوحدها' : 'nothing renews on its own'));
        expect(all.toLowerCase(), isNot(contains('cancel')));
        expect(all, isNot(contains('إلغاء')));
        if (lang == AppLang.ar) {
          expect(RegExp('[0-9]').hasMatch(all), isFalse, reason: 'Eastern digits throughout: $all');
        }
      });
    }
  }

  testWidgets('with no billing moment due it takes no space', (tester) async {
    final lite = AppState(clock: () => _now);
    expect(lite.billingMoment, BillingMoment.none);
    final size = await _pump(tester, lite);
    expect(size.height, 0);

    final early = _endingIn(const Duration(days: 5), trial: false, lang: AppLang.en);
    expect(early.billingMoment, BillingMoment.none, reason: 'only the last 48 hours');
  });

  testWidgets('tapping it opens the paywall', (tester) async {
    final s = _endingIn(const Duration(hours: 30), trial: false, lang: AppLang.en);
    await _pump(tester, s);
    expect(find.textContaining('Your Qamar+ month ends tomorrow'), findsOneWidget);
    await tester.tap(find.byType(BillingMomentCard));
    expect(s.screen, AppScreen.subscription);
  });
}
