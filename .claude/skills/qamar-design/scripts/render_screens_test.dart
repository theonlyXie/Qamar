// qamar-design render harness for Qamar: draws every screen, in English and
// Arabic, at phone size, to PNG files you can look at.
//
// This is a temporary test file and is never committed. To use it:
//
//   cp .claude/skills/qamar-design/scripts/render_screens_test.dart app/test/zz_render_tmp_test.dart
//   cd app && flutter test test/zz_render_tmp_test.dart \
//       --dart-define=OUT=/abs/path/for/pngs --dart-define=SHOT=after [--dart-define=ONLY=today]
//   rm -f test/zz_render_tmp_test.dart
//
// OUT is where the PNGs go (default /tmp/qamar-design-renders). SHOT names a
// sub-folder, so you can compare `before` with `after`. ONLY keeps just the
// scenes whose name contains that text.
//
// Fonts: the suite's own loader (test/support/app_fonts.dart) — the bundled
// Space Grotesk, Noto Sans Arabic and Inter, and the Iconsax glyphs from the
// iconsax_plus package. Glyphs render as boxes if the package is missing
// (run `flutter pub get`).
//
// Add a scene for any screen or sheet you change. The pattern is: build an
// AppState, put it where the screen is, then call _shoot.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/activity.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/models/messages.dart';
import 'package:qamar/models/problem.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/explain.dart';

import 'support/app_fonts.dart';

const _tag = String.fromEnvironment('SHOT', defaultValue: 'after');
const _only = String.fromEnvironment('ONLY', defaultValue: '');
const _out = String.fromEnvironment('OUT', defaultValue: '/tmp/qamar-design-renders');

