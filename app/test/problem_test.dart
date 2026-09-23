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
import 'package:qamar/models/plan.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/problem.dart';
import 'package:qamar/models/profile.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/services/auth_service.dart';
import 'package:qamar/services/dictation.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/common.dart';
import 'package:qamar/screens/today_screen.dart';
import 'package:qamar/state/today_focus.dart';
import 'package:qamar/widgets/tree_overlay.dart';

import 'support/arabic_digits.dart';

/// A gateway whose answers each test sets.
class _Ai implements AiGateway {
  Object? planFails;
  Completer<DayPlan>? planHangs;
  int planCalls = 0;
  final List<String?> planInstructions = [];
  Object? chatFails;
  ChatResult chatResult = const ChatResult(reply: 'grounded answer');
  AiQuotas quotas = AiQuotas.empty;
  int chatCalls = 0;
  final List<String?> mealTexts = [];

  @override
  Future<DayPlan> generatePlan({required String date, required String lang, bool force = false, String? instruction}) async {
    planCalls++;
    planInstructions.add(instruction);
    if (planHangs != null) return planHangs!.future;
    if (planFails != null) throw planFails!;
    return const DayPlan(date: '2026-09-22', slots: []);
  }

  @override
  Future<ChatResult> chatReply({required String message, required String lang, String? date, Map<String, dynamic>? currentPlan, List<String>? swappedSlots, String? imagePath}) async {
    chatCalls++;
    if (chatFails != null) throw chatFails!;
    return chatResult;
  }

  @override
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? imagePath, String lang = 'ar'}) async {
    mealTexts.add(text);
    return const MealAnalysis([
      ConfirmItemDef(ar: 'كشري', en: 'Koshary', portionAr: 'طبق وسط', portionEn: '1 medium bowl', conf: Confidence.low, kcal: 520, p: 16, c: 96, f: 9),
    ]);
  }

  @override
  Future<AiQuotas> quotaStatus() async => quotas;

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

/// A phone where the microphone is not allowed: the recogniser will not
/// start, and says nothing about why.
class _RefusedMic implements Dictation {
  @override
  bool get available => false;
  @override
  bool get listening => false;
  @override
  Future<bool> prepare({void Function(String status)? onStatus, void Function(String error)? onError}) async => false;
  @override
  Future<bool> start({required String lang, required void Function(String text, bool isFinal) onResult}) async => false;
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

