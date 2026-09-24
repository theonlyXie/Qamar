// Progress and the week's card count days, meals and the run the way each
// language counts (Counted, lib/l10n/words.dart), seat 3's part. They said
// "٢ أيام ورا بعض", "١٢ أيام", "٢ أيام نشاط", "٢ وجبة" and "لسه ١ يوم"; the
// week's gate wrote its "٣" in Eastern digits whatever the setting, and the
// weight trend's span and amount ignored it, with "over 1 days" in English.
//
// The week's days are the screen's one large figure, with "of 7 days"
// beside it (the noun agrees with the seven, whatever the figure), its meals
// counted in words under it; the gate is the shared card's own sentence.

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/meal.dart';
import 'package:qamar/screens/progress_screen.dart';
import 'package:qamar/services/repositories.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/hero_number.dart';
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

/// Every line of text inside [of], as read.
List<String> _within(Finder of) => [
      for (final e in find.descendant(of: of, matching: find.byType(RichText)).evaluate()) _plain((e.renderObject! as RenderParagraph).text.toPlainText()),
    ];

/// The run as the shared card says it.
String _cardRun(WidgetTester tester) =>
    _within(find.byType(ReviewCard)).firstWhere((t) => t.contains('ورا بعض') || t.contains('in a row'), orElse: () => '(no run)');

/// The streak card's lines: its name, its run, and its note when it has one.
List<String> _streak(WidgetTester tester) => _within(find.byKey(ProgressScreen.streakKey));

/// The week's figure as drawn, and as a screen reader hears it.
({String drawn, String heard}) _figure(WidgetTester tester) {
  final dots = tester.widget<HeroNumber>(find.descendant(of: find.byKey(ProgressScreen.weekKey), matching: find.byType(HeroNumber)));
  return (drawn: dots.text, heard: _plain(dots.semanticsLabel!));
}

