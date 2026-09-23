// The Why sheet's calculation version, seat 6's part (found on the sheet's
// renders in Arabic): "calc v2.0 · 2026-08-13" in Arabic digits drew as
// "calc v١٣-٠٨-٢٠٢٦ · ٢.٠", the version and the date swapped and the date
// backwards. It reads in its own order in both languages now.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/why_sheet.dart';

import 'support/app_fonts.dart';

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  for (final lang in AppLang.values) {
    testWidgets('the version reads calc, v, the version, the date, left to right (${lang.name})', (tester) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(390, 844) * 3;
      addTearDown(tester.view.reset);
      final s = AppState()..setLang(lang);
      s.dismissOrbTutorial();
      s.go(AppScreen.today);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      s.openWhy();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      final ar = lang == AppLang.ar;
      String bare(String t) => t.replaceAll(RegExp('[\u200E\u2066-\u2069]'), '');
      final version = find.descendant(of: find.byType(WhySheet), matching: find.byWidgetPredicate((w) => w is RichText && bare(w.text.toPlainText()).startsWith('calc')));
      expect(version, findsOneWidget);
      final p = tester.renderObject<RenderParagraph>(version);
      final text = p.text.toPlainText();
      double at(int i) {
        expect(i, isNonNegative, reason: 'in "$text"');
        return p.getOffsetForCaret(TextPosition(offset: i), Rect.zero).dx;
      }

      final iv = text.indexOf('v');
      final iVersion = text.indexOf(RegExp(ar ? '[٠-٩]' : '[0-9]'), iv);
      final year = ar ? '٢٠٢٦' : '2026', day = ar ? '١٣' : '13';
      final v = at(iv), ver = at(iVersion), y = at(text.indexOf(year)), d = at(text.lastIndexOf(day));
      expect(at(text.indexOf('calc')), lessThan(v));
      expect(v, lessThan(ver), reason: 'the version follows the v');
      expect(ver, lessThan(y), reason: 'then the date');
      expect(y, lessThan(d), reason: 'the year before the day, the date in its own order');
    });
  }
}
