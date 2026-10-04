// Drag-to-explain's signifier (seat 2): every value the orb can explain
// carries a quiet dotted line under it, and nothing else does. The tutorial
// names the mark, so the gesture can be found without it.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/app_theme.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/widgets/explain.dart';
import 'package:qamar/widgets/kit.dart';
import 'package:qamar/widgets/orb_gesture_guide.dart';

const _planJson = '''
{"date":"2026-09-22","plan":{"rationale_ar":"","rationale_en":"","meals":[
  {"slot":"lunch","name_ar":"فول","name_en":"Foul","note_ar":"","note_en":"",
   "portions":[{"ar":"فول","en":"Foul","amount_ar":"١٥٠ جم","amount_en":"150 g","kcal":180}]}
]}}
''';

class _Parser extends HttpAiGateway {
  _Parser() : super(baseUrl: 'http://test', authTokenProvider: () => '');
  DayPlan parse() => planFromBody(_planJson, 'en', '2026-09-22');
}

Future<void> _pump(WidgetTester tester, AppState s) async {
  await tester.binding.setSurfaceSize(const Size(900, 4000)); // every region built
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

void _everyExplainableMarked(WidgetTester tester, String where) {
  final regions = find.byType(Explainable);
  expect(regions, findsWidgets, reason: 'there is something to explain on $where');
  for (final e in regions.evaluate()) {
    final id = (e.widget as Explainable).id;
    expect(find.descendant(of: find.byWidget(e.widget), matching: find.byType(ExplainMark)), findsWidgets,
        reason: '"$id" on $where can be explained but nothing marks it');
  }
  for (final m in find.byType(ExplainMark).evaluate()) {
    expect(m.findAncestorWidgetOfExactType<Explainable>(), isNotNull, reason: 'a mark on $where the orb cannot explain');
  }
}

void main() {
  setUpAll(() {
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  final screens = <(String, void Function(AppState))>[
    ('Today, with a plan', (s) {
      s.plan = _Parser().parse();
      s.go(AppScreen.today);
    }),
    ('Plan', (s) {
      s.plan = _Parser().parse();
      s.go(AppScreen.plan);
    }),
    ('Progress', (s) => s.go(AppScreen.progress)),
    ('the wallet', (s) => s.openWallet()),
  ];

  for (final lang in AppLang.values) {
    for (final (where, open) in screens) {
      testWidgets('every explainable value on $where carries the mark, and only those (${lang.name})', (tester) async {
        final s = AppState()..setLang(lang);
        open(s);
        await _pump(tester, s);
        _everyExplainableMarked(tester, where);
      });
    }
  }

  testWidgets('the mark is a dotted line under the value, and leaves the value where it was', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: AppState(),
      child: MaterialApp(
        theme: buildQamarTheme(),
        home: const Scaffold(body: Center(child: Explainable(id: 'protein', child: ExplainMark(child: Text('34 / 148 g'))))),
      ),
    ));
    final mark = tester.getRect(find.byType(ExplainMark));
    final text = tester.getRect(find.text('34 / 148 g'));
    expect(mark, text, reason: 'it draws over the value’s own box, adding nothing to the layout');
    expect(find.byType(ExplainMark), paints..circle(color: ExplainMark.color), reason: 'on the dark, the second ink');
  });

  testWidgets('on a pastel the dots are black, as the words there are', (tester) async {
    await tester.pumpWidget(ChangeNotifierProvider.value(
      value: AppState(),
      child: MaterialApp(
        theme: buildQamarTheme(),
        home: const Scaffold(
          body: Center(
            child: PastelCard(color: QColors.mint, child: Explainable(id: 'protein', child: ExplainMark(child: Text('34 / 148 g')))),
          ),
        ),
      ),
    ));
    expect(find.byType(ExplainMark), paints..circle(color: ExplainMark.pastelColor));
  });

  test('the tutorial names the mark, in both languages', () {
    final (_, _, doAr, doEn, _, _) = OrbGestureGuide.rows().last;
    expect(doEn, 'Drag it onto a dotted number');
    expect(doAr, 'اسحبه على رقم تحته نقط');
  });
}
