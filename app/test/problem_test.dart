// Errors and empty states, the content (O10): every problem says what
// happened, why when it is known, and the next step from where the person
// is — as a real button — and never shows a raw exception.

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/problem.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/services/auth_service.dart';
import 'package:qamar/services/dictation.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/widgets/tree_overlay.dart';

/// A gateway whose answers each test sets.
class _Ai implements AiGateway {
  Object? planFails;
  Completer<DayPlan>? planHangs;
  int planCalls = 0;
  Object? chatFails;
  int chatCalls = 0;
  final List<String?> mealTexts = [];

  @override
  Future<DayPlan> generatePlan({required String date, required String lang, bool force = false, String? instruction}) async {
    planCalls++;
    if (planHangs != null) return planHangs!.future;
    if (planFails != null) throw planFails!;
    return const DayPlan(date: '2026-09-22', slots: []);
  }

  @override
  Future<ChatResult> chatReply({required String message, required String lang, String? date, Map<String, dynamic>? currentPlan, List<String>? swappedSlots, String? imagePath}) async {
    chatCalls++;
    if (chatFails != null) throw chatFails!;
    return const ChatResult(reply: 'grounded answer');
  }

  @override
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? imagePath, String lang = 'ar'}) async {
    mealTexts.add(text);
    return const MealAnalysis([
      ConfirmItemDef(ar: 'كشري', en: 'Koshary', portionAr: 'طبق وسط', portionEn: '1 medium bowl', conf: Confidence.low, kcal: 520, p: 16, c: 96, f: 9),
    ]);
  }

  @override
  Future<AiQuotas> quotaStatus() async => AiQuotas.empty;

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

class _Dictation implements Dictation {
  void Function(String error)? failWith;
  @override
  bool get available => true;
  @override
  bool get listening => false;
  @override
  Future<bool> prepare({void Function(String status)? onStatus, void Function(String error)? onError}) async {
    failWith = onError;
    return true;
  }

  @override
  Future<bool> start({required String lang, required void Function(String text, bool isFinal) onResult}) async => true;
  @override
  Future<void> stop() async {}
  @override
  Future<void> cancel() async {}
}

