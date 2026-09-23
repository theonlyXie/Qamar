// The welcome and the paywall as compositions, seat 6's part (the scorecard's
// 01 and 10): the welcome hangs from one centre line, its two ways back in
// read alike as links, its fine print ends on no orphan word; on the paywall
// the lockup is centred and balanced and the rest reads from the start, one
// plan has no radio, and "included" is one mark in one colour in both
// columns.
//
// The welcome in mono-glass: the moon sitting on the name, the promise, then
// the one white button ("Chat with Qamar") and the report as an outline under
// it, the width of the page; no sign-up block (the three providers and
// "Continue with email" are in the account sheet that "Sign in" opens,
// Google's mark in colour), the guest line, the way back in and the
// invitation side by side, and one order top to bottom. The buttons are
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
import 'package:qamar/models/invitation.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/theme/text_styles.dart';
import 'package:qamar/widgets/account_sheet.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/moon.dart';

import 'persistence_test.dart' show FakeInvitationRepo;
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

/// What the welcome can say under "Have an invitation?", seat 1's scenarios,
/// each reached the way the app reaches it: nothing; a link opened before
/// there is an account (good news: it waits); a link opened with an account
/// and no signal, whose code is kept on the phone (the longest notice); a
/// redeemed invitation, from a friend who is named and from one who is not
/// (good news either way); and a refusal after a success, which is not good
/// news although the friend is still named.
enum _Notice {
  none(good: false),
  waiting(good: true),
  kept(good: false),
  invited(good: true),
  unnamed(good: true),
  refusedAfter(good: false);

  const _Notice({required this.good});

  /// Drawn in the first ink when true, in the second when not.
  final bool good;

