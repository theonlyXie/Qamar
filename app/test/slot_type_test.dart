// Seat 1's gestures card and seat 2's fasting question, as set on Today,
// seat 6's part: their words and their 120 points are theirs
// (today_layout_test holds the budget); here, how the words fall. No line
// of either card ends a paragraph on one word alone. On renders the English
// "Tap it — opens the tree" left "tree" by itself on a third line (the
// cells were shared by letter count with a floor of 30, too little for a
// short English cell and right for the Arabic; the floor is now measured),
// and the Arabic fasting line ended on "للكل." under "ببلاش" (a no-break
// space keeps the closing sentence whole). Both languages.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/screens/today_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/state/today_focus.dart';

import 'support/app_fonts.dart';

final _now = DateTime(2027, 2, 5, 9); // the season's lead week

/// The words on [p]'s last line.
List<String> _lastLine(RenderParagraph p) {
  final painter = TextPainter(text: p.text, textDirection: p.textDirection, textScaler: p.textScaler)
    ..setPlaceholderDimensions(p.text.toPlainText(includeSemanticsLabels: false).contains('￼')
        ? const [PlaceholderDimensions(size: Size(17, 13), alignment: PlaceholderAlignment.middle)]
        : const [])
    ..layout(maxWidth: p.size.width);
  final text = p.text.toPlainText(includeSemanticsLabels: false);
  final lines = painter.computeLineMetrics();
  if (lines.length < 2) return const ['(one line)', ''];
  final range = painter.getLineBoundary(TextPosition(offset: text.length - 1));
  return text.substring(range.start, range.end).replaceAll('￼', '').trim().split(RegExp(r'[  ]+')).where((w) => w.isNotEmpty).toList();
}

Future<AppState> _today(WidgetTester tester, AppLang lang, TodayCard card) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390, 844) * 3;
  tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  final s = AppState(clock: () => _now)..setLang(lang);
  s.profile = s.profile.copyWith(name: 'Basel');
  if (card != TodayCard.fasting) s.setFasting(false);
  if (card != TodayCard.tutorial) s.dismissOrbTutorial();
  s.go(AppScreen.today);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  expect(todayFocus(s), card);
  return s;
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  for (final lang in AppLang.values) {
    for (final card in const [TodayCard.tutorial, TodayCard.fasting]) {
      testWidgets('${card.name}: no paragraph ends on one word alone (${lang.name})', (tester) async {
        await _today(tester, lang, card);
        final slot = find.byKey(TodayScreen.cardKey(card));
        expect(slot, findsOneWidget);
        var wrapped = 0;
        for (final e in find.descendant(of: slot, matching: find.byType(RichText)).evaluate()) {
          final p = e.renderObject! as RenderParagraph;
          if (p.text.toPlainText().trim().isEmpty) continue;
          final last = _lastLine(p);
          if (last.first == '(one line)') continue;
          wrapped++;
          expect(last.length, greaterThanOrEqualTo(2), reason: '"${p.text.toPlainText()}" ends on "${last.join(' ')}" alone');
        }
        // A card whose every line fits has no orphan to find; the gestures
        // card always wraps, so its check is never empty.
        if (card == TodayCard.tutorial) expect(wrapped, greaterThan(0), reason: 'the card has wrapped words to check');
      });
    }
  }
}
