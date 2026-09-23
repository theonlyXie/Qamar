// What the paywall promises (O14). Every clause has to be true for the person
// reading it: the price against one nutritionist visit, not below it; "same
// price for everyone" only while no campaign code has lowered it; the earned
// month in the server's numbers, only once the server has stated them and the
// month can still be earned; and "nothing renews on its own", because nothing
// does and there is nothing to cancel.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/billing.dart';
import 'package:qamar/screens/subscription_screen.dart';
import 'package:qamar/state/app_state.dart';

/// A free-tier person whose earned-month status the server has answered:
/// no paid membership yet, so the window opens on the first payment.
EarnedMonth _stated({int needed = 20, int window = 30, bool claimed = false, DateTime? windowStart, bool open = false}) => EarnedMonth(
      open: open,
      loggedDays: 0,
      needed: needed,
      windowDays: window,
      daysLeft: 0,
      eligible: false,
      claimed: claimed,
      windowStart: windowStart,
    );

AppState _lite(AppLang lang, {EarnedMonth? earned, PlusQuote? quote}) {
  final s = AppState()..setLang(lang);
  if (earned != null) s.earnedMonth = earned;
  if (quote != null) s.plusQuote = quote;
  return s;
}

Future<String> _paywall(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(const Size(900, 3000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  s.go(AppScreen.subscription);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join(' | ');
}

String _banner(WidgetTester tester) => tester.widget<Text>(find.byKey(SubscriptionScreen.bannerKey)).data!;

void main() {
  testWidgets('the agreed banner, in both languages, with the server\'s numbers', (tester) async {
    await _paywall(tester, _lite(AppLang.en, earned: _stated()));
    expect(
      _banner(tester),
      'EGP 500 a month — about one nutritionist visit, with Qamar at every meal. Same price for everyone. '
      'Log 20 of your first 30 days after you subscribe and the next month is on us. Nothing renews on its own.',
    );

    await _paywall(tester, _lite(AppLang.ar, earned: _stated()));
    final ar = _banner(tester);
    expect(ar, contains('في حدود تمن كشف واحد عند أخصائي تغذية، وقمر معاك في كل وجبة.'));
    expect(ar, contains('نفس السعر للكل.'));
    expect(ar, contains('سجّل \u2066٢٠\u2069 يوم من أول \u2066٣٠\u2069 يوم بعد ما تشترك، والشهر اللي بعده علينا.'));
    expect(ar, contains('ومفيش حاجة بتتجدد لوحدها.'));
    expect(ar, isNot(contains('20')), reason: 'Eastern digits in Arabic');
  });

  testWidgets('a threshold tuned on the server is the one the banner states', (tester) async {
    await _paywall(tester, _lite(AppLang.en, earned: _stated(needed: 24, window: 31)));
    expect(_banner(tester), contains('Log 24 of your first 31 days after you subscribe'));
  });

  testWidgets('the banner counts its days by the app’s one rule in Arabic: "١٠ أيام", and 11 on in the singular', (tester) async {
    await _paywall(tester, _lite(AppLang.ar, earned: _stated(needed: 10, window: 30)));
    final ar = _banner(tester).replaceAll(RegExp('[\u2066-\u2069]'), '');
    expect(ar, contains('سجّل ١٠ أيام من أول ٣٠ يوم بعد ما تشترك'));
    await _paywall(tester, _lite(AppLang.en, earned: _stated(needed: 1, window: 1)));
    expect(_banner(tester), contains('Log 1 of your first 1 day after you subscribe'), reason: 'never "1 days"');
  });

  testWidgets('before the server has answered, the earned month is not stated from the fallback', (tester) async {
    final s = _lite(AppLang.en);
    expect(s.earnedMonth.stated, isFalse);
    await _paywall(tester, s);
    expect(_banner(tester), isNot(contains('Log ')));
    expect(_banner(tester), isNot(contains('on us')));
    expect(_banner(tester), contains('Nothing renews on its own.'));
  });

  testWidgets('once granted, or once the first 30 paid days are over, the month is not on offer', (tester) async {
    await _paywall(tester, _lite(AppLang.en, earned: _stated(claimed: true)));
    expect(_banner(tester), isNot(contains('on us')));
    await _paywall(tester, _lite(AppLang.en, earned: _stated(windowStart: DateTime.utc(2026, 7, 1))));
    expect(_banner(tester), isNot(contains('on us')), reason: 'the window opened on the first payment and has closed');
    await _paywall(tester, _lite(AppLang.en, earned: _stated(windowStart: DateTime.utc(2026, 9, 10), open: true)));
    expect(_banner(tester), contains('the next month is on us'), reason: 'still inside the window');
  });

  testWidgets('a campaign code that lowers the price takes "same price for everyone" away', (tester) async {
    const campaign = PlusQuote(
      plan: 'monthly',
      days: 30,
      listCents: 50000,
      amountCents: 25000,
      pricingReason: 'campaign',
      firstPurchase: true,
      promoCode: 'RAMADAN',
      promoKind: 'campaign',
    );
    await _paywall(tester, _lite(AppLang.en, earned: _stated(), quote: campaign));
    expect(_banner(tester), isNot(contains('Same price for everyone')));
    expect(_banner(tester), startsWith('EGP 500 a month'), reason: 'the list price, which the tile shows struck through');
  });

  testWidgets('nothing on the paywall offers a cancel, a "less than one visit", or "no discounts"', (tester) async {
    for (final lang in AppLang.values) {
      final text = await _paywall(tester, _lite(lang, earned: _stated()));
      for (final never in ['cancel', 'Cancel', 'less than', 'No annual', 'no discounts', 'إلغاء', 'أقل من زيارة', 'خصومات']) {
        expect(text, isNot(contains(never)), reason: '$never, in ${lang.name}');
      }
      expect(text, contains(lang == AppLang.ar ? '٣٠ يوم · مفيش حاجة بتتجدد لوحدها' : '30 days · nothing renews on its own'), reason: 'the plan tile');
    }
  });

  testWidgets('the paywall leads with tomorrow: the first line, and the first row of the table', (tester) async {
    final text = await _paywall(tester, _lite(AppLang.en, earned: _stated()));
    expect(tester.widget<Text>(find.byKey(SubscriptionScreen.leadKey)).data,
        'Qamar+ tells you what to eat tomorrow: it writes the plan at night, in Egyptian dishes.');
    final table = text.substring(text.indexOf('What you get'));
    expect(table.indexOf('Tomorrow’s plan, written overnight'), lessThan(table.indexOf('Log meals by typing or speaking')),
        reason: 'tomorrow’s plan is the table’s first row');
  });

  test('a paying member is told the month simply runs out, not how to cancel', () async {
    for (final lang in AppLang.values) {
      final s = AppState()
        ..setLang(lang)
        ..plusActive = true
        ..plusUntil = DateTime.utc(2026, 10, 20, 12);
      await s.startPlusPurchase();
      expect(s.plusNotice, lang == AppLang.ar ? contains('ومفيش حاجة بتتجدد لوحدها') : contains('nothing renews on its own'));
      expect(s.plusNotice, isNot(contains(lang == AppLang.ar ? 'تلغي' : 'cancel')));
    }
  });

  testWidgets('Arabic rows write the brand as قمر+, never a Latin "Qamar+" an RTL line draws as "(+Qamar"', (tester) async {
    final text = await _paywall(tester, _lite(AppLang.ar, earned: _stated()));
    expect(text, contains('(٣٠ مع قمر+)'));
    expect(text, contains('(٥٠ مع قمر+)'));
    expect(text, isNot(contains('مع Qamar+')));
  });

  group('a typed professional\'s code that is not the one paid says why', () {
    test('each reason, in both languages, never claiming the code pays a share', () {
      for (final notice in ['referral_ended', 'other_professional', 'unchecked']) {
        for (final ar in [false, true]) {
          final line = SubscriptionScreen.promoNoticeLine(ar, notice);
          expect(line, isNotNull);
          expect(line, contains(ar ? 'السعر زي ما هو' : 'Your price is the same'));
          expect(line, isNot(contains(ar ? 'الكود شغال' : 'Code applied')));
        }
      }
      // Pinned: another professional may be a claim on the account before any
      // payment, so it is "your account", never "your subscription" — the
      // word Me's refusal uses. A referral ends only after payments, so there
      // "subscription" is true.
      expect(SubscriptionScreen.promoNoticeLine(false, 'other_professional'),
          'Another nutritionist is already on your account, and their share stays with them for their twelve months. To change, write to support. Your price is the same.');
      expect(SubscriptionScreen.promoNoticeLine(true, 'other_professional'),
          'فيه أخصائي تاني على حسابك، وهو اللي بياخد النصيب لحد ما سنته تخلص. لو عايز تغيّر، كلّم الدعم. السعر زي ما هو.');
      expect(SubscriptionScreen.promoNoticeLine(false, 'referral_ended'), contains('twelve months on your subscription have ended'));
      expect(SubscriptionScreen.promoNoticeLine(false, null), isNull);
      expect(SubscriptionScreen.promoNoticeLine(false, 'something new'), isNull);
    });

    test('the quote keeps only the reasons the phone can say', () {
      expect(PlusQuote.fromJson(const {'promo_notice': 'referral_ended'}).promoNotice, 'referral_ended');
      expect(PlusQuote.fromJson(const {'promo_notice': 'rm -rf'}).promoNotice, isNull);
      expect(PlusQuote.fromJson(const {}).promoNotice, isNull);
    });

    testWidgets('on the paywall it replaces "Code applied", even though another professional is paid', (tester) async {
      const quote = PlusQuote(
        plan: 'monthly', days: 30, listCents: 50000, amountCents: 50000,
        pricingReason: 'affiliate', firstPurchase: false, promoCode: 'QMRSARA1', promoKind: 'affiliate',
        promoNotice: 'other_professional',
      );
      await _paywall(tester, _lite(AppLang.en, earned: _stated(), quote: quote));
      final line = tester.widget<Text>(find.byKey(SubscriptionScreen.codeLineKey)).data!;
      expect(line, startsWith('Another nutritionist is already on your account'));
      expect(line, isNot(contains('Code applied')));
    });

    testWidgets('with no reason, the line is what it was', (tester) async {
      await _paywall(tester, _lite(AppLang.en, earned: _stated()));
      expect(tester.widget<Text>(find.byKey(SubscriptionScreen.codeLineKey)).data, startsWith('If a nutritionist or coach sent you'));
    });
  });

  group('how to pay names only what checkout can take', () {
    test('the rails the server names, in both languages', () {
      expect(SubscriptionScreen.paymentLine(false, const ['card', 'meeza', 'wallet']),
          'You pay in EGP through Paymob: Visa or Mastercard, a Meeza card, or Vodafone Cash or another mobile wallet. Qamar+ turns on once Paymob confirms the payment.');
      expect(SubscriptionScreen.paymentLine(true, const ['card', 'wallet']),
          'الدفع بالجنيه عن طريق Paymob: فيزا أو ماستركارد، أو فودافون كاش أو أي محفظة موبايل. قمر+ بيتفعل أول ما Paymob يأكد الدفع.');
      expect(SubscriptionScreen.paymentLine(false, const ['card']), startsWith('You pay in EGP through Paymob: Visa or Mastercard.'));
    });

    test('with no rail stated, none is named: no Vodafone Cash, no Meeza', () {
      for (final ar in [false, true]) {
        final line = SubscriptionScreen.paymentLine(ar, const []);
        for (final never in ['Vodafone', 'Meeza', 'Visa', 'فودافون', 'ميزة', 'فيزا']) {
          expect(line, isNot(contains(never)));
        }
      }
    });

    test('the quote carries the server\'s rails and nothing else', () {
      final q = PlusQuote.fromJson(const {'payment_methods': ['card', 'wallet', 'fawry', 7]});
      expect(q.paymentMethods, ['card', 'wallet'], reason: 'only rails the paywall knows how to name');
      expect(PlusQuote.fromJson(const {}).paymentMethods, isEmpty);
    });

    testWidgets('the paywall shows it', (tester) async {
      const quote = PlusQuote(plan: 'monthly', days: 30, listCents: 50000, amountCents: 50000, pricingReason: 'list', firstPurchase: true, paymentMethods: ['wallet']);
      await _paywall(tester, _lite(AppLang.en, earned: _stated(), quote: quote));
      final line = tester.widget<Text>(find.byKey(SubscriptionScreen.paymentKey)).data!;
      expect(line, contains('Vodafone Cash or another mobile wallet'));
      expect(line, isNot(contains('Mastercard')), reason: 'no card integration was named');
    });
  });
}

