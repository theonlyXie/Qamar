// The welcome and the paywall as compositions, seat 6's part (the scorecard's
// 01 and 10): the welcome hangs from one centre line, its two ways back in
// read alike as links, its fine print ends on no orphan word; on the paywall
// the lockup is centred and balanced and the rest reads from the start, one
// plan has no radio, and "included" is one mark in one colour in both
// columns. And the welcome's two ways in sit above and below the moon, never
// over it, on a tall phone and a short one.
//
// The welcome is seat 1's content in seat 6's layout: no sign-up block (the
// three providers and "Continue with email" are in the account sheet that
// "I already have an account" opens, Google's mark in colour), the guest
// line in the divider's place, and one order top to bottom. The pills are
// never scaled, the moon gives way first, and the invitation, its notice and
// the fine print stay on screen, at 360x640, 375x667, 360x800 and 390x844,
// in both languages and with each of the invitation's notices.

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
import 'package:qamar/widgets/moon.dart';

import 'support/app_fonts.dart';

const _phone = Size(390, 844);

/// The four phones, with no insets and with their own: 360x640 and 360x800
/// under an Android status bar (and 360x800 over a button bar), 375x667
/// under an iPhone SE's, 390x844 under an iPhone's notch and over its home
/// indicator.
const _welcomePhones = [
  (Size(360, 640), 0.0, 0.0),
  (Size(360, 640), 24.0, 0.0),
  (Size(375, 667), 0.0, 0.0),
  (Size(375, 667), 20.0, 0.0),
  (Size(360, 800), 0.0, 0.0),
  (Size(360, 800), 24.0, 48.0),
  (Size(390, 844), 47.0, 34.0),
];

/// What the welcome can say under "Have an invitation?", seat 1's scenarios:
/// nothing; a link opened before there is an account; a code kept on the
/// phone because the server could not be reached, the longest; and a
/// redeemed invitation, which names the friend.
enum _Notice {
  none,
  guest,
  kept,
  invited;

