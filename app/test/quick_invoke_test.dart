import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/services/quick_invoke.dart';
import 'package:qamar/state/app_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses ask and log deep links', () {
    final ask = QuickInvoke.parseUri(Uri.parse('com.qamar.app://quick/ask'));
    expect(ask?.kind, 'ask');
    expect(ask?.text, isNull);

    final log = QuickInvoke.parseUri(
      Uri.parse('com.qamar.app://quick/log?q=foul%20medames'),
    );
    expect(log?.kind, 'log');
    expect(log?.text, 'foul medames');
  });

  test('parses host-only ask/log URLs and ignores unrelated ones', () {
    expect(QuickInvoke.parseUri(Uri.parse('com.qamar.app://ask'))?.kind, 'ask');
    expect(QuickInvoke.parseUri(Uri.parse('com.qamar.app://login-callback')), isNull);
    expect(QuickInvoke.parseUri(Uri.parse('https://example.com/quick/ask')), isNull);
  });

  test('parses native payload maps', () {
    final a = QuickInvoke.parseMap({'action': 'ask', 'text': '  protein  '});
    expect(a?.kind, 'ask');
    expect(a?.text, 'protein');
    expect(QuickInvoke.parseMap({'action': 'nope'}), isNull);
  });

  test('apply ask opens the companion overlay', () {
    final state = AppState();
    QuickInvoke.apply(state, const QuickAction(kind: 'ask'));
    expect(state.chatOpen, isTrue);
  });
}
