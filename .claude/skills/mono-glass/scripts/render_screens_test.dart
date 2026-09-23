// Mono-glass render harness for Qamar: draws every screen, in English and
// Arabic, at phone size, to PNG files you can look at.
//
// This is a temporary test file and is never committed. To use it:
//
//   cp .claude/skills/mono-glass/scripts/render_screens_test.dart app/test/zz_render_tmp_test.dart
//   cd app && flutter test --update-goldens test/zz_render_tmp_test.dart \
//       --dart-define=OUT=/abs/path/for/pngs --dart-define=SHOT=after [--dart-define=ONLY=today]
//   rm -f test/zz_render_tmp_test.dart; rm -rf test/failures
//
// OUT is where the PNGs go (default /tmp/mono-glass-renders). SHOT names a
// sub-folder, so you can compare `before` with `after`. ONLY keeps just the
// scenes whose name contains that text.
//
// Fonts: the bundled Inter and Noto Sans Arabic (app/assets/fonts), plus the
// Cupertino icon font from the pub cache. Glyphs render as boxes if that font
// is missing, so check the path below if you see boxes.
//
// Add a scene for any screen or sheet you change. The pattern is: build an
// AppState, put it where the screen is, then call _shoot.
import 'dart:io';

import 'package:flutter/material.dart';
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

const _tag = String.fromEnvironment('SHOT', defaultValue: 'after');
const _only = String.fromEnvironment('ONLY', defaultValue: '');
const _out = String.fromEnvironment('OUT', defaultValue: '/tmp/mono-glass-renders');

class _Ai implements AiGateway {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError();
}

Future<void> _fonts() async {
  final home = Platform.environment['PUB_CACHE'] ?? '${Platform.environment['HOME']}/.pub-cache';
  final hosted = Directory('$home/hosted/pub.dev');
  final cupertino = hosted.existsSync()
      ? hosted.listSync().whereType<Directory>().where((d) => d.path.contains('cupertino_icons-')).map((d) => File('${d.path}/assets/CupertinoIcons.ttf')).where((f) => f.existsSync()).toList()
      : <File>[];
  if (cupertino.isNotEmpty) {
    await (FontLoader('packages/cupertino_icons/CupertinoIcons')..addFont(Future.value(cupertino.last.readAsBytesSync().buffer.asByteData()))).load();
  }
  final loaders = <String, FontLoader>{};
  for (final f in Directory('assets/fonts').listSync().whereType<File>()) {
    final family = f.path.contains('Noto') ? 'Noto Sans Arabic' : 'Inter';
    loaders.putIfAbsent(family, () => FontLoader(family)).addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
  }
  for (final l in loaders.values) {
    await l.load();
  }
}

/// Draws the app with [state] on a 390 × [height] phone (iPhone 14 insets),
/// runs [after] once it has settled, and writes `<OUT>/<SHOT>/<name>.png`.
Future<void> _shoot(WidgetTester t, AppState state, String name, {double height = 844, void Function(AppState s)? after, Duration settle = const Duration(milliseconds: 900)}) async {
  t.view.physicalSize = Size(390 * 3, height * 3);
  t.view.devicePixelRatio = 3.0;
  t.view.padding = const FakeViewPadding(top: 47 * 3, bottom: 34 * 3);
  addTearDown(t.view.reset);
  await t.runAsync(() async {
    await t.pumpWidget(ChangeNotifierProvider.value(value: state, child: const QamarApp()));
    await Future.delayed(const Duration(milliseconds: 900));
  });
  await t.pump();
  await t.pump(const Duration(milliseconds: 900));
  if (after != null) {
    after(state);
    await t.pump();
    await t.pump(settle);
  }
  await expectLater(find.byType(QamarApp), matchesGoldenFile(Uri.file('$_out/$_tag/$name.png')));
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
    await _fonts();
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
    _scene('06_tree_$l', (t) async => _shoot(t, _today(lang), '06_tree_$l', after: (s) => s.orbTap()));
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

    // The rest of the tree.
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
