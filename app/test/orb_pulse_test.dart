// The orb's pulse (the in-app prompt after the fortnight of pushes) promises
// only what the hold will do: it stops once its question has been passed.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/living_orb.dart';

import 'support/app_fonts.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  testWidgets('the orb on Today pulses while its question waits, and stops once the talk has moved past it', (tester) async {
    final s = AppState(clock: () => DateTime(2027, 2, 5, 14, 30))..setLang(AppLang.en);
    s.setFasting(false);
    s.dismissOrbTutorial();
    s.go(AppScreen.today);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
    await tester.pump();
    bool pulsing() => tester.widgetList<LivingOrb>(find.byType(LivingOrb)).any((o) => o.speaking);
    expect(pulsing(), isTrue, reason: 'lunch’s question waits');

    await s.holdOrb(); // Qamar asks it
    s.closeChat();
    s.quickLog(QuickLog.text); // the talk moves on: "Tell me what you ate."
    s.closeChat();
    await tester.pump();
    expect(s.waitingNudge, isNotNull, reason: 'lunch is still not logged');
    expect(pulsing(), isFalse, reason: 'the hold would not ask it again, so the orb does not promise it');
  });
}