    test('the plan’s daily cap with no plan yet: nothing to change, so back to Today — never a way that cannot work', () async {
      final cap = AiQuotaException(
        'Today’s plan has been rewritten enough. Swap meals on the plan itself, or tell me what changed and I will adjust the rest.',
        const AiQuota(bucket: 'plan', used: 4, limit: 4, extra: 0, remaining: 0),
      );
      final ai = _Ai()..planFails = cap;
      final s = AppState(ai: ai)..setLang(AppLang.en);
      await s.ensurePlan(force: true);
      final p = s.planProblem!;
      expect(p.kind, ProblemKind.limit);
      expect(p.action.label, 'Back to Today', reason: 'Su buys no plan uses, and with no plan there is no meal to swap or change');
      expect(p.what, isNot(contains('tell me what changed')));
      p.action.onTap();
      expect(s.screen, AppScreen.today);
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
          'That was today’s last free question. Qamar+ keeps the conversation going and tells you what to eat tomorrow — or ask again in the morning.',
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

    group('a microphone that is off', () {
      test('on Android: a permission in place of "I am listening", and typing keeps the meal', () async {
        final ai = _Ai();
        final s = AppState(ai: ai, dictation: _RefusedMic())..setLang(AppLang.en);
        s.quickLog(QuickLog.voice);
        await Future<void>.delayed(Duration.zero);
        final p = s.chat.last.problem!;
        _plainProblem(p);
        expect(p.kind, ProblemKind.permission);
        expect(p.what, 'The microphone is off for Qamar.');
        expect(p.why, contains('phone’s Settings'), reason: 'Android cannot be taken there, so the words say where');
        expect(p.action.label, 'Type it instead');
        expect(p.secondary, isNull);
        expect(s.chat.any((t) => t.text.contains('I am listening')), isFalse, reason: 'nothing is left saying Qamar is listening');
        expect(s.chatState, ChatState.idle);
        expect(s.dictationError, isNull, reason: 'said once, as Qamar’s line, not again in the header');

        final asked = s.composerFocus;
        p.action.onTap();
        expect(s.composerFocus, asked + 1, reason: '"Type it instead" takes the keyboard');
        await s.sendChatMsg('koshary with daqqa');
        expect(ai.mealTexts, ['koshary with daqqa'], reason: 'what is typed next is still the meal');
        expect(ai.chatCalls, 0, reason: 'and never spends a question');
      });

      test('on an iPhone, in Arabic: "Open Settings" first, "Type it instead" beside it', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        var opened = 0;
        final s = AppState(
          dictation: _RefusedMic(),
          openSettings: () async {
            opened++;
            return true;
          },
        )..setLang(AppLang.ar);
        s.quickLog(QuickLog.voice);
        await Future<void>.delayed(Duration.zero);
        final p = s.chat.last.problem!;
        expect(p.what, 'المايك مقفول لقمر.');
        expect(p.why, 'افتحه من الإعدادات، أو اكتبها بدل كده.');
        expect(p.action.label, 'افتح الإعدادات');
        expect(p.secondary!.label, 'اكتبها بدل كده');
        expect(s.chat.any((t) => t.text.contains('أنا سامعك')), isFalse);
        p.action.onTap();
        expect(opened, 1);
      });

      test('a question asked by voice: said the same way, and what is typed next is a question', () async {
        final ai = _Ai();
        final s = AppState(ai: ai, dictation: _RefusedMic())..setLang(AppLang.en);
        s.openChat();
        final before = s.chat.length;
        await s.tapOrbListen();
        expect(s.chat.length, before + 1, reason: 'Qamar’s opening line stays; the microphone line follows it');
        expect(s.chat.last.problem!.what, 'The microphone is off for Qamar.');
        await s.sendChatMsg('is feteer ok tonight?');
        expect(ai.chatCalls, 1);
        expect(ai.mealTexts, isEmpty);
      });

      testWidgets('"Type it instead" in the conversation puts the keyboard in the field', (tester) async {
        final s = AppState(dictation: _RefusedMic())..setLang(AppLang.en);
        s.go(AppScreen.today);
        await tester.binding.setSurfaceSize(const Size(900, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
        s.quickLog(QuickLog.voice);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
        final field = find.byType(TextField);
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isFalse);
        await tester.tap(find.text('Type it instead'));
        await tester.pump();
        await tester.pump();
        expect(tester.widget<TextField>(field).focusNode!.hasFocus, isTrue);
      });
    });
  });

  test('an account error the app does not know is said from the person’s side', () async {
    final s = AppState(auth: _Account())..setLang(AppLang.en);
    s.authEmail = 'basel@example.com';
    await s.sendAuthCode();
    _plain(s.authError);
    expect(s.authError, 'Something went wrong on our side. Try again in a moment.');
  });

  for (final lang in AppLang.values) {
    testWidgets('the InBody scan says what it gives before the camera opens (${lang.code})', (tester) async {
      final s = AppState()..setLang(lang);
      s.openScan();
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
      expect(
        find.text(lang == AppLang.ar ? 'صوّر التقرير وأنا هقرا أرقامك.' : 'Photograph the report and I’ll read your numbers.'),
        findsOneWidget,
        reason: 'what a scan gives is said before capture, not only its name on the welcome',
      );
    });
  }

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