void main() {
  setUpAll(() async {
    await loadAppFonts();
    for (final name in const ['com.qamar.app/quick_events', 'com.qamar.app/quick_invoke']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel(name), (call) async => null);
    }
  });

  testWidgets('a run of one, two and twelve, on the streak card and the shared card', (tester) async {
    await _progress(tester, _state(AppLang.ar, today: 1));
    expect(_streak(tester), contains('يوم واحد ورا بعض'));

    await _progress(tester, _state(AppLang.ar, days: [1], today: 1));
    expect(_streak(tester), contains('يومين ورا بعض'));
    expect(_cardRun(tester), 'يومين ورا بعض');

    await _progress(tester, _state(AppLang.ar, days: List.filled(11, 1), today: 1));
    expect(_streak(tester), contains('١٢ يوم ورا بعض'));
    expect(_cardRun(tester), '١٢ يوم ورا بعض');

    await _progress(tester, _state(AppLang.ar, days: [1, 1, 1], today: 1));
    expect(_cardRun(tester), '٤ أيام ورا بعض');

    // A run today has not joined yet: its length, and what keeps it.
    await _progress(tester, _state(AppLang.ar, days: [1, 1]));
    expect(_streak(tester), containsAll(['يومين', 'وجبة واحدة قبل نص الليل تكمّلها.']));

    await _progress(tester, _state(AppLang.en, days: [1], today: 1));
    expect(_streak(tester), contains('2 days in a row'));
    expect(_cardRun(tester), '2 days in a row');
    await _progress(tester, _state(AppLang.en, today: 1));
    expect(_streak(tester), contains('1 day in a row'));
    await _progress(tester, _state(AppLang.en, days: [1, 1]));
    expect(_streak(tester), containsAll(['2 days', 'One meal before midnight keeps it going.']));
  });

  testWidgets('this week: the days in the figure, the meals counted in words', (tester) async {
    var lines = await _progress(tester, _state(AppLang.ar, today: 1));
    expect(_figure(tester), (drawn: '١', heard: '١ من ٧ أيام متسجّلة'));
    expect(lines, contains('من ٧ أيام متسجّلة، وجبة واحدة'));
    lines = await _progress(tester, _state(AppLang.ar, days: [1], today: 1));
    expect(_figure(tester).drawn, '٢');
    expect(lines, contains('من ٧ أيام متسجّلة، وجبتين'));
    lines = await _progress(tester, _state(AppLang.ar, days: [3, 3, 3, 1], today: 1));
    expect(_figure(tester).drawn, '٥');
    expect(lines, contains('من ٧ أيام متسجّلة، ١١ وجبة'));
    lines = await _progress(tester, _state(AppLang.ar, days: [2, 2], today: 1));
    expect(_figure(tester).drawn, '٣');
    expect(lines, contains('من ٧ أيام متسجّلة، ٥ وجبات'));
    lines = await _progress(tester, _state(AppLang.en, days: [2, 2], today: 1));
    expect(_figure(tester), (drawn: '3', heard: '3 of 7 days logged'));
    expect(lines, contains('of 7 days logged · 5 meals'));
    // Nothing logged: the week says so in words, with no lonely zero.
    lines = await _progress(tester, _state(AppLang.ar));
    expect(find.descendant(of: find.byKey(ProgressScreen.weekKey), matching: find.byType(HeroNumber)), findsNothing);
    expect(lines, contains('لسه مفيش أكل متسجّل الأسبوع ده. أول وجبة تسجّلها هتبان هنا.'));
  });

  testWidgets('the week’s card waits for three days, in the app’s digits', (tester) async {
    var lines = await _progress(tester, _state(AppLang.ar, today: 1));
    expect(lines, contains('سجّل ٣ أيام على الأقل وأقدر أقولك حاجة متتوقعها. لسه يومين.'));
    lines = await _progress(tester, _state(AppLang.ar, days: [1], today: 1));
    expect(lines, contains('سجّل ٣ أيام على الأقل وأقدر أقولك حاجة متتوقعها. لسه يوم واحد.'));
    lines = await _progress(tester, _state(AppLang.ar, today: 1, eastern: false));
    expect(lines, contains('سجّل 3 أيام على الأقل وأقدر أقولك حاجة متتوقعها. لسه يومين.'), reason: 'Western digits asked for');
    expect(_figure(tester).drawn, '1', reason: 'the figure too');
    expect(lines.where((l) => RegExp('[٠-٩]').hasMatch(l)), isEmpty, reason: 'no Eastern digit anywhere on Progress');
  });

  testWidgets('the weight trend counts its span, and draws its figures in the app’s digits', (tester) async {
    WeightReading at(int day, double kg) => WeightReading(at: DateTime(2026, 9, day, 8), kg: kg);
    var lines = await _progress(tester, _state(AppLang.ar, today: 1, weights: [at(16, 80), at(23, 79)]));
    expect(lines, contains('نزلت ١.٠ كجم في ٧ أيام.'));
    lines = await _progress(tester, _state(AppLang.ar, today: 1, weights: [at(22, 80), at(23, 80.1)]));
    expect(lines, contains('وزنك ثابت تقريباً بقاله يوم واحد.'));
    lines = await _progress(tester, _state(AppLang.en, today: 1, weights: [at(22, 80), at(23, 80.1)]));
    expect(lines, contains('Steady for 1 day.'));
    lines = await _progress(tester, _state(AppLang.en, today: 1, weights: [at(16, 80), at(23, 79)]));
    expect(lines, contains('Down 1.0 kg in 7 days.'));
    lines = await _progress(tester, _state(AppLang.ar, today: 1, eastern: false, weights: [at(16, 80), at(23, 79)]));
    expect(lines, contains('نزلت 1.0 كجم في 7 أيام.'));
    // One reading is no trend: nothing is drawn, and nothing is held open.
    lines = await _progress(tester, _state(AppLang.en, today: 1, weights: [at(23, 79)]));
    expect(lines.where((l) => l.contains('kg')), isEmpty);
  });
}
