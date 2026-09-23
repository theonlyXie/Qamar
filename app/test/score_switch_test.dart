// "Points and streaks" (O4): one switch in Me, on by default and kept on this
// phone. Off hides everything on screen that keeps score — Today's Su chip,
// the orb's receipt and streak ring, the streak line, the quest and its coin,
// Progress's streak card and the week card's streak — and only hides it:
// points are still earned, the streak still counts, the quest is still paid
// when met, and the wallet in Me still shows the balance.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/quest.dart';
import 'package:qamar/models/streak.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/screens/progress_screen.dart';
import 'package:qamar/screens/today_screen.dart';
import 'package:qamar/screens/wallet_screen.dart';
import 'package:qamar/screens/you_screen.dart';
import 'package:qamar/services/device_prefs.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/icons.dart';
import 'package:qamar/widgets/dot_number.dart';
import 'package:qamar/widgets/living_orb.dart';
import 'package:qamar/widgets/orb_nav.dart';
import 'package:qamar/widgets/quest_card.dart';
import 'package:qamar/widgets/review_card.dart';

import 'support/app_fonts.dart';

final _now = DateTime(2027, 3, 10, 13);

/// A day with everything that keeps score in it: a run of three that today
/// has joined, and a quest the server chose.
AppState _state(AppLang lang) {
  final s = AppState(clock: () => _now)..setLang(lang);
  s.profile = s.profile.copyWith(name: 'Basel');
  s.setFasting(false);
  s.dismissOrbTutorial();
  s.serverStreak = const Streak(current: 3, best: 3, todayCounted: true);
  s.quest = DayQuest(kind: QuestKind.water6, done: false, expiresAt: _now.add(const Duration(hours: 6)));
  return s;
}

LoggedMeal _koshary() => LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: _now);

