// The conversation header's line (O8), seat 6's part: the line keeps its
// height when it has nothing to say, so Qamar's name never jumps as a status
// comes and goes; it is set at 12pt; and the quota is drawn in textMuted,
// which passes AA on the conversation's ground where the old faint grey did
// not. What the line says, and when, is seat 2's
// (conversation_header_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:qamar/l10n/strings.dart';
import 'package:qamar/models/su_economy.dart';
import 'package:qamar/services/ai_gateway.dart';
import 'package:qamar/state/app_state.dart';
import 'package:qamar/theme/colors.dart';
import 'package:qamar/widgets/ask_qamar_overlay.dart';

import 'support/app_fonts.dart';
import 'support/contrast.dart';

class _Ai implements AiGateway {
  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

AiQuota _chat(int remaining) => AiQuota(bucket: 'chat', used: 3 - remaining, limit: 3, extra: 0, remaining: remaining);

/// The conversation's ground under the header (ask_qamar_overlay's scrim
/// top, cardDeep at 95%, over the app's darkest background).
final _ground = over(QColors.cardDeep.withValues(alpha: 0.95), QColors.bgBottom);

void main() {
  setUpAll(loadAppFonts);

  for (final lang in AppLang.values) {
    testWidgets('the name stays put while the line comes and goes (${lang.name})', (tester) async {
      await tester.binding.setSurfaceSize(const Size(390, 844));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final s = AppState(ai: _Ai())
        ..setLang(lang)
        ..aiQuota = _chat(3);
      await tester.pumpWidget(ChangeNotifierProvider.value(
        value: s,
        child: MaterialApp(
          builder: (context, child) => Directionality(textDirection: s.isAr ? TextDirection.rtl : TextDirection.ltr, child: child!),
          home: const Scaffold(body: AskQamarOverlay()),
        ),
      ));
      // At rest: the conversation's entrance (a spring) has settled.
      await tester.pump(const Duration(milliseconds: 800));
      final name = find.text(s.t.brand);
      final quiet = tester.getRect(name);
      final lineBox = tester.getRect(find.byKey(ChatHeader.lineKey));
      expect(lineBox.height, ChatHeader.lineHeight, reason: 'the empty line keeps its height');
      expect(quiet.center.dx, moreOrLessEquals(195, epsilon: 0.5), reason: 'the name is centred on the screen');

      final states = <String, void Function()>{
        'the last question': () => s.aiQuota = _chat(1),
        'none left': () => s.aiQuota = _chat(0),
        'listening': () => s.chatState = ChatState.listening,
        'thinking': () => s.chatState = ChatState.thinking,
        'a dictation error': () => s.dictationError = 'Dictation is not available.',
      };
      for (final e in states.entries) {
        e.value();
        s.setLang(lang); // rebuild
        await tester.pump(const Duration(milliseconds: 400));
        expect(tester.getRect(name), quiet, reason: 'the name does not move for ${e.key}');
        final texts = tester.widgetList<Text>(find.descendant(of: find.byKey(ChatHeader.lineKey), matching: find.byType(Text)));
        expect(texts, isNotEmpty, reason: '${e.key} says something');
        for (final t in texts) {
          expect(t.style!.fontSize, 12, reason: '${e.key} at 12pt');
        }
      }
    });
  }

  testWidgets('the quota is drawn in textMuted, which passes AA on the ground', (tester) async {
    final s = AppState(ai: _Ai())
      ..setLang(AppLang.en)
      ..aiQuota = _chat(1);
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(ChangeNotifierProvider.value(value: s, child: const MaterialApp(home: Scaffold(body: AskQamarOverlay()))));
    await tester.pump(const Duration(milliseconds: 400));
    final line = tester.widget<Text>(find.text('Last question today'));
    expect(line.style!.color, QColors.textMuted);
    expect(contrastRatio(QColors.textMuted, _ground), greaterThanOrEqualTo(4.5));
  });
}
