// The orb's sparks, seat 6's part (seat 4's review: at the band's reach
// every orbit was 16 to 25 points out, painted before a 28-point moon, so
// the moon covered them on every frame). They now ride a tilted ring wider
// than the moon: drawn over it, the near half passing in front, the far half
// clipped where the disc is, as if behind; the ring is flattened to stay in
// the band; the three are spread round it and loop without a seam; and the
// receipt sits clear of it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/models/activity.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/layout.dart';
import 'package:qamar/widgets/living_orb.dart';
import 'package:qamar/widgets/moon.dart';
import 'package:qamar/widgets/orb_nav.dart';

import 'support/app_fonts.dart';

const _area = Size(390, 844);
const _moonR = OrbNav.moon / 2 * 1.045; // at the top of its breath

Future<void> _pumpOrb(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(_area);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(
    value: s,
    child: const MaterialApp(home: Scaffold(body: Stack(children: [OrbNav()]))),
  ));
  await tester.pump();
}

/// Whether spark [i] can be seen at [t]: in front of the moon, or clear of
/// its disc.
bool _seen(int i, double t) {
  final p = LivingOrb.sparkAt(i, t, size: OrbNav.moon, reach: OrbNav.bandReach);
  return p.near || p.at.distance > _moonR + LivingOrb.sparkOrbits[i].size / 2;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  test('each spark is seen most of the way round, passes in front of the moon, goes behind it, and never jumps', () {
    for (var i = 0; i < LivingOrb.sparkOrbits.length; i++) {
      var seen = 0, inFront = 0, behind = 0;
      const n = 2000;
      for (var k = 0; k < n; k++) {
        final t = k / n;
        final p = LivingOrb.sparkAt(i, t, size: OrbNav.moon, reach: OrbNav.bandReach);
        if (_seen(i, t)) seen++;
        if (p.near && p.at.distance < _moonR) inFront++;
        if (!p.near && p.at.distance < _moonR) behind++;
      }
      expect(seen / n, greaterThan(0.6), reason: 'spark $i is seen, not hidden by the moon');
      expect(inFront, greaterThan(0), reason: 'spark $i crosses the moon’s face');
      expect(behind, greaterThan(0), reason: 'spark $i goes behind it');
      expect(LivingOrb.sparkAt(i, 0, size: OrbNav.moon, reach: OrbNav.bandReach).at, isNot(LivingOrb.sparkAt((i + 1) % 3, 0, size: OrbNav.moon, reach: OrbNav.bandReach).at), reason: 'spread round the ring');
      // Its ring is wider than the moon, flattened to the band, and the
      // loop has no seam: where the drift's cycle ends, it began.
      final o = LivingOrb.sparkOrbits[i];
      expect(o.across * OrbNav.moon, greaterThan(_moonR + o.size), reason: 'clear of the disc at the sides');
      final a = LivingOrb.sparkAt(i, 0, size: OrbNav.moon, reach: OrbNav.bandReach).at;
      final b = LivingOrb.sparkAt(i, 1, size: OrbNav.moon, reach: OrbNav.bandReach).at;
      expect((a - b).distance, lessThan(1e-6), reason: 'spark $i does not jump when the cycle repeats');
    }
  });

  testWidgets('drawn over the moon; behind it only where the ring is far', (tester) async {
    final s = AppState()..setLang(AppLang.en);
    s.go(AppScreen.today);
    await _pumpOrb(tester, s);
    final orb = find.byKey(OrbNav.orbKey);
    final stack = tester.widget<Stack>(find.ancestor(of: find.byKey(LivingOrb.sparkKey(0)), matching: find.byType(Stack)).first);
    final moonAt = stack.children.indexWhere((c) => find.descendant(of: find.byWidget(c), matching: find.byType(QamarMoon)).evaluate().isNotEmpty);
    expect(moonAt, isNonNegative);
    for (var i = 0; i < LivingOrb.sparkOrbits.length; i++) {
      final at = stack.children.indexWhere((c) => c.key == LivingOrb.sparkKey(i));
      expect(at, greaterThan(moonAt), reason: 'spark $i is painted after the moon, not under it');
    }

    // Sample the cycle: where the spark is drawn is where the ring puts it,
    // and it is clipped exactly when it is on the far side.
    var clipped = 0, open = 0;
    for (var k = 0; k < 44; k++) {
      await tester.pump(const Duration(milliseconds: 250));
      final centre = tester.getCenter(find.descendant(of: orb, matching: find.byType(QamarMoon)).first);
      for (var i = 0; i < LivingOrb.sparkOrbits.length; i++) {
        final spark = find.byKey(LivingOrb.sparkKey(i));
        final dot = tester.getCenter(find.descendant(of: spark, matching: find.byType(Container)).first);
        final offset = dot - centre;
        final clip = find.descendant(of: spark, matching: find.byType(ClipPath)).evaluate().isNotEmpty;
        final far = offset.dy < -0.01;
        if (far) {
          expect(clip, isTrue, reason: 'spark $i behind the moon is clipped to its disc');
          clipped++;
        } else if (offset.dy > 0.01) {
          expect(clip, isFalse, reason: 'spark $i in front is whole');
          open++;
        }
        expect(offset.dx.abs(), lessThanOrEqualTo(LivingOrb.sparkOrbits[i].across * OrbNav.moon + 0.5));
      }
    }
    expect(clipped, greaterThan(0));
    expect(open, greaterThan(0));
  });

  for (final lang in AppLang.values) {
    testWidgets('the receipt sits clear of the sparks’ ring (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.go(AppScreen.today);
      await _pumpOrb(tester, s);
      s.chooseActivity(ActivityKind.walk);
      await s.logActivity(20);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final moon = tester.getRect(find.byKey(OrbNav.orbKey));
      final receipt = tester.getRect(find.byType(SuReceiptChip));
      final reach = LivingOrb.sparkOrbits.map((o) => o.across * OrbNav.moon + o.size / 2).reduce((a, b) => a > b ? a : b);
      final clear = receipt.left >= moon.center.dx ? receipt.left - moon.center.dx : moon.center.dx - receipt.right;
      expect(clear, greaterThanOrEqualTo(reach), reason: 'no spark crosses the number');
      expect(receipt.top, greaterThanOrEqualTo(_area.height - QLayout.orbBand), reason: 'still in the band');
    });
  }
}