  group('words the food data cannot match', () {
    // The gateway's note for this case says a photo needs Qamar+; the free
    // tier has three a day, so the app says its own line instead.
    const gatewayNote = 'I could not match that to a food we know. Try a clearer name. Photographing a plate is Qamar+.';
    for (final lang in AppLang.values) {
      for (final left in [3, 0]) {
        test('offer ${left > 0 ? 'a photo, with no Qamar+' : 'the words that can be matched, the photos used'} (${lang.code})', () async {
          final ai = _NotFoundAi()
            ..quotas = AiQuotas(
              chat: AiQuotas.empty.chat,
              photo: AiQuota(bucket: 'photo', used: 3 - left, limit: 3, extra: 0, remaining: left),
              plan: AiQuotas.empty.plan,
            );
          final s = AppState(ai: ai)..setLang(lang);
          s.openChat();
          await s.logTextAsMeal('fesikh bel tahina');
          final said = s.chat.last.text;
          expect(said, isNot(contains('Qamar+')));
          expect(said, isNot(contains('قمر+')), reason: 'a photo is not Qamar+: the free tier has three a day');
          final isAr = lang == AppLang.ar;
          expect(
            said,
            left > 0
                ? (isAr ? 'مقدرتش ألاقي الأكل ده. جرّب اسم أوضح، أو صوّر الطبق.' : 'I could not match that food. Try a clearer name, or photograph the plate.')
                : (isAr ? 'مقدرتش ألاقي الأكل ده. جرّب اسم أوضح، أو قوللي فيه إيه وقد إيه.' : 'I could not match that food. Try a clearer name, or tell me what’s in it and how much.'),
            reason: left > 0 ? 'photos are left today' : 'no photo is left today, so none is offered',
          );
        });
      }
    }
    test('the gateway’s note is not what is said', () async {
      final s = AppState(ai: _NotFoundAi())..setLang(AppLang.en);
      await s.logTextAsMeal('fesikh');
      expect(s.chat.last.text, isNot(gatewayNote));
    });
  });

  test('in Arabic the Qamar+ button names it قمر+, as the Arabic paywall does', () async {
    final ai = _Ai()
      ..chatFails = AiQuotaException('دي كانت آخر سؤال ببلاش النهارده.', const AiQuota(bucket: 'chat', used: 3, limit: 3, extra: 0, remaining: 0));
    final s = AppState(ai: ai)..setLang(AppLang.ar);
    s.openChat();
    await s.sendChatMsg('أكلت كشري');
    final label = s.chat.last.problem!.action.label;
    expect(label, 'شوف قمر+');
    expect(label, isNot(contains('Qamar')), reason: 'no Latin brand dropped into Arabic');
  });

  test('the Problem kinds are the five the component draws', () {
    expect(ProblemKind.values.map((k) => k.name), ['empty', 'error', 'offline', 'permission', 'limit']);
  });

