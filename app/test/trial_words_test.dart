// The trial's day counts go through the app's one count rule (Counted.day):
// one day, two days, 3–10 days, and the singular from eleven in Arabic, and
// the English plural (and verb) agreeing with the count. The free week is 7
// today and a nutritionist's code 14, but neither is promised to stay, so
// every phrase is checked at 1, 2, 7 and 14, in both languages.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/l10n/trial_words.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/billing.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/state/app_state.dart';

String _plain(String s) => s.replaceAll(RegExp('[\u2066-\u2069]'), '');

void main() {
  final ar = AppState()..setLang(AppLang.ar);
  String iso(String s) => ar.iso(s);

  // (days, English count, Arabic count)
  const counts = [
    (1, '1 day', 'يوم واحد'),
    (2, '2 days', 'يومين'),
    (7, '7 days', '٧ أيام'),
    (14, '14 days', '١٤ يوم'),
  ];

  test('every trial phrase counts its days by the rule, at 1, 2, 7 and 14, in both languages', () {
    for (final (n, en, arabic) in counts) {
      final cases = <(String, String, String, String)>[
        ('offerTitle', TrialWords.offerTitle(n, ar: false, iso: iso), TrialWords.offerTitle(n, ar: true, iso: iso), '$en of the full Qamar.'),
        ('waitingInMe', TrialWords.waitingInMe(n, ar: false, iso: iso), TrialWords.waitingInMe(n, ar: true, iso: iso), 'Your free week is waiting: $en, no card, nothing renews.'),
        ('started', TrialWords.started(n, ar: false, iso: iso), TrialWords.started(n, ar: true, iso: iso), 'Your week of the full Qamar has started: $en, no card, and nothing renews on its own.'),
        ('paywallRule', TrialWords.paywallRule(n, ar: false, iso: iso), TrialWords.paywallRule(n, ar: true, iso: iso), 'No card, and nothing renews on its own: after $en you are simply back on the free Qamar.'),
        ('lockLink', TrialWords.lockLink(n, ar: false, iso: iso), TrialWords.lockLink(n, ar: true, iso: iso), 'Open the plan with your free week: $en, no card'),
        ('clientDays confirmed', TrialWords.clientDays(n, confirmed: true, ar: false, iso: iso), TrialWords.clientDays(n, confirmed: true, ar: true, iso: iso), ' A client who enters it in Me before subscribing also gets $en of Qamar+ free.'),
        ('clientDays unconfirmed', TrialWords.clientDays(n, confirmed: false, ar: false, iso: iso), TrialWords.clientDays(n, confirmed: false, ar: true, iso: iso), ' Once Qamar confirms you are a nutritionist or coach, a client who enters it in Me also gets $en of Qamar+ free.'),
        ('nearTarget', TrialWords.nearTarget(n, ar: false, iso: iso), TrialWords.nearTarget(n, ar: true, iso: iso), '$en near target'),
      ];
      for (final (name, enText, arText, want) in cases) {
        expect(enText, want, reason: '$name at $n');
        expect(_plain(arText), contains(arabic), reason: '$name at $n in Arabic');
        if (n != 1) expect(_plain(arText), isNot(contains('يوم واحد')), reason: '$name at $n');
        if (n == 1 || n == 2) expect(_plain(arText), isNot(contains(RegExp('[٠-٩]'))), reason: '$name at $n: one and two are words, not digits');
        if (n == 14) expect(_plain(arText), isNot(contains('١٤ أيام')), reason: '$name: eleven on take the singular');
      }
    }
  });

  test('a nutritionist\'s days: the English verb agrees with the count', () {
    for (final (n, en, arabic) in counts) {
      final enText = TrialWords.proRedeemed('Dr. Sara', n, ar: false, iso: iso);
      expect(enText, 'Dr. Sara sent you. $en of Qamar+ ${n == 1 ? 'is' : 'are'} yours from now — no card, and nothing renews on its own.');
      expect(_plain(TrialWords.proRedeemed('Dr. Sara', n, ar: true, iso: iso)),
          'Dr. Sara بعتك. $arabic قمر+ عليك من دلوقتي — من غير بطاقة، ومفيش حاجة بتتجدد لوحدها.');
    }
  });

  test('the paywall\'s button is a verb and what it starts, with no count: the rule right under it says the days', () {
    expect(TrialWords.paywallButton(ar: false), 'Start the free week');
    expect(TrialWords.paywallButton(ar: true), 'ابدأ الأسبوع المجاني');
    for (final (n, en, arabic) in counts) {
      expect(TrialWords.paywallRule(n, ar: false, iso: iso), contains('after $en'));
      expect(_plain(TrialWords.paywallRule(n, ar: true, iso: iso)), contains('بعد $arabic'));
    }
  });

  test('the Arabic near-target phrase takes no agreement, so it reads right after one, two and many', () {
    for (final (n, _, arabic) in counts) {
      expect(_plain(TrialWords.nearTarget(n, ar: true, iso: iso)), '$arabic في حدود الهدف');
    }
  });

  // The screens use these phrases, not their own. [open] is a row whose
  // sheet holds them, tapped first.
  Future<String> screen(WidgetTester tester, AppState s, AppScreen at, {Key? open}) async {
    await tester.binding.setSurfaceSize(const Size(900, 3200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
    s.go(at);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    if (open != null) {
      await tester.tap(find.byKey(open));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
    }
    return _plain(tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join(' | '));
  }

  testWidgets('the professional\'s card says a confirmed code\'s days by the rule: 1 is يوم واحد, 2 is يومين', (tester) async {
    for (final (n, en, arabic) in const [(1, '1 day', 'يوم واحد'), (2, '2 days', 'يومين')]) {
      for (final lang in AppLang.values) {
        final s = AppState()
          ..setLang(lang)
          ..affiliateWallet = AffiliateWallet(code: 'QMRSARA1', professional: true, clientTrialDays: n);
        final text = await screen(tester, s, AppScreen.you, open: YouScreen.programmeRowKey);
        expect(text, contains(lang == AppLang.ar ? 'بياخد $arabic قمر+ ببلاش' : 'also gets $en of Qamar+ free'));
      }
    }
  });

  testWidgets('the clients card counts days near target by the rule, in both languages', (tester) async {
    for (final (n, en, arabic) in counts.where((c) => c.$1 <= 7)) {
      for (final lang in AppLang.values) {
        final s = AppState()
          ..setLang(lang)
          ..proClients = [ProClient(name: 'Omar', daysLogged: 7, onTargetDays: n, avgKcal: 1900, targetKcal: 2000)];
        final text = await screen(tester, s, AppScreen.you, open: YouScreen.programmeRowKey);
        expect(text, contains(lang == AppLang.ar ? '$arabic في حدود الهدف' : '$en near target'));
        expect(text, isNot(contains('قريب من الهدف')));
      }
    }
  });
}