class _Ai implements AiGateway {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

/// Draws the app with [state] on a 390 × [height] phone (iPhone 14 insets),
/// runs [after] once it has settled, and writes `<OUT>/<SHOT>/<name>.png`.
Future<void> _shoot(WidgetTester t, AppState state, String name, {double height = 844, void Function(AppState s)? after, Duration settle = const Duration(milliseconds: 900)}) async {
  t.view.physicalSize = Size(390 * 2, height * 2);
  t.view.devicePixelRatio = 2.0;
  t.view.padding = const FakeViewPadding(top: 47 * 2, bottom: 34 * 2);
  addTearDown(t.view.reset);
  final key = GlobalKey();
  await t.pumpWidget(RepaintBoundary(key: key, child: ChangeNotifierProvider.value(value: state, child: const QamarApp())));
  await t.pump();
  await t.pump(const Duration(milliseconds: 900));
  if (after != null) {
    after(state);
    await t.pump();
    await t.pump(settle);
  }
  final problem = t.takeException();
  if (problem != null) stderr.writeln('EXCEPTION in $name: $problem');
  await t.runAsync(() async {
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 2);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$_tag/$name.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void _scene(String name, Future<void> Function(WidgetTester t) body) {
  if (_only.isNotEmpty && !name.contains(_only)) return;
  testWidgets(name, body);
}

AppState _fresh(AppLang lang) => AppState(ai: _Ai())..setLang(lang);

/// A person past onboarding, on Today; with two meals when [logged].
AppState _today(AppLang lang, {bool logged = false, bool tutorial = false}) {
  final s = _fresh(lang);
  s.profile = s.profile.copyWith(name: 'Basel');
  if (!tutorial) s.dismissOrbTutorial();
  if (logged) {
    final ar = lang == AppLang.ar;
    s.meals.add(LoggedMeal(name: ar ? 'فول بالعيش' : 'Foul with bread', sub: '', kcal: 520, p: 22, c: 64, f: 18, at: DateTime.now()));
    s.meals.add(LoggedMeal(name: ar ? 'كشري' : 'Koshary', sub: '', kcal: 700, p: 12, c: 118, f: 14, at: DateTime.now()));
  }
  s.go(AppScreen.today);
  return s;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  for (final lang in AppLang.values) {
    final l = lang.name;
    final ar = lang == AppLang.ar;

    // First run.
    _scene('01_welcome_$l', (t) async => _shoot(t, _fresh(lang), '01_welcome_$l'));
    _scene('02_onboarding_$l', (t) async => _shoot(t, _fresh(lang)..startOnboarding(), '02_onboarding_$l'));
    _scene('03_scan_denied_$l', (t) async {
      final s = _fresh(lang)..go(AppScreen.scan);
      s.setScanProblem(s.cameraProblem(PlatformException(code: 'camera_access_denied'), instead: ProblemAction(ar ? 'اكتبها بنفسك' : 'Type it instead', () {})));
      await _shoot(t, s, '03_scan_denied_$l');
    });

    // The day.
    _scene('04_today_first_$l', (t) async => _shoot(t, _today(lang, tutorial: true), '04_today_first_$l'));
    _scene('05_today_logged_$l', (t) async => _shoot(t, _today(lang, logged: true), '05_today_logged_$l'));
    _scene('05b_today_tall_$l', (t) async => _shoot(t, _today(lang, logged: true), '05b_today_tall_$l', height: 1800));
    _scene('06_log_$l', (t) async => _shoot(t, _today(lang, logged: true), '06_log_$l', after: (s) => s.orbTap()));
    _scene('07_why_$l', (t) async => _shoot(t, _today(lang, logged: true), '07_why_$l', after: (s) => s.openWhy()));
    _scene('08_explain_$l', (t) async => _shoot(t, _today(lang, logged: true), '08_explain_$l', after: (s) => s.openExplain(kExplanations['kcal_remaining']!)));
    _scene('09_activity_$l', (t) async => _shoot(t, _today(lang), '09_activity_$l', after: (s) => s.chooseActivity(ActivityKind.walk)));

    // The conversation.
    _scene('10_chat_empty_$l', (t) async {
      final s = _today(lang)..chatOpen = true;
      await _shoot(t, s, '10_chat_empty_$l');
    });
    _scene('11_chat_thread_$l', (t) async {
      final s = _today(lang)..chatOpen = true;
      s.aiQuota = const AiQuota(bucket: 'chat', used: 3, limit: 20, extra: 0, remaining: 17);
      s.chat.addAll([
        ChatTurn(who: ChatWho.u, text: ar ? 'أكلت حتتين فطير عند خالتي، ده وحش؟' : 'I had two pieces of feteer at my aunt’s, is that bad?'),
        ChatTurn(
          who: ChatWho.q,
          text: ar ? 'مش وحش، بس تقيل. الحتتين حوالي ٦٢٠ سعر، أغلبهم زبدة ودقيق، عشان كده مش بيشبعوا كتير.' : 'Not bad, just heavy. Two pieces is about 620 kcal, most of it butter and flour, which is why it does not hold you for long.',
          sub: ar ? 'فاضلك حوالي ٩٠٠ سعر النهارده.' : 'That leaves roughly 900 kcal for the rest of today.',
          action: ar ? 'شوف خطة الليلة' : 'See tonight’s plan',
        ),
        ChatTurn(who: ChatWho.u, text: ar ? 'طب آكل إيه بالليل؟' : 'What should I eat tonight then?'),
      ]);
      s.chatState = ChatState.thinking;
      await _shoot(t, s, '11_chat_thread_$l');
    });

    _scene('11b_chat_confirm_$l', (t) async {
      final s = _today(lang)..chatOpen = true;
      s.chat.add(ChatTurn(who: ChatWho.u, text: ar ? 'فطرت فول وعيش وبيضة' : 'Breakfast was foul, bread and an egg'));
      s.proposal = MealAnalysis([
        ConfirmItemDef(ar: 'فول مدمس', en: 'Foul medames', portionAr: 'طبق وسط', portionEn: 'a medium plate', conf: Confidence.high, kcal: 320, p: 18, c: 40, f: 9),
        ConfirmItemDef(ar: 'عيش بلدي', en: 'Baladi bread', portionAr: 'رغيف', portionEn: 'one loaf', conf: Confidence.high, kcal: 250, p: 9, c: 50, f: 2),
        ConfirmItemDef(ar: 'بيضة مسلوقة', en: 'Boiled egg', portionAr: 'واحدة', portionEn: 'one', conf: Confidence.med, kcal: 78, p: 6, c: 1, f: 5),
      ]);
      s.proposalQty = [1, 1, 1];
      await _shoot(t, s, '11b_chat_confirm_$l');
    });
    _scene('11c_chat_listening_$l', (t) async {
      final s = _today(lang)..chatOpen = true;
      s.chatState = ChatState.listening;
      await _shoot(t, s, '11c_chat_listening_$l');
    });

    // The other tabs, and the pages under them.
    _scene('12_plan_$l', (t) async => _shoot(t, _today(lang)..go(AppScreen.plan), '12_plan_$l'));
    _scene('13_progress_$l', (t) async => _shoot(t, _today(lang, logged: true)..go(AppScreen.progress), '13_progress_$l'));
    _scene('14_you_$l', (t) async {
      final s = _today(lang)..suAvailable = 1250..suLifetime = 3400;
      await _shoot(t, s..go(AppScreen.you), '14_you_$l', height: 2100);
    });
    _scene('15_account_$l', (t) async => _shoot(t, _today(lang)..go(AppScreen.you), '15_account_$l', after: (s) => s.openSignIn()));
    _scene('16_subscription_$l', (t) async => _shoot(t, _today(lang)..go(AppScreen.subscription), '16_subscription_$l', height: 1500));
    _scene('17_wallet_$l', (t) async => _shoot(t, (_today(lang)..suAvailable = 1250)..go(AppScreen.wallet), '17_wallet_$l'));
    _scene('18_ramadan_$l', (t) async {
      final s = AppState(ai: _Ai(), clock: () => DateTime(2027, 2, 12, 20))..setLang(lang);
      s.profile = s.profile.copyWith(name: 'Basel');
      s.dismissOrbTutorial();
      s.go(AppScreen.ramadan);
      await _shoot(t, s, '18_ramadan_$l');
    });
  }
}