  group('a daily cap is a limit, and its way on is one that works now', () {
    AiQuotaException planCap() => AiQuotaException(
          'Today’s plan has been rewritten enough. Swap meals on the plan itself, or tell me what changed and I will adjust the rest.',
          const AiQuota(bucket: 'plan', used: 4, limit: 4, extra: 0, remaining: 0),
        );
    PlanMeal meal(String id, String name) =>
        (id: id, slotAr: id, slotEn: id, nameAr: name, nameEn: name, noteAr: '', noteEn: '', portions: const []);
    DayPlan day({required bool alternative}) => DayPlan(date: '2026-09-22', slots: [
          (meal('lunch', 'Koshary'), alternative ? meal('lunch', 'Grilled chicken') : meal('lunch', 'Koshary')),
        ]);
    AppState capped({required int questionsLeft, required bool plan, bool alternative = true}) {
      final chat = AiQuota(bucket: 'chat', used: 3 - questionsLeft, limit: 3, extra: 0, remaining: questionsLeft);
      final ai = _Ai()
        ..planFails = planCap()
        ..quotas = AiQuotas(chat: chat, photo: AiQuota.emptyPhoto, plan: AiQuotas.empty.plan);
      final s = AppState(ai: ai)..setLang(AppLang.en);
      s.aiQuota = chat;
      if (plan) s.plan = day(alternative: alternative);
      return s;
    }

    test('the question and photo limits are limits, not errors', () async {
      final ai = _Ai()
        ..chatFails = AiQuotaException('That was today’s last free question.', const AiQuota(bucket: 'chat', used: 3, limit: 3, extra: 0, remaining: 0));
      final s = AppState(ai: ai)..setLang(AppLang.en);
      await s.sendChatMsg('what should I eat tonight?');
      expect(s.chat.last.problem!.kind, ProblemKind.limit);

      final photos = AppState(ai: _PhotoWallAi())..setLang(AppLang.en);
      photos.logPhotoTaken('/tmp/does-not-matter.jpg');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(photos.chat.last.problem!.kind, ProblemKind.limit);
    });

    test('a question left and a plan to change: "Tell Qamar what changed" — a swap is saved under the question', () async {
      final s = capped(questionsLeft: 2, plan: true);
      await s.ensurePlan(force: true);
      final p = s.planProblem!;
      expect(p.kind, ProblemKind.limit);
      expect(p.action.label, 'Tell Qamar what changed');
      expect(p.secondary!.label, 'Swap a meal on the plan', reason: 'and the way that spends nothing, beside it');
    });

    test('no questions left: never "Tell Qamar", which would open on the question wall; the plan’s own swap instead', () async {
      final s = capped(questionsLeft: 0, plan: true);
      s.go(AppScreen.today);
      s.openChat();
      await s.ensurePlan(force: true);
      final p = s.planProblem!;
      expect(p.kind, ProblemKind.limit);
      expect(p.action.label, 'Swap a meal on the plan');
      expect(p.secondary, isNull);
      expect(p.what, 'Today’s plan has been rewritten enough.', reason: 'the server’s "tell me what changed" is not offered when it cannot work');
      p.action.onTap();
      expect(s.screen, AppScreen.plan);
      expect(s.chatOpen, isFalse);
    });

    test('no questions and nothing to swap: back to Today, and when it comes back', () async {
      for (final plan in [false, true]) {
        final s = capped(questionsLeft: 0, plan: plan, alternative: false);
        s.go(AppScreen.plan);
        await s.ensurePlan(force: true);
        final p = s.planProblem!;
        expect(p.action.label, 'Back to Today', reason: plan ? 'no meal has another option' : 'no plan to change');
        expect(p.why, 'It can be written again from tomorrow.');
        p.action.onTap();
        expect(s.screen, AppScreen.today);
      }
    });

    test('a full rewrite asked for in the conversation that meets the cap is said, not claimed — even with questions left', () async {
      final ai = _Ai()
        ..planFails = planCap()
        ..chatResult = const ChatResult(reply: 'Rewriting your whole day around no cooking.', rebuildInstruction: 'no cooking');
      final s = AppState(ai: ai)..setLang(AppLang.en);
      s.plan = day(alternative: true);
      s.aiQuota = const AiQuota(bucket: 'chat', used: 1, limit: 3, extra: 0, remaining: 2);
      s.openChat();
      await s.sendChatMsg('I’m too tired to cook, redo my day');

      expect(ai.planInstructions, ['no cooking'], reason: 'the rewrite went to the metered plan call');
      final turn = s.chat.last;
      expect(turn.text, 'Today’s plan has been rewritten enough.');
      expect(s.chat.any((t) => t.text.startsWith('Rewriting your whole day')), isFalse, reason: 'the reply spoke as if it would happen');
      expect(turn.action, isNull, reason: 'no "See the plan" on a plan that did not change');
      expect(turn.problem!.kind, ProblemKind.limit);
      expect(turn.problem!.action.label, 'Swap a meal on the plan',
          reason: 'telling Qamar again would ask for the same rewrite and meet the same cap');
    });

    test('trying again after a failed rewrite asks for the same rewrite', () async {
      final ai = _Ai()
        ..planFails = const SocketException('Failed host lookup')
        ..chatResult = const ChatResult(reply: 'Rewriting your day.', rebuildInstruction: 'no cooking');
      final s = AppState(ai: ai)..setLang(AppLang.en);
      s.plan = day(alternative: true);
      await s.sendChatMsg('redo my day');
      final turn = s.chat.last;
      expect(turn.problem!.action.label, 'Try again');
      ai.planFails = null;
      turn.problem!.action.onTap();
      await Future<void>.delayed(Duration.zero);
      expect(ai.planInstructions, ['no cooking', 'no cooking']);
    });
  });

