// What iso()'s isolate holds and what it does not (seat 2's own note on
// iso(), from its review of seat 6's 799db1c): several Arabic-Indic numbers
// in one isolate still take the bidi rules for Arabic numbers. The macros
// rely on it: "consumed / target" reads consumed first in Arabic.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/state/app_state.dart';

import 'support/app_fonts.dart';

/// Where the caret before [a] and before [b] fall, left to right, in [text]
/// laid out in an Arabic line.
({double a, double b}) _xs(String text, String a, String b) {
  final tp = TextPainter(text: TextSpan(text: text, style: const TextStyle(fontSize: 20)), textDirection: TextDirection.rtl)..layout();
  double x(int i) => tp.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dx;
  return (a: x(text.indexOf(a)), b: x(text.lastIndexOf(b)));
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  group('the rules iso() documents', () {
    final s = AppState()..setLang(AppLang.ar);

    test('numbers joined by " / " or "-" read right to left, the first on the right', () {
      final macro = _xs('${s.iso('34 / 148')} جم', '٣٤', '١٤٨');
      expect(macro.a, greaterThan(macro.b), reason: 'consumed on the right: read first in Arabic');
      final date = _xs(s.iso('2026-08-13'), '٢٠٢٦', '١٣');
      expect(date.a, greaterThan(date.b), reason: 'which is why a date needs marks of its own');
    });

    test('numbers joined by a lone "/" or "." read left to right', () {
      final step = _xs(s.iso('1/9'), '١', '٩');
      expect(step.a, lessThan(step.b));
      final version = _xs(s.iso('2.0'), '٢', '٠');
      expect(version.a, lessThan(version.b));
    });

    test('with Western digits the numbers are a Latin run, left to right', () {
      final w = AppState()..setLang(AppLang.ar);
      w.setEasternDigits(false);
      final macro = _xs('${w.iso('34 / 148')} جم', '34', '148');
      expect(macro.a, lessThan(macro.b));
    });
  });

  // The macros on Today say consumed, then target, in each reading order.
  for (final eastern in [true, false]) {
    testWidgets('Today’s macros read consumed first in Arabic, ${eastern ? 'Arabic-Indic' : 'Western'} digits', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 1600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = AppState()..setLang(AppLang.ar);
      s.setEasternDigits(eastern);
      s.profile = s.profile.copyWith(name: 'Basel');
      s.dismissOrbTutorial();
      s.meals.add(LoggedMeal(name: 'Koshary', sub: '', kcal: 640, p: 20, c: 100, f: 18, at: DateTime.now()));
      s.go(AppScreen.today);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();

      final target = s.target().protein;
      final text = '${s.iso('20 / $target')} جم';
      // Found by what it says, whatever direction marks it may carry.
      final row = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().replaceAll('\u200E', '') == text);
      expect(row, findsOneWidget);
      final paragraph = tester.renderObject<RenderParagraph>(row);
      final plain = paragraph.text.toPlainText();
      double x(int i) => paragraph.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dx;
      final consumed = x(plain.indexOf(s.digits('20')));
      final goal = x(plain.lastIndexOf(s.digits('$target')));
      if (eastern) {
        expect(consumed, greaterThan(goal), reason: 'right to left: the consumed number on the right, read first');
      } else {
        expect(consumed, lessThan(goal), reason: 'a Latin run, left to right: the consumed number on the left, read first');
      }
    });
  }
}
