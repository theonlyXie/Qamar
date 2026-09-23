// What Qamar's lines carry in the conversation. Only an answer has the copy
// action under it: the greeting, the meal question and a notice are Qamar's
// own words, not something to take away. Asked to log a meal, Qamar says one
// thing (the question), with the keyboard up and no questions offered.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:qamar/l10n/strings.dart';
import 'package:qamar/main.dart';
import 'package:qamar/models/messages.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/widgets/ask_qamar_overlay.dart';

Future<AppState> _open(WidgetTester tester, void Function(AppState s) arrange) async {
  final s = AppState()..setLang(AppLang.en);
  s.go(AppScreen.today);
  await tester.binding.setSurfaceSize(const Size(430, 932));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const QamarApp()));
  arrange(s);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  return s;
}

final _suggestion = find.descendant(of: find.byType(AskQamarOverlay), matching: find.text('I ate koshary, what now?'));

void main() {
  testWidgets('the newest answer can be copied', (tester) async {
    await _open(tester, (s) {
      s.chat.add(const ChatTurn(who: ChatWho.u, text: 'Is feteer ok tonight?'));
      s.chat.add(const ChatTurn(who: ChatWho.q, text: 'Half a feteer, with a salad beside it.', answer: true));
      s.openChat();
    });
    expect(find.byKey(AskQamarOverlay.copyKey), findsOneWidget);
  });

  testWidgets('the greeting is not an answer: nothing to copy, and questions are offered', (tester) async {
    final s = await _open(tester, (s) => s.openChat());
    expect(s.chat.single.answer, isFalse);
    expect(find.byKey(AskQamarOverlay.copyKey), findsNothing);
    expect(_suggestion, findsOneWidget);
  });

  testWidgets('logging a meal in words: the question alone, the keyboard up, no questions offered', (tester) async {
    final s = await _open(tester, (s) => s.quickLog(QuickLog.text));
    expect(s.chat.map((t) => t.text), ['Tell me what you ate.'], reason: 'one line from Qamar, not a greeting and then the question');
    expect(find.byKey(AskQamarOverlay.copyKey), findsNothing);
    expect(_suggestion, findsNothing, reason: 'Qamar is waiting to hear a meal, not a question');
    final field = tester.widget<TextField>(find.descendant(of: find.byType(AskQamarOverlay), matching: find.byType(TextField)));
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('a photo keeps the greeting, for a camera that is cancelled', (tester) async {
    final s = await _open(tester, (s) => s.quickLog(QuickLog.photo));
    expect(s.chat, hasLength(1));
    expect(s.chat.single.text, startsWith('I’m here.'));
    final field = tester.widget<TextField>(find.descendant(of: find.byType(AskQamarOverlay), matching: find.byType(TextField)));
    expect(field.focusNode!.hasFocus, isFalse, reason: 'the camera is the way in, not the keyboard');
  });
}
