// The orb's receipt (O9), seat 6's part: where it sits and how it moves.
// Seats 2 and 4 settled what it says (a coin and the signed amount, never a
// balance, never a zero) and that nothing is drawn with "Points and streaks"
// off; su_display_test.dart holds that. Here: it sits over the orb, just
// above the tab bar's middle, in both languages; it arrives with an ease-out
// and leaves with an ease-in, no overshoot; it makes no haptic.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/models/activity.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/layout.dart';
import 'package:qamar/widgets/tab_bar.dart';

import 'support/app_fonts.dart';

const _area = Size(390, 844);

Future<void> _pumpOrb(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(_area);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: MaterialApp(
      builder: (context, child) => Directionality(
        textDirection: context.watch<AppState>().isAr ? TextDirection.rtl : TextDirection.ltr,
        child: child!,
      ),
      home: const Scaffold(body: Stack(children: [QTabBar()])),
    ),
  ));
  await tester.pump();
}

Future<void> _earn(AppState s) async {
  s.chooseActivity(ActivityKind.walk);
  await s.logActivity(20);
}

void main() {
  setUpAll(loadAppFonts);

  for (final lang in AppLang.values) {
    testWidgets('over the orb, just above the bar’s middle, never on the moon (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.go(AppScreen.today);
      await _pumpOrb(tester, s);
      await _earn(s);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400)); // arrived
      final orb = tester.getRect(find.byKey(QTabBar.orbKey));
      final bar = tester.getRect(find.byKey(QTabBar.barKey));
      final receipt = tester.getRect(find.byType(SuReceiptChip));

      expect(receipt.center.dx, moreOrLessEquals(orb.center.dx, epsilon: 0.5), reason: 'over the moon it came from');
      expect(receipt.bottom, moreOrLessEquals(bar.top - 8, epsilon: 0.5), reason: 'just above the bar');
      expect(receipt.overlaps(orb), isFalse, reason: 'never on the moon');
      expect(receipt.top, greaterThanOrEqualTo(_area.height - QLayout.pageBottom - receipt.height), reason: 'at the page’s foot, where it fades under the bar');
    });
  }

  test('it eases in and out, and never overshoots', () {
    var lastOpacity = 0.0, lastRise = double.infinity;
    for (var i = 0; i <= 240; i++) {
      final t = i / 2000; // the first 240ms of two seconds
      final m = SuReceiptChip.motionAt(t, still: false);
      expect(m.opacity, inInclusiveRange(0, 1));
      expect(m.opacity, greaterThanOrEqualTo(lastOpacity), reason: 'it only brightens as it arrives');
      expect(m.rise, greaterThanOrEqualTo(0), reason: 'it rises into place and stops there: no overshoot past it');
      expect(m.rise, lessThanOrEqualTo(lastRise));
      lastOpacity = m.opacity;
      lastRise = m.rise;
    }
    // Ease-out: most of the way in the first half of the entrance.
    expect(SuReceiptChip.motionAt(0.06, still: false).opacity, greaterThan(0.8));
    expect(SuReceiptChip.motionAt(0.5, still: false), (opacity: 1.0, rise: 0.0));
    // Ease-in on the way out: slow to start going.
    expect(SuReceiptChip.motionAt(0.9, still: false).opacity, greaterThan(0.8));
    expect(SuReceiptChip.motionAt(1.0, still: false).opacity, 0);
    // Reduced motion: it does not move, it appears and goes.
    for (final t in [0.0, 0.05, 0.5, 0.95]) {
      expect(SuReceiptChip.motionAt(t, still: true), (opacity: 1.0, rise: 0.0));
    }
  });

  testWidgets('it makes no haptic: a receipt, not a reward', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    await _pumpOrb(tester, s);
    await _earn(s);
    final haptics = <MethodCall>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method.startsWith('HapticFeedback') || call.method == 'SystemSound.play') haptics.add(call);
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
    for (var i = 0; i < 25; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(SuReceiptChip), findsOneWidget);
    expect(haptics, isEmpty);
  });
}