  Future<void> show(AppState s) async {
    final ar = s.isAr;
    switch (this) {
      case _Notice.none:
        return;
      case _Notice.guest:
        await s.acceptInvitationLink('QMR-LATER');
      case _Notice.kept:
        s.invitationNotice = ar
            ? 'مقدرتش أفعّل الدعوة دلوقتي. هي محفوظة على الموبايل، وهجرّب تاني أول ما تفتح التطبيق وانت متوصل.'
            : 'I could not redeem your invitation just now. It is kept on this phone, and I will try again the next time you open the app with a connection.';
      case _Notice.invited:
        s.invitedBy = 'Basel';
        s.invitationNotice = ar ? 'Basel عزمك. ١٤ يوم قمر+ عليك من دلوقتي.' : 'Basel invited you. 14 days of Qamar+ are yours from now.';
    }
  }
}

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

      // No sign-up block before the first question: no providers, no email.
      expect(find.byType(ProviderRow), findsNothing);
      expect(find.byType(GoogleMark), findsNothing);
      expect(find.text(lang == AppLang.ar ? 'كمّل بالإيميل' : 'Continue with email'), findsNothing);
      expect(find.text(s.t.guestNote), findsOneWidget, reason: 'the guest line says none is needed');

      // The one way back in opens the account sheet to sign in, and the
      // sheet carries all four ways.
      await tester.tap(find.text(s.t.haveAccount));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(s.authOpen, isTrue);
      expect(s.authLinking, isFalse, reason: 'signing in, not linking');
      final sheet = find.byType(AccountSheet);
      expect(sheet, findsOneWidget);
      expect(find.descendant(of: sheet, matching: find.byType(GoogleMark)), findsOneWidget, reason: 'Google’s own mark');
      expect(find.descendant(of: sheet, matching: find.byIcon(Icons.g_mobiledata)), findsNothing, reason: 'not the mobile-data glyph');
      for (final way in const ['Google', 'Apple', 'Facebook']) {
        expect(find.descendant(of: sheet, matching: find.text(way)), findsOneWidget, reason: way);
      }
      expect(find.descendant(of: sheet, matching: find.byType(TextField)), findsOneWidget, reason: 'and email');
    });

    for (final phone in const [Size(390, 844), Size(360, 800), Size(375, 667), Size(360, 640)]) {
      testWidgets('the welcome’s ways in never sit on the moon, with room around them (${lang.name}, ${phone.width.toInt()}x${phone.height.toInt()})', (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = phone * 3;
        addTearDown(tester.view.reset);
        final s = AppState()..setLang(lang);
        await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.takeException(), isNull);
        final chat = tester.getRect(find.byKey(WelcomeScreen.chatPillKey));
        final scan = tester.getRect(find.byKey(WelcomeScreen.scanPillKey));
        final moon = find.descendant(of: find.byKey(WelcomeScreen.moonKey), matching: find.byType(QamarMoon));
        if (phone.height >= 800) expect(moon, findsOneWidget, reason: 'a phone this tall has room for the moon');
        if (moon.evaluate().isNotEmpty) {
          final disc = tester.getRect(moon.first);
          expect(chat.bottom, lessThanOrEqualTo(disc.top), reason: 'Chat with Qamar above the moon, not over it');
          expect(scan.top, greaterThanOrEqualTo(disc.bottom), reason: 'the scan below it');
          expect(disc.height, greaterThanOrEqualTo(64));
        }
        expect(chat.bottom, lessThanOrEqualTo(scan.top), reason: 'the two ways in never overlap');
        final name = tester.getRect(find.text(s.t.brand));
        expect(name.top - scan.bottom, greaterThanOrEqualTo(18), reason: 'room between the hero and the name');
        for (final r in [chat, scan]) {
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(phone.width));
        }
        // The first way in hangs from the start edge, the second from the end.
        if (lang == AppLang.ar) {
          expect(chat.right, greaterThan(scan.right - 1), reason: 'mirrored in Arabic');
        } else {
          expect(chat.left, lessThan(scan.left + 1));
        }
      });
    }

    testWidgets('the welcome in seat 1’s order, its pills whole, its notice and fine print on screen, at four sizes (${lang.name})', (tester) async {
      final invitation = lang == AppLang.ar ? 'عندك دعوة؟' : 'Have an invitation?';
      final failures = <String>[];
      for (final (phone, top, bottom) in _welcomePhones) {
        for (final notice in _Notice.values) {
          final at = '${phone.width.toInt()}x${phone.height.toInt()} (${top.toInt()}/${bottom.toInt()}), ${notice.name}';
          tester.view.devicePixelRatio = 3;
          tester.view.physicalSize = phone * 3;
          tester.view.padding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
          final s = AppState()..setLang(lang);
          await notice.show(s);
          await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull, reason: 'nothing overflows at $at');

          // Never scaled: the pills are their own height at every size.
          final chat = tester.getRect(find.byKey(WelcomeScreen.chatPillKey));
          final scan = tester.getRect(find.byKey(WelcomeScreen.scanPillKey));
          if (chat.height != 60 || scan.height != 52) failures.add('$at: pills ${chat.height} and ${scan.height}');

          final moon = find.descendant(of: find.byKey(WelcomeScreen.moonKey), matching: find.byType(QamarMoon));
          final disc = moon.evaluate().isEmpty ? null : tester.getRect(moon.first);
          final wantsMoon = phone.height >= 800;
          if (wantsMoon && (disc == null || disc.height < 64)) failures.add('$at: moon ${disc?.height}');
          if (disc != null && disc.height < 64) failures.add('$at: a moon of ${disc.height}, under 64');

          // Top to bottom, each clear of the next.
          final order = <(String, Rect)>[
            ('language', tester.getRect(find.byType(QLangToggle))),
            ('chat', chat),
            if (disc != null) ('moon', disc),
            ('scan', scan),
            ('name', tester.getRect(find.text(s.t.brand))),
            ('promise', tester.getRect(find.text(s.t.promise))),
            ('guest line', tester.getRect(find.byKey(WelcomeScreen.guestNoteKey))),
            ('account', tester.getRect(find.text(s.t.haveAccount))),
            ('invitation', tester.getRect(find.text(invitation))),
            if (notice != _Notice.none) ('notice', tester.getRect(find.byKey(WelcomeScreen.noticeKey))),
            ('fine print', tester.getRect(find.byKey(WelcomeScreen.boundaryKey))),
          ];
          for (var i = 1; i < order.length; i++) {
            if (order[i].$2.top < order[i - 1].$2.bottom - 0.5) failures.add('$at: ${order[i].$1} over ${order[i - 1].$1}');
          }
          // On screen, with nothing to scroll to: the page fits.
          final screen = Rect.fromLTRB(0, top, phone.width, phone.height - bottom);
          for (final (what, r) in order) {
            if (r.top < screen.top - 0.5 || r.bottom > screen.bottom + 0.5) failures.add('$at: $what off screen, $r');
          }
          final page = tester.state<ScrollableState>(find.descendant(of: find.byType(WelcomeScreen), matching: find.byType(Scrollable)).first);
          if (page.position.maxScrollExtent > 0) failures.add('$at: scrolls ${page.position.maxScrollExtent}');
          if (notice == _Notice.invited) {
            expect(tester.widget<Text>(find.byKey(WelcomeScreen.noticeKey)).style!.color, QColors.cyan, reason: 'a redeemed invitation is good news');
          }
          await tester.pumpWidget(const SizedBox());
        }
      }
      tester.view.reset();
      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    testWidgets('where even a moonless welcome is taller than the phone, it scrolls, and nothing is scaled (${lang.name})', (tester) async {
      // A phone on its side: the pills stay whole and the fine print is a
      // scroll away, where the hero used to be scaled down as a picture.
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(740, 360) * 3;
      addTearDown(tester.view.reset);
      final s = AppState()..setLang(lang);
      await _Notice.kept.show(s);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(WelcomeScreen.chatPillKey)).height, 60);
      expect(tester.getRect(find.byKey(WelcomeScreen.scanPillKey)).height, 52);
      expect(find.byType(FittedBox), findsNothing, reason: 'nothing on the welcome is drawn smaller than its size');
      final page = find.descendant(of: find.byType(WelcomeScreen), matching: find.byType(Scrollable)).first;
      expect(tester.state<ScrollableState>(page).position.maxScrollExtent, greaterThan(0));
      await tester.drag(page, const Offset(0, -2000));
      await tester.pump();
      expect(tester.getRect(find.byKey(WelcomeScreen.boundaryKey)).bottom, lessThanOrEqualTo(360), reason: 'the fine print is reached');
      expect(tester.getRect(find.byKey(WelcomeScreen.noticeKey)).top, greaterThan(tester.getRect(find.text(s.t.haveAccount)).bottom));
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
