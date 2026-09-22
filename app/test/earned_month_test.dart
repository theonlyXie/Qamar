// The earned month's rule is the server's (0058: billing_config, 20 of 30 at
// launch). Every sentence in the app that states it must read `needed` and
// `windowDays` from the status — never a number of its own — so the operator
// can tune it without a release and no screen goes stale.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/billing.dart';
import 'package:qamar/state/app_state.dart';

AppState _member({required int needed, required AppLang lang}) {
  final s = AppState()
    ..plusActive = true
    ..plusUntil = DateTime.now().toUtc().add(const Duration(days: 20))
    ..earnedMonth = EarnedMonth(open: true, loggedDays: 9, needed: needed, windowDays: 30, daysLeft: 12, eligible: false, claimed: false);
  s.setLang(lang);
  return s;
}

Future<String> _screenText(WidgetTester tester, AppState s, AppScreen screen) async {
  await tester.binding.setSurfaceSize(const Size(900, 2400)); // wide: this checks the words, not the layout
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  s.go(screen);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return tester.widgetList<Text>(find.byType(Text)).map((t) => t.data ?? t.textSpan?.toPlainText() ?? '').join(' | ');
}

void main() {
  testWidgets('the launch rule, 20 of 30, is what Today and the plan tile say', (tester) async {
    final today = await _screenText(tester, _member(needed: 20, lang: AppLang.en), AppScreen.today);
    expect(today, contains('9 of 20 days logged'));
    expect(today, contains('Log 20 of your first 30 days and the next month is free.'));
    expect(today, isNot(contains('28')));

    final tile = await _screenText(tester, _member(needed: 20, lang: AppLang.en), AppScreen.subscription);
    expect(tile, contains('A month on us: 9 of 20 days logged'));
  });

  testWidgets('a threshold tuned on the server is the one stated, in both languages', (tester) async {
    final en = await _screenText(tester, _member(needed: 24, lang: AppLang.en), AppScreen.today);
    expect(en, contains('9 of 24 days logged'));
    expect(en, contains('Log 24 of your first 30 days'));
    expect(en, isNot(contains('of 20 days')));

    final ar = await _screenText(tester, _member(needed: 24, lang: AppLang.ar), AppScreen.today);
    expect(ar, contains('٢٤'), reason: 'the server’s number, in Eastern digits');
    expect(ar, isNot(contains('٢٠ يوم')));
    expect(ar, isNot(contains('٢٨')));
  });

  test('before the server answers, the fallback is the launch rule', () {
    expect(EarnedMonth.none.needed, 20);
    expect(EarnedMonth.none.windowDays, 30);
    expect(EarnedMonth.fromJson(const {}).needed, 20);
    expect(EarnedMonth.fromJson(const {'needed': 22, 'window_days': 30}).needed, 22);
  });
}
