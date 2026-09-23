// Progress and the week's card count days, meals and the run the way each
// language counts (Counted, lib/l10n/words.dart), seat 3's part. They said
// "٢ أيام ورا بعض", "١٢ أيام", "٢ أيام نشاط", "٢ وجبة" and "لسه ١ يوم"; the
// weekly insight's gate wrote its "٣" in Eastern digits whatever the
// setting, and the weight trend's span and amount ignored it, with "over 1
// days" in English.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/review_card.dart';

import 'support/app_fonts.dart';

final _now = DateTime(2026, 9, 23, 13);

/// Progress, for a person who logged [meals] on each of the [days] before
/// today (oldest first), and [today] meals today.
AppState _state(AppLang lang, {List<int> days = const [], int today = 0, List<WeightReading> weights = const [], bool eastern = true}) {
  final s = AppState(clock: () => _now)..setLang(lang);
  s.setFasting(false);
  s.dismissOrbTutorial();
  s.setEasternDigits(eastern);
  for (var i = 0; i < days.length; i++) {
    if (days[i] > 0) s.dayHistory.add(DayTotals(day: DateTime(2026, 9, 23 - days.length + i), kcal: 900 * days[i], meals: days[i]));
  }
  for (var m = 0; m < today; m++) {
    s.meals.add(LoggedMeal(name: 'Foul', sub: '', kcal: 500, p: 20, c: 60, f: 12, at: _now));
  }
  s.weightHistory.addAll(weights);
  s.go(AppScreen.today);
  s.go(AppScreen.progress);
  return s;
}

String _plain(String s) => s.replaceAll('\u00A0', ' ').replaceAll(RegExp('[\u2066-\u2069]'), '');

/// Every line of text on Progress, as read.
Future<List<String>> _progress(WidgetTester tester, AppState s) async {
  tester.view.devicePixelRatio = 3;
  tester.view.physicalSize = const Size(390, 3000) * 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  return [for (final e in find.byType(RichText).evaluate()) _plain((e.renderObject! as RenderParagraph).text.toPlainText())];
}

/// The run as the shared card says it.
String _cardRun(WidgetTester tester) {
  final texts = [
    for (final e in find.descendant(of: find.byType(ReviewCard), matching: find.byType(RichText)).evaluate())
      _plain((e.renderObject! as RenderParagraph).text.toPlainText()),
  ];
  return texts.firstWhere((t) => t.contains('ورا بعض') || t.contains('in a row'), orElse: () => '(no run)');
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  testWidgets('a run of one, two and twelve, on the streak card and the shared card', (tester) async {
    var lines = await _progress(tester, _state(AppLang.ar, today: 1));
    expect(lines, contains('يوم واحد ورا بعض · النهاردة محسوب'));

    lines = await _progress(tester, _state(AppLang.ar, days: [1], today: 1));
    expect(lines, contains('يومين ورا بعض · النهاردة محسوب'));
    expect(_cardRun(tester), 'يومين ورا بعض');

    lines = await _progress(tester, _state(AppLang.ar, days: List.filled(11, 1), today: 1));
    expect(lines, contains('١٢ يوم ورا بعض · النهاردة محسوب'));
    expect(_cardRun(tester), '١٢ يوم ورا بعض');

    lines = await _progress(tester, _state(AppLang.ar, days: [1, 1, 1], today: 1));
    expect(_cardRun(tester), '٤ أيام ورا بعض');

    lines = await _progress(tester, _state(AppLang.ar, days: [1, 1]));
    expect(lines, contains('يومين · وجبة واحدة قبل نص الليل تكمّلها'), reason: 'a run today has not joined yet');

    lines = await _progress(tester, _state(AppLang.en, days: [1], today: 1));
    expect(lines, contains('2 days in a row · today counted'));
    expect(_cardRun(tester), '2 days in a row');
    lines = await _progress(tester, _state(AppLang.en, today: 1));
    expect(lines, contains('1 day in a row · today counted'));
  });

  testWidgets('this week: days active and meals logged', (tester) async {
    var lines = await _progress(tester, _state(AppLang.ar, today: 1));
    expect(lines.any((l) => l.startsWith('يوم واحد نشاط · وجبة واحدة مسجلة')), isTrue, reason: '$lines');
    lines = await _progress(tester, _state(AppLang.ar, days: [1], today: 1));
    expect(lines.any((l) => l.startsWith('يومين نشاط · وجبتين مسجلتين')), isTrue, reason: '$lines');
    lines = await _progress(tester, _state(AppLang.ar, days: [3, 3, 3, 1], today: 1));
    expect(lines.any((l) => l.startsWith('٥ أيام نشاط · ١١ وجبة مسجلة')), isTrue, reason: '$lines');
    lines = await _progress(tester, _state(AppLang.ar, days: [2, 2], today: 1));
    expect(lines.any((l) => l.startsWith('٣ أيام نشاط · ٥ وجبات مسجلة')), isTrue, reason: '$lines');
  });

  testWidgets('the weekly insight waits for three days, in the app’s digits', (tester) async {
    var lines = await _progress(tester, _state(AppLang.ar, today: 1));
    expect(lines, contains('رأي الأسبوع بيظهر بعد ٣ أيام مسجلة. لسه يومين.'));
    lines = await _progress(tester, _state(AppLang.ar, days: [1], today: 1));
    expect(lines, contains('رأي الأسبوع بيظهر بعد ٣ أيام مسجلة. لسه يوم واحد.'));
    lines = await _progress(tester, _state(AppLang.ar, today: 1, eastern: false));
    expect(lines, contains('رأي الأسبوع بيظهر بعد 3 أيام مسجلة. لسه يومين.'), reason: 'Western digits asked for');
    expect(lines.where((l) => RegExp('[٠-٩]').hasMatch(l)), isEmpty, reason: 'no Eastern digit anywhere on Progress');
  });

  testWidgets('the weight trend counts its span, and draws its figures in the app’s digits', (tester) async {
    WeightReading at(int day, double kg) => WeightReading(at: DateTime(2026, 9, day, 8), kg: kg);
    var lines = await _progress(tester, _state(AppLang.ar, today: 1, weights: [at(16, 80), at(23, 79)]));
    expect(lines, contains('نزلت ١.٠ كجم على مدى ٧ أيام. قياس واحد مش دليل.'));
    lines = await _progress(tester, _state(AppLang.ar, today: 1, weights: [at(22, 80), at(23, 80.1)]));
    expect(lines, contains('وزنك ثابت تقريباً على مدى يوم واحد. قياس واحد مش دليل.'));
    lines = await _progress(tester, _state(AppLang.en, today: 1, weights: [at(22, 80), at(23, 80.1)]));
    expect(lines, contains('Essentially level over 1 day. A single reading is not evidence.'));
    lines = await _progress(tester, _state(AppLang.ar, today: 1, eastern: false, weights: [at(16, 80), at(23, 79)]));
    expect(lines, contains('نزلت 1.0 كجم على مدى 7 أيام. قياس واحد مش دليل.'));
  });
}
