// A nutritionist's code in Me (O12, 0069), each side one row away in its
// own sheet. The client's sheet takes the code and never states a trial
// length of its own; the professional's sheet promises clients the free days
// only when the operator has confirmed the code, and in the server's days.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/billing.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/state/app_state.dart';

/// The latest definition of [name] across every migration, as the database
/// ends up with it (the behaviour itself is checked in PGlite).
String _latestFunction(String name) {
  final files = Directory('supabase/migrations').listSync().whereType<File>().where((f) => f.path.endsWith('.sql')).toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  String? body;
  for (final f in files) {
    for (final m in RegExp('create or replace function public\\.$name\\(.*?\\n\\\$\\\$;', dotAll: true).allMatches(f.readAsStringSync())) {
      body = m.group(0);
    }
  }
  expect(body, isNotNull, reason: '$name is defined');
  return body!;
}

Future<String> _me(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(const Size(900, 3200)); // tall: this checks the words, not the layout
  addTearDown(() => tester.binding.setSurfaceSize(null));
  // A fresh app each time: a sheet left open by the last one goes with it.
  await tester.pumpWidget(const SizedBox());
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  s.go(AppScreen.you);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return _texts(tester);
}

String _texts(WidgetTester tester) => tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join(' | ');

/// Opens the sheet behind [row] on Me, and reads what is on screen.
Future<String> _open(WidgetTester tester, Key row) async {
  await tester.tap(find.byKey(row));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 700)); // the sheet rises
  return _texts(tester);
}

void main() {
  testWidgets('the client types the code in Me; with no account yet it waits on the phone and says so', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    var text = await _me(tester, s);
    expect(text, contains('Nutritionist’s code'), reason: 'the row on Me');
    expect(text, contains('If a nutritionist or coach sent you, add their code.'), reason: 'and what it is for, under it');
    text = await _open(tester, YouScreen.proCodeRowKey);
    expect(text, contains('If a nutritionist or coach sent you, enter their code.'));
    expect(text, isNot(contains('14')), reason: 'the length is the server’s; the answer says the days given');

    await tester.enterText(find.byKey(const ValueKey('pro-code-field')), 'qmr sara1');
    await tester.tap(find.byKey(const ValueKey('pro-code-use')));
    await tester.pump();
    expect(s.pendingProCode, 'QMRSARA1');
    expect(s.trialWaiting, isFalse);
    expect(find.textContaining('kept on this phone'), findsOneWidget);
  });

  testWidgets('once a code is on the account, Me names the professional and asks for no other', (tester) async {
    for (final lang in AppLang.values) {
      final s = AppState()
        ..setLang(lang)
        ..proName = 'Dr. Sara';
      final text = await _me(tester, s);
      expect(text, contains(lang == AppLang.ar ? 'كود Dr. Sara على حسابك' : 'Dr. Sara’s code is on your account.'));
      expect(find.byKey(const ValueKey('pro-code-field')), findsNothing);
      // The row names them, and asks for no other: it goes nowhere.
      expect(find.descendant(of: find.byKey(YouScreen.proCodeRowKey), matching: find.text('Dr. Sara')), findsOneWidget);
      await tester.tap(find.byKey(YouScreen.proCodeRowKey));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.byKey(const ValueKey('pro-code-field')), findsNothing, reason: 'no field to type another into');
    }
  });

  testWidgets('the professional is promised clients\' free days only for a confirmed code, in the server\'s days', (tester) async {
    final confirmed = AppState()
      ..setLang(AppLang.en)
      ..affiliateWallet = const AffiliateWallet(code: 'QMRSARA1', professional: true, clientTrialDays: 14);
    await _me(tester, confirmed);
    var text = await _open(tester, YouScreen.programmeRowKey);
    expect(text, contains('A client who enters it in Me before subscribing also gets 14 days of Qamar+ free.'));

    final unconfirmed = AppState()
      ..setLang(AppLang.en)
      ..affiliateWallet = const AffiliateWallet(code: 'QMROMAR1', clientTrialDays: 14);
    await _me(tester, unconfirmed);
    text = await _open(tester, YouScreen.programmeRowKey);
    expect(text, contains('Once Qamar confirms you are a nutritionist or coach, a client who enters it in Me also gets 14 days of Qamar+ free.'));
    expect(text, isNot(contains('before subscribing also gets')));

    final tuned = AppState()
      ..setLang(AppLang.ar)
      ..affiliateWallet = const AffiliateWallet(code: 'QMRSARA1', professional: true, clientTrialDays: 21);
    await _me(tester, tuned);
    text = await _open(tester, YouScreen.programmeRowKey);
    expect(text, contains('٢١'), reason: 'the server’s number, in Eastern digits');

    final unstated = AppState()
      ..setLang(AppLang.en)
      ..affiliateWallet = const AffiliateWallet(code: 'QMRSARA1', professional: true);
    await _me(tester, unstated);
    text = await _open(tester, YouScreen.programmeRowKey);
    expect(text, isNot(contains('days of Qamar+ free')), reason: 'no days stated by the server, no promise');
  });

  group('the SQL behind it (0069)', () {
    test('only a confirmed professional\'s code starts the fortnight, and it is recorded as pro', () {
      final body = _latestFunction('qamar_redeem_pro_code');
      expect(body, contains('if not v_promo.professional then'), reason: 'every account has an affiliate code; only a confirmed one gives the trial');
      expect(body, contains('public.qamar_start_trial(v_uid, v_days)'), reason: '0049\'s two-argument trial');
      expect(body, contains("set source = 'pro'"));
      expect(body, contains("'pro_trial_days'"), reason: 'the length is config');
    });

    test('the free week records itself as organic', () {
      final body = _latestFunction('qamar_start_trial');
      expect(body, contains('public.qamar_start_trial(p_user_id, 7)'));
      expect(body, contains("set source = 'organic'"));
    });
  });
}
