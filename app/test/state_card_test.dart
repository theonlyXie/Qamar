// The state card's design (O10), seat 6's part. Seat 2 wrote what each
// problem says and wired it (problem_test.dart); here, without changing its
// API: each kind has its own glyph (and a daily limit is not drawn as a
// failure); the card sits in the middle of the free space, not stuck to its
// top; its way on is a whole touch; its "what happened" line is always
// whole. And the conversation is drawn from the bottom up, like the
// consultation, its suggestions fading at the end of their row.

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/messages.dart';
import 'package:qamar/models/problem.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/widgets/ask_qamar_overlay.dart';
import 'package:qamar/widgets/common.dart';

import 'support/app_fonts.dart';

const _phone = Size(390, 844);

class _Ai implements AiGateway {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

Future<void> _pumpApp(WidgetTester tester, AppState s) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = _phone * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Problem _problem(ProblemKind kind) => Problem(
      what: 'Something happened that has to be said in full, however long the sentence runs on a phone.',
      why: 'Why, when it is known.',
      action: ProblemAction('Try again', () {}),
      secondary: ProblemAction('Another way', () {}),
      kind: kind,
    );

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  group('the card', () {
    test('each kind has its own glyph, one ink for all of them, and a daily limit is not drawn as a failure', () {
      final looks = {for (final k in ProblemKind.values) k: QStateCard.look(k)};
      expect(looks.values.map((l) => l.icon).toSet().length, ProblemKind.values.length, reason: 'five kinds, five glyphs');
      expect(looks.values.map((l) => l.tint).toSet(), {QColors.ink}, reason: 'the glyph says which, never a colour');
      expect(looks[ProblemKind.limit]!.icon, isNot(looks[ProblemKind.error]!.icon), reason: 'a limit is an hourglass, not a warning');
    });

    for (final kind in ProblemKind.values) {
      testWidgets('${kind.name}: its glyph, the whole "what", a whole touch for each way on', (tester) async {
        await tester.binding.setSurfaceSize(_phone);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(MaterialApp(home: Scaffold(body: Padding(padding: const EdgeInsets.all(20), child: QStateCard(problem: _problem(kind))))));
        expect(find.byKey(ValueKey('state-glyph-${kind.name}')), findsOneWidget);
        final what = tester.renderObject<RenderParagraph>(find.textContaining('Something happened'));
        expect(what.didExceedMaxLines, isFalse, reason: 'what happened is always whole');
        expect(tester.getSize(find.byType(QPrimaryButton)).height, greaterThanOrEqualTo(48));
        expect(tester.getSize(find.byType(QOutlineButton)).height, greaterThanOrEqualTo(48));
      });
    }
  });