  group('a fasting switch whose rewrite does not happen says so above the plan it left', () {
    // Today's plan is on screen, written today, and a rewrite is refused.
    PlanMeal lunch(String ar, String en) =>
        (id: 'lunch', slotAr: 'الغدا', slotEn: 'Lunch', nameAr: ar, nameEn: en, noteAr: '', noteEn: '', portions: const []);
    AppState written(AppLang lang, {required Object refusal, int questionsLeft = 2, bool alternative = true, _Ai? gateway, DateTime? now}) {
      final chat = AiQuota(bucket: 'chat', used: 3 - questionsLeft, limit: 3, extra: 0, remaining: questionsLeft);
      final ai = (gateway ?? _Ai())
        ..planFails = refusal
        ..quotas = AiQuotas(chat: chat, photo: AiQuota.emptyPhoto, plan: AiQuotas.empty.plan);
      final s = AppState(ai: ai, clock: now == null ? null : () => now)..setLang(lang);
      s.aiQuota = chat;
      final koshary = lunch('كشري', 'Koshary');
      s.plan = DayPlan(date: '2026-09-22', slots: [(koshary, alternative ? lunch('فراخ مشوية', 'Grilled chicken') : koshary)]);
      s.planDate = DateTime.now().toIso8601String().substring(0, 10);
      return s;
    }

    AiQuotaException planCap() => AiQuotaException(
          'Today’s plan has been rewritten enough. Swap meals on the plan itself, or tell me what changed and I will adjust the rest.',
          const AiQuota(bucket: 'plan', used: 4, limit: 4, extra: 0, remaining: 0),
        );

    for (final lang in [AppLang.en, AppLang.ar]) {
      testWidgets('the plan’s cap: a limit card above the meals says the plan is not the fasting plan yet (${lang.code})', (tester) async {
        final isAr = lang == AppLang.ar;
        final s = written(lang, refusal: planCap());
        s.go(AppScreen.plan);
        await tester.binding.setSurfaceSize(const Size(900, 2400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
        await tester.pump();
        expect(find.byType(QStateCard), findsNothing, reason: 'nothing to say before the switch');

        await s.setFasting(true);
        await tester.pump();

        final notYet = isAr ? 'خطة النهارده لسه مش خطة الصيام.' : 'Today’s plan isn’t your fasting plan yet.';
        final card = find.byType(QStateCard);
        expect(card, findsOneWidget, reason: 'the refusal is drawn, not only kept in state');
        expect(find.descendant(of: card, matching: find.text(notYet)), findsOneWidget);
        expect(
          find.descendant(
            of: card,
            matching: find.text(isAr
                ? 'اتكتبت كفاية النهارده، فمتكتبتش تاني. قمر لسه يقدر يغيّر وجباتها في المحادثة.'
                : 'It has been rewritten enough today, so it wasn’t written again. Qamar can still change its meals in the conversation.'),
          ),
          findsOneWidget,
        );
        final meal = find.text(isAr ? 'كشري' : 'Koshary');
        expect(meal, findsOneWidget, reason: 'the plan from before stays on screen');
        expect(tester.getBottomLeft(card).dy, lessThan(tester.getTopLeft(meal).dy), reason: 'above the meal list');
        expect(Directionality.of(tester.element(find.text(notYet))), isAr ? TextDirection.rtl : TextDirection.ltr);

        final p = s.planProblem!;
        expect(p.kind, ProblemKind.limit);
        expect(p.action.label, isAr ? 'قول لقمر إيه اللي اتغيّر' : 'Tell Qamar what changed',
            reason: 'a question left: the conversation changes meals without the plan call');
        expect(p.secondary!.label, isAr ? 'بدّل وجبة من الخطة' : 'Swap a meal on the plan');
        expect(find.descendant(of: card, matching: find.widgetWithText(QPrimaryButton, p.action.label)), findsOneWidget);
        if (isAr) expectNoLatinDigits(tester, within: card, where: 'the fasting card');

        await tester.tap(find.descendant(of: card, matching: find.widgetWithText(QPrimaryButton, p.action.label)));
        await tester.pump();
        expect(s.chatOpen, isTrue);
      });
    }

    test('no questions left: the plan’s own swap, which on the Plan screen makes way for the meals', () async {
      final s = written(AppLang.en, refusal: planCap(), questionsLeft: 0);
      s.go(AppScreen.plan);
      await s.setFasting(true);
      final p = s.planProblem!;
      expect(p.what, 'Today’s plan isn’t your fasting plan yet.');
      expect(p.kind, ProblemKind.limit);
      expect(p.action.label, 'Swap a meal on the plan');
      expect(p.secondary, isNull);
      expect(p.why, 'It has been rewritten enough today, so it wasn’t written again. '
          'A meal with another option can be swapped on the plan itself, and that spends nothing.');
      p.action.onTap();
      expect(s.screen, AppScreen.plan);
      expect(s.planProblem, isNull, reason: 'already on the plan, the button is not a dead one');
      expect(s.hasPlan, isTrue);
    });

    test('nothing that works now: back to Today, and when it can be written again', () async {
      final s = written(AppLang.ar, refusal: planCap(), questionsLeft: 0, alternative: false);
      s.go(AppScreen.plan);
      await s.setFasting(true);
      final p = s.planProblem!;
      expect(p.what, 'خطة النهارده لسه مش خطة الصيام.');
      expect(p.why, 'اتكتبت كفاية النهارده، فمتكتبتش تاني. تقدر تتكتب تاني من بكرة.');
      expect(p.action.label, 'ارجع للنهارده');
    });

    test('turning it off says the plan is still the fasting one', () async {
      final s = written(AppLang.en, refusal: planCap(), questionsLeft: 0);
      s.profile = s.profile.copyWith(fasting: FastingMode.ramadan);
      await s.setFasting(false);
      expect(s.planProblem!.what, 'Today’s plan is still your fasting plan.');
    });

    test('offline: said the same way, with the refusal as its reason and "Try again" writing the fasting plan', () async {
      final ai = _Ai();
      final s = written(AppLang.en, refusal: const SocketException('Failed host lookup'), gateway: ai);
      await s.setFasting(true);
      final p = s.planProblem!;
      expect(p.what, 'Today’s plan isn’t your fasting plan yet.');
      expect(p.why, 'You’re offline right now. The plan is written for you on our server, so it needs a connection.');
      expect(p.kind, ProblemKind.offline);
      expect(p.action.label, 'Try again');
      ai.planFails = null;
      p.action.onTap();
      await Future<void>.delayed(Duration.zero);
      expect(ai.planCalls, 2);
      expect(s.planProblem, isNull);
    });

    // Where the answer is given: the season's question in Today's slot, and
    // the switch on the Ramadan screen. Four days before the first fast of
    // 1448, so the question is due.
    final inSeason = DateTime(2027, 2, 4, 9);
    Future<void> show(WidgetTester tester, AppState s) async {
      await tester.binding.setSurfaceSize(const Size(900, 2400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
      await tester.pump();
    }

    for (final lang in [AppLang.en, AppLang.ar]) {
      final isAr = lang == AppLang.ar;
      final notYet = isAr ? 'خطة النهارده لسه مش خطة الصيام.' : 'Today’s plan isn’t your fasting plan yet.';

      testWidgets('Today: "Yes, fasting" refused leaves one line in the slot, with the Plan card’s way on (${lang.code})', (tester) async {
        final s = written(lang, refusal: planCap(), now: inSeason)..dismissOrbTutorial();
        s.go(AppScreen.today);
        await show(tester, s);
        final slot = find.byKey(TodayScreen.cardKey(TodayCard.fasting));
        expect(slot, findsOneWidget, reason: 'the season’s question is in the slot');

        await tester.tap(find.text(isAr ? 'أيوة، صايم' : 'Yes, fasting'));
        await tester.pump();
        await tester.pump();

        expect(todayFocus(s), TodayCard.fasting, reason: 'the answer keeps the slot while the plan has not caught up');
        final line = find.descendant(of: slot, matching: find.byType(QStateLine));
        expect(line, findsOneWidget, reason: 'the answer’s outcome is said where it was given');
        expect(find.descendant(of: line, matching: find.text(notYet)), findsOneWidget);
        expect(find.textContaining(isAr ? 'هتصوم؟' : 'Fasting?'), findsNothing, reason: 'the question is answered');
        expect(find.byType(QStateCard), findsNothing, reason: 'a line in the slot, not a second card');
        final way = find.descendant(of: line, matching: find.text(isAr ? 'قول لقمر إيه اللي اتغيّر' : 'Tell Qamar what changed'));
        expect(way, findsOneWidget, reason: 'the Plan card’s own way on: a question is left');
        expect(tester.getSize(find.ancestor(of: way, matching: find.byType(TextButton))).height, greaterThanOrEqualTo(48));
        expect(Directionality.of(tester.element(find.text(notYet))), isAr ? TextDirection.rtl : TextDirection.ltr);
        if (isAr) expectNoLatinDigits(tester, within: line, where: 'the fasting line');

        await tester.tap(way);
        await tester.pump();
        expect(s.chatOpen, isTrue);
      });

      testWidgets('Ramadan: the switch refused says so under it, with the Plan card’s way on (${lang.code})', (tester) async {
        final s = written(lang, refusal: planCap(), questionsLeft: 0, now: inSeason);
        s.go(AppScreen.ramadan);
        await show(tester, s);
        expect(find.byType(QStateLine), findsNothing, reason: 'nothing to say before the switch');

        await tester.tap(find.byType(Switch));
        await tester.pump();
        await tester.pump();

        final line = find.byType(QStateLine);
        expect(line, findsOneWidget);
        expect(find.descendant(of: line, matching: find.text(notYet)), findsOneWidget);
        expect(tester.getTopLeft(line).dy, greaterThan(tester.getBottomLeft(find.byType(Switch)).dy), reason: 'under the switch that asked');
        expect(Directionality.of(tester.element(find.text(notYet))), isAr ? TextDirection.rtl : TextDirection.ltr);
        if (isAr) expectNoLatinDigits(tester, within: line, where: 'the fasting line');

        // No question left: the plan's own swap, which leads to the plan and
        // its card.
        final way = find.descendant(of: line, matching: find.text(isAr ? 'بدّل وجبة من الخطة' : 'Swap a meal on the plan'));
        expect(way, findsOneWidget);
        await tester.tap(way);
        await tester.pump();
        expect(s.screen, AppScreen.plan);
        await tester.pump();
        expect(find.descendant(of: find.byType(QStateCard), matching: find.text(notYet)), findsOneWidget, reason: 'the full card, with its reason');
      });
    }

    test('where nothing works today, the line says when, with no button that only leads back', () async {
      final s = written(AppLang.en, refusal: planCap(), questionsLeft: 0, alternative: false, now: inSeason);
      s.go(AppScreen.ramadan);
      await s.setFasting(true);
      final n = s.fastingNotYet!;
      expect(n.line, 'Today’s plan isn’t your fasting plan yet. It can be written again from tomorrow.');
      expect(n.action, isNull, reason: '"Back to Today" is a way out, not a way on');
      expect(s.planProblem!.action.label, 'Back to Today', reason: 'the Plan card keeps it');
    });

    test('taking the answer back after a refusal: the plan on screen already fits, so nothing is rewritten and nothing said', () async {
      final ai = _Ai();
      final s = written(AppLang.en, refusal: planCap(), gateway: ai, now: inSeason);
      await s.setFasting(true);
      expect(s.fastingNotYet, isNotNull);
      await s.setFasting(false);
      expect(ai.planCalls, 1, reason: 'the plan shown was written without the fast');
      expect(s.fastingNotYet, isNull);
      expect(s.planProblem, isNull);
      expect(todayCardDue(s, TodayCard.fasting), isFalse, reason: 'the slot is free again');
    });

    test('trying again that fails again still says what it left undone; a plan written clears it everywhere', () async {
      final ai = _Ai();
      final s = written(AppLang.en, refusal: const SocketException('Failed host lookup'), gateway: ai, now: inSeason);
      await s.setFasting(true);
      s.planProblem!.action.onTap();
      await Future<void>.delayed(Duration.zero);
      expect(ai.planCalls, 2);
      expect(s.planProblem!.what, 'Today’s plan isn’t your fasting plan yet.');
      expect(s.fastingNotYet!.action!.label, 'Try again');
      ai.planFails = null;
      s.fastingNotYet!.action!.onTap();
      await Future<void>.delayed(Duration.zero);
      expect(s.planProblem, isNull);
      expect(s.fastingNotYet, isNull);
    });
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

/// A reading that finds nothing, with the gateway's note for that case.
class _NotFoundAi extends _Ai {
  @override
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? imagePath, String lang = 'ar'}) async =>
      const MealAnalysis([], note: 'I could not match that to a food we know. Try a clearer name. Photographing a plate is Qamar+.');
}

class _PhotoWallAi extends _Ai {
  @override
  Future<MealAnalysis> analyzeMeal({required String inputType, String? text, String? imagePath, String lang = 'ar'}) async =>
      throw AiQuotaException(
        'That’s today’s three photos. Type or say the meal for free, or spend Su Points on another photo from the wallet.',
        const AiQuota(bucket: 'photo', used: 3, limit: 3, extra: 0, remaining: 0),
      );
}