  Future<AppState> make(AppLang lang) async {
    switch (this) {
      case _Notice.none:
        return AppState()..setLang(lang);
      case _Notice.waiting:
        final s = AppState()..setLang(lang);
        await s.acceptInvitationLink('QMR-LATER');
        return s;
      case _Notice.kept:
        final s = AppState(invitationRepo: FakeInvitationRepo()..failWith = StateError('no signal'), userId: 'user-1')..setLang(lang);
        await s.acceptInvitationLink('QMR-LIVE');
        return s;
      case _Notice.invited:
        final s = AppState(invitationRepo: FakeInvitationRepo(), userId: 'user-1')..setLang(lang);
        await s.redeemInvitation('QMR-7F3A1');
        return s;
      case _Notice.unnamed:
        final repo = FakeInvitationRepo()..redemption = const InvitationRedemption(inviterName: '', inviteeName: 'Omar', trialDays: 14);
        final s = AppState(invitationRepo: repo, userId: 'user-1')..setLang(lang);
        await s.redeemInvitation('QMR-7F3A1');
        return s;
      case _Notice.refusedAfter:
        final repo = FakeInvitationRepo();
        final s = AppState(invitationRepo: repo, userId: 'user-1')..setLang(lang);
        await s.redeemInvitation('QMR-7F3A1');
        repo.failWith = const InvitationException('this account already used an invitation', refused: true);
        await s.redeemInvitation('QMR-9Z9Z9');
        return s;
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
    testWidgets('the welcome hangs from one centre line: one white button, its links alike, its fine print whole (${lang.name})', (tester) async {
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

      // One thing to do, in white; the report is the second way in, drawn
      // by its edge.
      final primaries = find.descendant(of: find.byType(WelcomeScreen), matching: find.byType(QPrimaryButton));
      expect(primaries, findsOneWidget, reason: 'one white button on the screen');
      expect(tester.widget<QPrimaryButton>(primaries).label, s.t.chatDirect);
      expect(find.descendant(of: find.byKey(WelcomeScreen.scanPillKey), matching: find.text(s.t.scanInbody)), findsOneWidget);
      expect(tester.widget(find.byKey(WelcomeScreen.scanPillKey)), isA<QOutlineButton>());

      final haveAccount = tester.widget<Text>(find.text(s.t.haveAccount));
      final invitation = tester.widget<Text>(find.text(WelcomeScreen.invitationLabel(lang == AppLang.ar)));
      expect(haveAccount.style!.color, QColors.inkSecondary, reason: 'a quiet action: the second ink, never a hue');
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
      testWidgets('the moon sits on the name with air round it, and the ways in are under the promise, the width of the page (${lang.name}, ${phone.width.toInt()}x${phone.height.toInt()})', (tester) async {
        tester.view.devicePixelRatio = 3;
        tester.view.physicalSize = phone * 3;
        addTearDown(tester.view.reset);
        final s = AppState()..setLang(lang);
        await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(tester.takeException(), isNull);
        final chat = tester.getRect(find.byKey(WelcomeScreen.chatPillKey));
        final scan = tester.getRect(find.byKey(WelcomeScreen.scanPillKey));
        final name = tester.getRect(find.text(s.t.brand));
        final promise = tester.getRect(find.text(s.t.promise));
        final moon = find.descendant(of: find.byKey(WelcomeScreen.moonKey), matching: find.byType(QamarMoon));
        if (phone.height >= 800) expect(moon, findsOneWidget, reason: 'a phone this tall has room for the moon');
        if (moon.evaluate().isNotEmpty) {
          final disc = tester.getRect(moon.first);
          expect(disc.height, greaterThanOrEqualTo(WelcomeScreen.moonMin - 4), reason: 'a moon worth the name');
          expect(name.top - disc.bottom, greaterThanOrEqualTo(12), reason: 'the moon sits on the name, not on top of it');
        }
        expect(chat.top - promise.bottom, greaterThanOrEqualTo(24), reason: 'room between the promise and the ways in');
        expect(scan.top, greaterThanOrEqualTo(chat.bottom), reason: 'the two ways in never overlap');
        for (final r in [chat, scan]) {
          expect(r.left, moreOrLessEquals(20, epsilon: 0.5), reason: 'the page’s margin, in either language');
          expect(r.right, moreOrLessEquals(phone.width - 20, epsilon: 0.5));
        }
      });
    }

    testWidgets('the welcome in its order, its buttons whole, its notice and fine print on screen, at four sizes (${lang.name})', (tester) async {
      final invitation = WelcomeScreen.invitationLabel(lang == AppLang.ar);
      final failures = <String>[];
      for (final (phone, top, bottom) in _welcomePhones) {
        for (final notice in _Notice.values) {
          final at = '${phone.width.toInt()}x${phone.height.toInt()} (${top.toInt()}/${bottom.toInt()}), ${notice.name}';
          tester.view.devicePixelRatio = 3;
          tester.view.physicalSize = phone * 3;
          tester.view.padding = FakeViewPadding(top: top * 3, bottom: bottom * 3);
          final s = await notice.make(lang);
          await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          expect(tester.takeException(), isNull, reason: 'nothing overflows at $at');

          // Never scaled: the buttons are their own height at every size.
          final chat = tester.getRect(find.byKey(WelcomeScreen.chatPillKey));
          final scan = tester.getRect(find.byKey(WelcomeScreen.scanPillKey));
          if (chat.height != 52 || scan.height != 48) failures.add('$at: buttons ${chat.height} and ${scan.height}');

          final moon = find.descendant(of: find.byKey(WelcomeScreen.moonKey), matching: find.byType(QamarMoon));
          final disc = moon.evaluate().isEmpty ? null : tester.getRect(moon.first);
          final wantsMoon = phone.height >= 800;
          if (wantsMoon && disc == null) failures.add('$at: no moon');
          if (disc != null && disc.height < WelcomeScreen.moonMin - 4) failures.add('$at: a moon of ${disc.height}');

          // The way back in and the invitation share a line, side by side.
          final account = tester.getRect(find.text(s.t.haveAccount));
          final invite = tester.getRect(find.text(invitation));
          if ((account.center.dy - invite.center.dy).abs() > 1) failures.add('$at: the links are not on one line');
          if (account.overlaps(invite)) failures.add('$at: the links overlap');
          final links = account.expandToInclude(invite);

          // Top to bottom, each clear of the next.
          final order = <(String, Rect)>[
            ('language', tester.getRect(find.byType(QLangToggle))),
            if (disc != null) ('moon', disc),
            ('name', tester.getRect(find.text(s.t.brand))),
            ('promise', tester.getRect(find.text(s.t.promise))),
            ('chat', chat),
            ('scan', scan),
            ('guest line', tester.getRect(find.byKey(WelcomeScreen.guestNoteKey))),
            ('links', links),
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
          await tester.pumpWidget(const SizedBox());
        }
      }
      tester.view.reset();
      expect(failures, isEmpty, reason: failures.join('\n'));
    });

    testWidgets('the notice is drawn in its own ink: good news in the first, the inviter named or not; anything that did not happen in the second (${lang.name})', (tester) async {
      final ar = lang == AppLang.ar;
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = _phone * 3;
      tester.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
      addTearDown(tester.view.reset);
      final says = {
        _Notice.waiting: ar ? 'وصلتك دعوة.' : 'You have an invitation.',
        _Notice.kept: ar ? 'محفوظة على الموبايل' : 'kept on this phone',
        _Notice.invited: ar ? 'Basel عزمك.' : 'Basel invited you.',
        _Notice.unnamed: ar ? 'صاحبك عزمك.' : 'A friend invited you.',
        _Notice.refusedAfter: 'this account already used an invitation',
      };
      for (final notice in _Notice.values.where((n) => n != _Notice.none)) {
        final s = await notice.make(lang);
        await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        final text = tester.widget<Text>(find.byKey(WelcomeScreen.noticeKey));
        expect(text.data, contains(says[notice]!), reason: '${notice.name}: the notice the app says');
        if (notice == _Notice.refusedAfter) expect(s.invitedBy, 'Basel', reason: 'still invited by Basel, and the tone is not');
        if (notice == _Notice.unnamed) expect(s.invitedBy, isNull, reason: 'no name, and still good news');
        expect(text.style!.color, notice.good ? QColors.ink : QColors.inkSecondary, reason: '${notice.name} ${notice.good ? 'is good news' : 'did not happen'}');
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('where even a moonless welcome is taller than the phone, it scrolls, and nothing is scaled (${lang.name})', (tester) async {
      // A phone on its side: the buttons stay whole and the fine print is a
      // scroll away, where the hero used to be scaled down as a picture.
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(740, 360) * 3;
      addTearDown(tester.view.reset);
      final s = await _Notice.kept.make(lang);
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(tester.getRect(find.byKey(WelcomeScreen.chatPillKey)).height, 52);
      expect(tester.getRect(find.byKey(WelcomeScreen.scanPillKey)).height, 48);
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
      expect(checks, {QColors.inkSecondary}, reason: 'included is one ink in both columns');
    });
  }
}