  group('in the free space', () {
    for (final lang in AppLang.values) {
      testWidgets('on Plan with no plan, the card is in the middle of the space under the header (${lang.name})', (tester) async {
        final s = AppState(ai: _Ai())..setLang(lang);
        s.dismissOrbTutorial();
        s.go(AppScreen.today);
        s.go(AppScreen.plan);
        await _pumpApp(tester, s);
        final card = tester.getRect(find.byType(QStateCard));
        // The header is the title's row, the back button in it; the space
        // ends at the "Day changed?" row under it.
        final header = tester.getRect(find.ancestor(of: find.byType(QBackButton), matching: find.byType(Row)).first);
        final dayRow = tester.getRect(find.ancestor(of: find.text(s.t.dayChanged), matching: find.byType(Row)).first);
        final spaceTop = header.bottom;
        final spaceBottom = dayRow.top;
        final at = (card.center.dy - spaceTop) / (spaceBottom - spaceTop);
        expect(at, inInclusiveRange(0.33, 0.5), reason: 'at the optical centre of the free space, not stuck under the header ($at)');
        expect(card.top - header.bottom, greaterThan(40));
      });
    }

    testWidgets('on the scan, the card takes the viewfinder’s middle and nothing is drawn under it', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.openScan();
      s.setScanProblem(s.cameraProblem(PlatformException(code: 'camera_access_denied'), instead: ProblemAction('Type it instead', () {})));
      await _pumpApp(tester, s);
      expect(find.byType(QStateCard), findsOneWidget);
      expect(find.text(s.t.scanInbodySub), findsNothing, reason: 'the placeholder is not left under the card');
      expect(find.byKey(const ValueKey('state-glyph-permission')), findsOneWidget);
    });
  });

  group('the conversation', () {
    for (final lang in AppLang.values) {
      testWidgets('is drawn from the bottom up: a fresh line sits on the field, the space above is sky (${lang.name})', (tester) async {
        final s = AppState(ai: _Ai())..setLang(lang);
        s.dismissOrbTutorial();
        s.go(AppScreen.today);
        s.aiQuota = const AiQuota(bucket: 'chat', used: 1, limit: 20, extra: 0, remaining: 19);
        s.chat.add(const ChatTurn(who: ChatWho.q, text: 'Evening. You are 480 kcal under today.'));
        s.chatOpen = true;
        await _pumpApp(tester, s);
        final list = tester.widget<ListView>(find.byKey(AskQamarOverlay.transcriptKey));
        expect(list.reverse, isTrue);
        final line = tester.getRect(find.text('Evening. You are 480 kcal under today.'));
        final field = tester.getRect(find.byType(TextField));
        expect(field.top - line.bottom, lessThan(140), reason: 'on the field (with the suggestions between), not at the top of an empty screen');
        expect(line.top, greaterThan(_phone.height / 2));
      });
    }

    testWidgets('a new message pins to the newest, but someone reading back is left where they are', (tester) async {
      final s = AppState(ai: _Ai())..setLang(AppLang.en);
      s.dismissOrbTutorial();
      s.go(AppScreen.today);
      for (var i = 0; i < 30; i++) {
        s.chat.add(ChatTurn(who: i.isEven ? ChatWho.u : ChatWho.q, text: 'Line $i of a long conversation about lunch.'));
      }
      s.chatOpen = true;
      await _pumpApp(tester, s);
      final scroll = tester.state<ScrollableState>(find.descendant(of: find.byKey(AskQamarOverlay.transcriptKey), matching: find.byType(Scrollable))).position;
      expect(scroll.pixels, 0, reason: 'opens on the newest');

      scroll.jumpTo(600); // reading back
      s.chat.add(const ChatTurn(who: ChatWho.q, text: 'A new line.'));
      s.onChatDraftChanged('a'); // anything that rebuilds
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(scroll.pixels, greaterThanOrEqualTo(500), reason: 'never yanked away from what they are reading');

      scroll.jumpTo(60); // near the newest
      s.chat.add(const ChatTurn(who: ChatWho.q, text: 'Another new line.'));
      s.onChatDraftChanged('ab');
      await tester.pump();
      await tester.pump(); // the animation's first frame starts its clock
      await tester.pump(const Duration(milliseconds: 400));
      expect(scroll.pixels, 0, reason: 'back to the newest');
    });

    for (final lang in AppLang.values) {
      testWidgets('the suggestions fade at the end of their row, the end the row runs on to (${lang.name})', (tester) async {
        final s = AppState(ai: _Ai())..setLang(lang);
        s.dismissOrbTutorial();
        s.go(AppScreen.today);
        s.aiQuota = const AiQuota(bucket: 'chat', used: 1, limit: 20, extra: 0, remaining: 19);
        s.chat.add(const ChatTurn(who: ChatWho.q, text: 'Evening.'));
        s.chatOpen = true;
        await _pumpApp(tester, s);
        final mask = tester.widget<ShaderMask>(find.byKey(AskQamarOverlay.suggestionFadeKey));
        expect(mask.blendMode, BlendMode.dstIn);
        final shader = mask.shaderCallback(const Rect.fromLTWH(0, 0, 360, 48));
        expect(shader, isNotNull);
        // The end: the right in English, the left in Arabic.
        expect(find.byKey(AskQamarOverlay.suggestionFadeKey), findsOneWidget);
        expect(Directionality.of(tester.element(find.byKey(AskQamarOverlay.suggestionFadeKey))), lang == AppLang.ar ? TextDirection.rtl : TextDirection.ltr);
      });
    }
  });
}
