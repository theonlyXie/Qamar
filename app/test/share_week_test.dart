// "Share the week" waits for three logged days, as the week card on Today
// does (the coordinator's ruling on seat 3's review). Before then the card's
// sentence is what is still missing ("Log at least 3 days … 2 to go."),
// said to the person; sent to someone else it would be an instruction to
// them. Both sides of the threshold: in the state, and on the button.

import 'dart:ui' show Tristate;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/screens/progress_screen.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/services/sharer.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';

import 'support/app_fonts.dart';

final _now = DateTime(2026, 9, 23, 13);

AppState _state(AppLang lang, {required int logged, required MemorySharer sharer}) {
  final s = AppState(clock: () => _now, sharer: sharer)..setLang(lang);
  s.setFasting(false);
  s.dismissOrbTutorial();
  for (var back = 1; back <= logged; back++) {
    s.dayHistory.add(DayTotals(day: DateTime(2026, 9, 23 - back), kcal: 1900, meals: 2));
  }
  s.go(AppScreen.today);
  s.go(AppScreen.progress);
  return s;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  test('two logged days share nothing; three share the week', () async {
    final none = MemorySharer();
    final two = _state(AppLang.en, logged: 2, sharer: none);
    expect(two.weekReview().enough, isFalse);
    await two.shareReview(Uint8List.fromList([1, 2, 3]));
    expect(none.shared, isEmpty, reason: 'under three days nothing is sent');

    final one = MemorySharer();
    final three = _state(AppLang.en, logged: 3, sharer: one);
    expect(three.weekReview().enough, isTrue);
    await three.shareReview(Uint8List.fromList([1, 2, 3]));
    expect(one.shared, hasLength(1));
  });

  for (final lang in AppLang.values) {
    testWidgets('on Progress, Share is off at two days and on at three (${lang.name})', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390, 2400) * 3;
      addTearDown(tester.view.reset);
      final handle = tester.ensureSemantics();
      final sharer = MemorySharer();

      for (final (logged, on) in [(2, false), (3, true)]) {
        final s = _state(lang, logged: logged, sharer: sharer);
        await tester.pumpWidget(ChangeNotifierProvider.value(key: ValueKey(logged), value: s, child: const QamarApp()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final share = find.byKey(ProgressScreen.shareKey);
        expect(share, findsOneWidget);
        expect(tester.widget<QOutlineButton>(share).onTap != null, on, reason: '$logged logged days');
        final data = tester.getSemantics(find.descendant(of: share, matching: find.byType(Semantics)).first).getSemanticsData();
        expect(data.flagsCollection.isEnabled, on ? Tristate.isTrue : Tristate.isFalse, reason: 'a screen reader hears it off too');
      }

      // Off, a tap sends nothing.
      final s = _state(lang, logged: 2, sharer: sharer);
      await tester.pumpWidget(ChangeNotifierProvider.value(key: const ValueKey('tap'), value: s, child: const QamarApp()));
      await tester.pump();
      await tester.tap(find.byKey(ProgressScreen.shareKey), warnIfMissed: false);
      await tester.pump();
      expect(sharer.shared, isEmpty);
      handle.dispose();
    });
  }
}