class _Account implements Account {
  Object fails = Exception('AuthRetryableFetchException(message: something_new, statusCode: 500)');
  @override
  Future<void> startLink(String email) async => throw fails;
  @override
  Future<void> startSignIn(String email) async => throw fails;
  @override
  Stream<void> get changes => const Stream.empty();
  @override
  String? get email => null;
  @override
  bool get isAnonymous => true;
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

/// Nothing a person reads carries an exception's name or its raw text.
void _plain(String? s) {
  if (s == null) return;
  expect(s, isNot(matches(RegExp(r'Exception|Error|errno|statusCode|SocketException|Platform'))), reason: s);
}

void _plainProblem(Problem? p) {
  expect(p, isNotNull);
  _plain(p!.what);
  _plain(p.why);
}

void main() {
  setUpAll(() {
    // The app's quick-invoke channels, which have no platform side in tests.
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  group('the plan', () {
    test('offline: says so, why, and "Try again" asks again', () async {
      final ai = _Ai()..planFails = const SocketException('Failed host lookup: qamar.supabase.co');
      final s = AppState(ai: ai)..setLang(AppLang.en);
      await s.ensurePlan(force: true);
      final p = s.planProblem!;
      _plainProblem(p);
      expect(p.kind, ProblemKind.offline);
      expect(p.what, 'You’re offline right now.');
      expect(p.why, contains('needs a connection'));
      expect(p.action.label, 'Try again');

      ai.planFails = null;
      p.action.onTap();
      await Future<void>.delayed(Duration.zero);
      expect(ai.planCalls, 2, reason: 'the button asks again');
      expect(s.planProblem, isNull);
    });

    testWidgets('too slow: after a minute it stops waiting and says so', (tester) async {
      final ai = _Ai()..planHangs = Completer<DayPlan>();
      final s = AppState(ai: ai)..setLang(AppLang.ar);
      unawaited(s.ensurePlan(force: true));
      await tester.pump(const Duration(seconds: 1));
      expect(s.planLoading, isTrue);
      await tester.pump(AppState.planTimeout);
      expect(s.planLoading, isFalse, reason: 'never "Writing…" for ever');
      _plainProblem(s.planProblem);
      expect(s.planProblem!.what, 'النت بطيء دلوقتي.');
      expect(s.planProblem!.action.label, 'جرّب تاني');
    });

    test('no target yet: "Finish the questions" opens them', () async {
      final ai = _Ai()..planFails = AiGatewayException('generatePlan failed: 409 {"error":"no target"}');
      final s = AppState(ai: ai)..setLang(AppLang.en);
      s.go(AppScreen.plan);
      await s.ensurePlan(force: true);
      _plainProblem(s.planProblem);
      expect(s.planError, contains('target'));
      expect(s.planProblem!.action.label, 'Finish the questions');
      s.planProblem!.action.onTap();
      expect(s.screen, AppScreen.onboard);
    });

    test('the plan’s daily cap names the way the server names: tell Qamar what changed', () async {
      final cap = AiQuotaException(
        'Today’s plan has been rewritten enough. Swap meals on the plan itself, or tell me what changed and I will adjust the rest.',
        const AiQuota(bucket: 'plan', used: 4, limit: 4, extra: 0, remaining: 0),
      );
      final ai = _Ai()..planFails = cap;
      final s = AppState(ai: ai)..setLang(AppLang.en);
      await s.ensurePlan(force: true);
      final p = s.planProblem!;
      expect(p.what, cap.message);
      expect(p.action.label, 'Tell Qamar what changed', reason: 'Su buys no plan uses, so the wallet is not the way out');
      p.action.onTap();
      expect(s.chatOpen, isTrue);
    });

    test('something on our side: said without blame, with "Try again"', () async {
      final ai = _Ai()..planFails = AiGatewayException('generatePlan failed: 500 {"error":"boom"}');
      final s = AppState(ai: ai)..setLang(AppLang.ar);
      await s.ensurePlan(force: true);
      _plainProblem(s.planProblem);
      expect(s.planProblem!.what, 'حصلت مشكلة عندنا.');
      expect(s.planProblem!.why, 'مش منك. جرّب تاني بعد شوية.');
      expect(s.planProblem!.action.label, 'جرّب تاني');
    });

    testWidgets('the Plan screen shows the problem as a card whose button is the next step', (tester) async {
      final ai = _Ai()..planFails = const SocketException('Connection refused');
      final s = AppState(ai: ai)..setLang(AppLang.en);
      s.go(AppScreen.plan);
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(QStateCard), findsOneWidget);
      expect(find.text('You’re offline right now.'), findsOneWidget);
      expect(find.text('Build today’s plan'), findsNothing, reason: 'the card’s button replaces it while the error shows');
      final button = find.widgetWithText(QPrimaryButton, 'Try again');
      expect(button, findsOneWidget);
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      ai.planFails = null;
      await tester.tap(button);
      await tester.pump();
      expect(ai.planCalls, 2);
    });
  });

  group('the camera', () {
    final refused = PlatformException(code: 'camera_access_denied', message: 'The user did not allow camera access.');

    test('refused, on Android: a permission, and "Type it instead" keeps the meal being logged', () {
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      s.toggleTree();
      s.cameraFailedInTree(refused);
      final p = s.treeProblem!;
      _plainProblem(p);
      expect(p.kind, ProblemKind.permission);
      expect(p.what, 'The camera is off for Qamar.');
      expect(p.why, contains('phone’s Settings'), reason: 'Android cannot be taken there, so the words say where');
      expect(p.action.label, 'Type it instead');
      expect(p.secondary, isNull);

      p.action.onTap();
      expect(s.chatOpen, isTrue);
      expect(s.chat.last.text, 'Tell me what you ate.', reason: 'the conversation opens on the meal question, armed');
      expect(s.treeOpen, isFalse);
    });

    test('refused, on an iPhone: "Open Settings" first, "Type it instead" beside it', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      var opened = 0;
      final s = AppState(openSettings: () async {
        opened++;
        return true;
      })
        ..setLang(AppLang.ar);
      final p = s.cameraProblem(refused, instead: ProblemAction('اكتبها بدل كده', () {}));
      expect(p.what, 'الكاميرا مقفولة لقمر.');
      expect(p.action.label, 'افتح الإعدادات');
      expect(p.secondary!.label, 'اكتبها بدل كده');
      p.action.onTap();
      expect(opened, 1);
    });

    test('a camera that is missing is an error, not a permission, and still has a way on', () {
      final s = AppState()..setLang(AppLang.en);
      final p = s.cameraProblem(PlatformException(code: 'no_available_camera'), instead: ProblemAction('Type it instead', () {}));
      _plainProblem(p);
      expect(p.kind, ProblemKind.error);
      expect(p.what, 'The camera didn’t open.');
      expect(p.action.label, 'Type it instead');
    });

    testWidgets('the tree shows it in place of the ring, and closing clears it', (tester) async {
      final s = AppState()..setLang(AppLang.en);
      s.go(AppScreen.today);
      s.toggleTree();
      s.cameraFailedInTree(refused);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: s,
        child: const MaterialApp(home: Scaffold(body: Stack(children: [TreeOverlay()]))),
      ));
      expect(find.byType(QStateCard), findsOneWidget);
      expect(find.text('The camera is off for Qamar.'), findsOneWidget);
      s.closeTree();
      expect(s.treeProblem, isNull);
    });

    test('in the conversation: Qamar says so, with a photo from the phone as the way on', () {
      final s = AppState()..setLang(AppLang.en);
      s.openChat();
      var chose = 0;
      s.cameraFailedInChat(refused, instead: ProblemAction('Choose a photo instead', () => chose++));
      final turn = s.chat.last;
      expect(turn.text, 'The camera is off for Qamar.');
      expect(turn.problem!.action.label, 'Choose a photo instead');
      turn.problem!.action.onTap();
      expect(chose, 1);
    });
  });

  group('the conversation', () {
    test('words that hit the question limit can be logged as a meal, which spends no question', () async {
      final ai = _Ai()
        ..chatFails = AiQuotaException(
          'That was today’s third question. Qamar+ opens the questions and tomorrow’s plan — or come back in the morning.',
          const AiQuota(bucket: 'chat', used: 3, limit: 3, extra: 0, remaining: 0),
        );
      final s = AppState(ai: ai)..setLang(AppLang.en);
      s.openChat();
      await s.sendChatMsg('I had koshary for lunch');
      final wall = s.chat.last;
      expect(wall.openPlus, isTrue, reason: 'the fourth question still opens the Qamar+ wall first');
      expect(wall.problem!.action.label, 'See Qamar+');
      expect(wall.problem!.secondary!.label, 'Log it as a meal');

      wall.problem!.secondary!.onTap();
      await Future<void>.delayed(Duration.zero);
      expect(ai.mealTexts, ['I had koshary for lunch']);
      expect(ai.chatCalls, 1, reason: 'no second question was asked');
      expect(s.proposal, isNotNull, reason: 'the meal is up for confirming');
    });

    test('a failure keeps the words: "Try again" puts them back in the box, and no raw error is shown', () async {
      final ai = _Ai()..chatFails = const SocketException('Failed host lookup: qamar.supabase.co');
      final s = AppState(ai: ai)..setLang(AppLang.en);
      s.openChat();
      await s.sendChatMsg('can I have feteer tonight?');
      final turn = s.chat.last;
      _plain(turn.text);
      _plain(turn.sub);
      expect(turn.sub, 'You’re offline right now.');
      turn.problem!.action.onTap();
      expect(s.chatDraft, 'can I have feteer tonight?');
    });

    test('dictation failing is said plainly, not as the recogniser’s error code', () async {
      final d = _Dictation();
      final s = AppState(dictation: d)..setLang(AppLang.en);
      s.openChat();
      await s.tapOrbListen();
      d.failWith!('error_network');
      _plain(s.dictationError);
      expect(s.dictationError, isNot(contains('error_network')));
      expect(s.dictationError, 'I couldn’t hear that — try again, or type it.');
    });
  });

  test('an account error the app does not know is said from the person’s side', () async {
    final s = AppState(auth: _Account())..setLang(AppLang.en);
    s.authEmail = 'basel@example.com';
    await s.sendAuthCode();
    _plain(s.authError);
    expect(s.authError, 'Something went wrong on our side. Try again in a moment.');
  });

  testWidgets('the InBody scan: a camera that will not open says so plainly, with typing the numbers as the way on', (tester) async {
    // In tests the image picker has no plugin behind it, which is exactly a
    // camera that will not open.
    final s = AppState()..setLang(AppLang.en);
    s.openScan();
    await tester.binding.setSurfaceSize(const Size(900, 2400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.photo_camera));
    // The platform call fails on its own clock, outside the test's.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();

    expect(find.byType(QStateCard), findsOneWidget);
    expect(find.text('The camera didn’t open.'), findsOneWidget);
    expect(find.textContaining('Exception'), findsNothing, reason: 'the exception’s type used to be printed in brackets');
    await tester.tap(find.widgetWithText(QPrimaryButton, 'Type your numbers instead'));
    await tester.pump();
    expect(s.screen, AppScreen.onboard);
  });

  test('in Arabic the Qamar+ button isolates the Latin brand, so its plus stays on its side', () async {
    final ai = _Ai()
      ..chatFails = AiQuotaException('دي كانت تالت سؤال النهارده.', const AiQuota(bucket: 'chat', used: 3, limit: 3, extra: 0, remaining: 0));
    final s = AppState(ai: ai)..setLang(AppLang.ar);
    s.openChat();
    await s.sendChatMsg('أكلت كشري');
    expect(s.chat.last.problem!.action.label, 'شوف \u2066Qamar+\u2069');
  });

  test('the Problem kinds are the four the component draws', () {
    expect(ProblemKind.values.map((k) => k.name), ['empty', 'error', 'offline', 'permission']);
  });

  test('a meal photo past the day’s photos offers typing it instead', () async {
    final s = AppState(ai: _PhotoWallAi())..setLang(AppLang.en);
    s.openChat();
    s.logPhotoTaken('/tmp/does-not-matter.jpg');
    await Future<void>.delayed(const Duration(milliseconds: 10));
    final wall = s.chat.last;
    expect(wall.openWallet, isTrue);
    expect(wall.problem!.secondary!.label, 'Type it instead');
  });
}

class _PhotoWallAi extends _Ai {
  @override
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? imagePath, String lang = 'ar'}) async =>
      throw AiQuotaException(
        'That’s today’s three photos. Type or say the meal for free, or spend Su Points on another photo from the wallet.',
        const AiQuota(bucket: 'photo', used: 3, limit: 3, extra: 0, remaining: 0),
      );
}
