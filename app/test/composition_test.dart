// The welcome and the paywall as compositions, seat 6's part (the scorecard's
// 01 and 10): the welcome hangs from one centre line, its two ways back in
// read alike as links, its fine print ends on no orphan word, and Google's
// mark is Google's, in colour; on the paywall the lockup is centred and
// balanced and the rest reads from the start, one plan has no radio, and
// "included" is one mark in one colour in both columns.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/screens/subscription_screen.dart';
import 'package:qamar/screens/welcome_screen.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/theme/text_styles.dart';
import 'package:qamar/widgets/account_sheet.dart';
import 'package:qamar/widgets/common.dart';

import 'support/app_fonts.dart';

const _phone = Size(390, 844);

Future<void> _pumpApp(WidgetTester tester, AppState s) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390, 1800) * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

/// The widths of [paragraph]'s lines.
List<double> _lines(RenderParagraph paragraph) {
  final painter = TextPainter(text: paragraph.text, textDirection: paragraph.textDirection, textScaler: paragraph.textScaler)
    ..layout(maxWidth: paragraph.size.width);
  return painter.computeLineMetrics().map((l) => l.width).toList();
}

void _expectNoOrphan(RenderParagraph p, String what) {
  final lines = _lines(p);
  if (lines.length < 2) return;
  final widest = lines.reduce((a, b) => a > b ? a : b);
  expect(lines.last, greaterThan(widest * 0.5), reason: '$what ends on a short last line: $lines');
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  testWidgets('balanced text keeps its lines and ends on no orphan', (tester) async {
    const sentence = 'AI-powered general wellness guidance. Not a medical service.';
    final style = QText.body(size: 11, height: 17);
    // At this width a plain Text leaves "service." alone on its line.
    const width = 300.0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: Column(children: [
              Text(sentence, key: const ValueKey('plain'), textAlign: TextAlign.center, style: style),
              QBalancedText(sentence, textKey: const ValueKey('balanced'), style: style),
            ]),
          ),
        ),
      ),
    ));
    final plain = _lines(tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('plain'))));
    final balanced = _lines(tester.renderObject<RenderParagraph>(find.byKey(const ValueKey('balanced'))));
    expect(plain.length, 2);
    expect(plain.last, lessThan(plain.first * 0.5), reason: 'the orphan this is about: $plain');
    expect(balanced.length, plain.length, reason: 'no extra line');
    expect(balanced.last, greaterThan(balanced.first * 0.6), reason: 'even lines: $balanced');
  });

  for (final lang in AppLang.values) {
    testWidgets('the welcome hangs from one centre line, its links alike, its fine print whole (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      await _pumpApp(tester, s);
      expect(find.byType(WelcomeScreen), findsOneWidget);
      final mid = _phone.width / 2;
      for (final text in [s.t.brand, s.t.promise]) {
        final r = tester.getRect(find.text(text));
        expect(r.center.dx, moreOrLessEquals(mid, epsilon: 1), reason: '"$text" on the centre line');
        final p = tester.renderObject<RenderParagraph>(find.text(text));
        expect(p.textAlign, TextAlign.center);
      }
      _expectNoOrphan(tester.renderObject<RenderParagraph>(find.byKey(WelcomeScreen.boundaryKey)), 'the fine print');

      final haveAccount = tester.widget<Text>(find.text(s.t.haveAccount));
      final invitation = tester.widget<Text>(find.text(lang == AppLang.ar ? 'عندك دعوة؟' : 'Have an invitation?'));
      expect(haveAccount.style!.color, QColors.violetSoft, reason: 'a link looks like one');
      expect(invitation.style!.color, haveAccount.style!.color);
      expect(invitation.style!.fontSize, haveAccount.style!.fontSize);

      expect(find.byType(GoogleMark), findsOneWidget, reason: 'Google’s own mark');
      expect(find.byIcon(Icons.g_mobiledata), findsNothing, reason: 'not the mobile-data glyph');
    });

    testWidgets('the paywall: a centred, balanced lockup; the rest from the start; one plan, no radio; one mark for included (${lang.name})', (tester) async {
      final s = AppState()..setLang(lang);
      s.go(AppScreen.today);
      s.go(AppScreen.subscription);
      await _pumpApp(tester, s);
      expect(find.byType(SubscriptionScreen), findsOneWidget);

      final lead = tester.renderObject<RenderParagraph>(find.byKey(SubscriptionScreen.leadKey));
      expect(lead.textAlign, TextAlign.center);
      _expectNoOrphan(lead, 'the lead');
      expect(tester.getRect(find.byKey(SubscriptionScreen.leadKey)).center.dx, moreOrLessEquals(_phone.width / 2, epsilon: 1));
      final without = tester.widget<Text>(find.byKey(SubscriptionScreen.withoutKey));
      expect(without.textAlign ?? TextAlign.start, TextAlign.start, reason: 'three lines of reading are not centred');

      expect(find.byIcon(Icons.radio_button_checked), findsNothing, reason: 'one plan is not a choice');
      expect(find.byIcon(Icons.radio_button_unchecked), findsNothing);

      final checks = tester.widgetList<Icon>(find.byIcon(Icons.check)).map((i) => i.color).toSet();
      expect(checks, {QColors.violetSoft}, reason: 'included is one colour in both columns');
    });
  }
}