Future<void> _pump(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(const Size(390, 844));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

final _ring = find.byWidgetPredicate((w) => w is CustomPaint && w.painter is StreakRingPainter, description: 'the orb’s streak ring');

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  group('the switch', () {
    test('is on by default, and the choice survives a relaunch on the same phone', () async {
      final prefs = MemoryDevicePrefs();
      final first = AppState(prefs: prefs);
      expect(first.showScore, isTrue);
      first.setShowScore(false);
      await Future<void>.delayed(Duration.zero);
      final again = AppState(prefs: prefs);
      await Future<void>.delayed(Duration.zero);
      expect(again.showScore, isFalse);
    });

    test('off only hides: points are still earned, the streak still counts, the quest still waits', () {
      final s = _state(AppLang.en)..setShowScore(false);
      final before = s.suAvailable;
      s.repeatMeal(_koshary());
      expect(s.suAvailable, before + SuEconomy.firstMeal, reason: 'the meal still earns');
      expect(s.suReceipt?.amount, SuEconomy.firstMeal, reason: 'the receipt is made, only not drawn');
      expect(s.streak().current, greaterThanOrEqualTo(3), reason: 'the run still counts');
      expect(s.orbState().streak.current, 0, reason: 'but the orb draws no ring for it');
      expect(s.quest, isNotNull, reason: 'the quest is still held, and the server still pays it when met');
      expect(s.questDue, isFalse, reason: 'it is only not shown');

      // Switching back costs nothing: everything is where it was.
      s.setShowScore(true);
      expect(s.questDue, isTrue);
      expect(s.orbState().streak.current, greaterThanOrEqualTo(3));
      expect(s.suAvailable, before + SuEconomy.firstMeal);
    });
  });

  for (final lang in AppLang.values) {
    final ar = lang == AppLang.ar;

    testWidgets('in Me, under the wallet, it says what it hides; off keeps the wallet (${lang.name})', (tester) async {
      final s = _state(lang)..go(AppScreen.you);
      await _pump(tester, s);
      final toggle = find.byKey(YouScreen.scoreSwitchKey);
      await tester.dragUntilVisible(toggle, find.byType(ListView).first, const Offset(0, -200));
      await tester.pump();
      expect(find.text(ar ? 'النقاط والسلسلة' : 'Points and streaks'), findsOneWidget);
      expect(find.textContaining(ar ? 'بتستخبى بس' : 'Off only hides them'), findsOneWidget);
      expect(tester.getSize(toggle).height, greaterThanOrEqualTo(48), reason: 'a full touch target');

      await tester.tap(toggle);
      await tester.pump();
      expect(s.showScore, isFalse);
      expect(find.text(s.t.walletTitle), findsOneWidget, reason: 'the wallet stays, for whoever goes to look');
    });

    testWidgets('the whole row is the control, not only the switch (${lang.name})', (tester) async {
      final s = _state(lang)..go(AppScreen.you);
      await _pump(tester, s);
      await tester.dragUntilVisible(find.byKey(YouScreen.scoreRowKey), find.byType(ListView).first, const Offset(0, -200));
      await tester.pump();
      await tester.tap(find.text(ar ? 'النقاط والسلسلة' : 'Points and streaks'));
      await tester.pump();
      expect(s.showScore, isFalse, reason: 'a tap on the words turns it off');
      // Anywhere on the row: its glyph, at the other end from the switch.
      await tester.tap(find.descendant(of: find.byKey(YouScreen.scoreRowKey), matching: find.byIcon(QIcons.star)));
      await tester.pump();
      expect(s.showScore, isTrue, reason: 'and on again');
    });

    testWidgets('the wallet with it off: the balance to spend, and no Level or lifetime (${lang.name})', (tester) async {
      final s = _state(lang)
        ..suAvailable = 1250
        ..suLifetime = 3400
        ..go(AppScreen.wallet);
      await _pump(tester, s);
      final level = ar ? 'المستوى ${s.iso('${s.level()}')}' : 'Level ${s.level()}';
      expect(find.byKey(WalletScreen.levelKey), findsOneWidget);
      expect(find.text(level), findsOneWidget);
      expect(find.text(s.t.levelNote), findsOneWidget);
      expect(find.byKey(WalletScreen.lifetimeKey), findsOneWidget);

      s.setShowScore(false);
      await tester.pump();
      // The balance is the wallet's hero, drawn in dots.
      expect(tester.widget<DotNumber>(find.byKey(WalletScreen.balanceKey)).text, s.formatSu(1250), reason: 'the balance stays: spending needs it');
      expect(find.byKey(WalletScreen.levelKey), findsNothing, reason: 'the Level bar keeps score');
      expect(find.text(level), findsNothing);
      expect(find.text(s.t.levelNote), findsNothing);
      expect(find.byKey(WalletScreen.lifetimeKey), findsNothing, reason: 'lifetime earned is what Level is made of');
      expect(find.text(s.formatSu(3400)), findsNothing);

      // And Me's wallet row says only the balance.
      s.go(AppScreen.you);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.dragUntilVisible(find.text(s.t.walletTitle), find.byType(ListView).first, const Offset(0, -200));
      await tester.pump();
      expect(find.textContaining(s.formatSu(3400)), findsNothing);
      expect(find.descendant(of: find.byKey(YouScreen.walletRowKey), matching: find.text(s.formatSu(1250))), findsOneWidget);
    });

    testWidgets('Today with it off: no Su chip, streak line, quest, ring or receipt (${lang.name})', (tester) async {
      final s = _state(lang)..go(AppScreen.today);
      await _pump(tester, s);
      expect(find.byType(SuChip), findsOneWidget);
      expect(find.byType(TodayStreakLine), findsOneWidget);
      expect(find.byType(QuestCard), findsOneWidget);
      expect(_ring, findsWidgets);

      s.setShowScore(false);
      await tester.pump();
      expect(find.byType(SuChip), findsNothing);
      expect(find.byType(TodayStreakLine), findsNothing);
      expect(find.byType(QuestCard), findsNothing);
      expect(_ring, findsNothing);

      // Something earned while it is off makes no receipt on the orb.
      s.repeatMeal(_koshary());
      await tester.pump();
      expect(find.byType(SuReceiptChip), findsNothing);

      // On again, the receipt already passed is not replayed; the rest return.
      s.setShowScore(true);
      await tester.pump(SuReceipt.showFor);
      expect(find.byType(SuChip), findsOneWidget);
      expect(find.byType(TodayStreakLine), findsOneWidget);
      expect(_ring, findsWidgets);
    });

    testWidgets('Progress with it off: no streak card, no streak on the week card, and the screen closes up (${lang.name})', (tester) async {
      final s = _state(lang)..go(AppScreen.progress);
      await _pump(tester, s);
      final streakCard = find.byKey(ProgressScreen.streakKey);
      expect(streakCard, findsOneWidget);
      final run = find.descendant(of: find.byType(ReviewCard), matching: find.textContaining(ar ? 'أيام ورا بعض' : 'days in a row'));
      expect(run, findsOneWidget, reason: 'the week card carries the run while the score is shown');
      final cardTop = tester.getRect(streakCard).top;

      s.setShowScore(false);
      await tester.pump();
      expect(streakCard, findsNothing);
      expect(run, findsNothing, reason: 'nor on the card that gets shared');
      expect(tester.getRect(find.byType(ReviewCard)).top, lessThan(cardTop + 1),
          reason: 'the week card moves up into the space; nothing is held open');
    });
  }
}
