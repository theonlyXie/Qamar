import 'package:flutter_test/flutter_test.dart';

import 'package:qamar/l10n/strings.dart';
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
    expect(QuickInvoke.parseUri(Uri.parse('com.qamar.app://plus/return'))?.kind, 'plus');
    expect(QuickInvoke.parseUri(Uri.parse('com.qamar.app://login-callback')), isNull);
    expect(QuickInvoke.parseUri(Uri.parse('https://example.com/quick/ask')), isNull);
  });

  test('invitation links carry the code, from the site or the scheme', () {
    expect(QuickInvoke.parseUri(Uri.parse('https://dr-qamar.com/i/QMR-7H2K9'))?.kind, 'invite');
    expect(QuickInvoke.parseUri(Uri.parse('https://dr-qamar.com/i/QMR-7H2K9'))?.text, 'QMR-7H2K9');
    expect(QuickInvoke.parseUri(Uri.parse('https://www.dr-qamar.com/i/abc/'))?.text, 'abc');
    expect(QuickInvoke.parseUri(Uri.parse('qamar://i/QMR-1'))?.text, 'QMR-1');
    expect(QuickInvoke.parseUri(Uri.parse('com.qamar.app://i/QMR-2'))?.text, 'QMR-2');
    expect(QuickInvoke.parseUri(Uri.parse('https://dr-qamar.com/privacy')), isNull, reason: 'only /i/ is an invitation');
    expect(QuickInvoke.parseUri(Uri.parse('https://evil.example/i/QMR-1')), isNull, reason: 'only the site’s own host');
    expect(QuickInvoke.parseMap({'action': 'invite', 'text': ' QMR-3 '})?.text, 'QMR-3');
    expect(QuickInvoke.parseMap({'action': 'invite'}), isNull);
  });

  test('a nutritionist\'s code link carries the code through the same doors, with p', () {
    expect(QuickInvoke.parseUri(Uri.parse('https://dr-qamar.com/p/QMRSARA1'))?.kind, 'pro');
    expect(QuickInvoke.parseUri(Uri.parse('https://dr-qamar.com/p/QMRSARA1'))?.text, 'QMRSARA1');
    expect(QuickInvoke.parseUri(Uri.parse('https://www.dr-qamar.com/p/abc/'))?.text, 'abc');
    expect(QuickInvoke.parseUri(Uri.parse('qamar://p/QMR1'))?.kind, 'pro');
    expect(QuickInvoke.parseUri(Uri.parse('com.qamar.app://p/QMR2'))?.text, 'QMR2');
    expect(QuickInvoke.parseUri(Uri.parse('https://dr-qamar.com/i/QMR-7H2K9'))?.kind, 'invite', reason: 'an invitation is still an invitation');
    expect(QuickInvoke.parseUri(Uri.parse('https://evil.example/p/QMR1')), isNull, reason: 'only the site’s own host');
    expect(QuickInvoke.parseMap({'action': 'pro', 'text': ' QMRSARA1 '})?.kind, 'pro');
    expect(QuickInvoke.parseMap({'action': 'pro', 'text': ' QMRSARA1 '})?.text, 'QMRSARA1');
    expect(QuickInvoke.parseMap({'action': 'pro'}), isNull);
  });

  test('a nutritionist\'s code before there is an account waits on the phone, and says so', () async {
    final state = AppState()..setLang(AppLang.en);
    QuickInvoke.apply(state, const QuickAction(kind: 'pro', text: 'qmrsara1'));
    await Future<void>.delayed(Duration.zero);
    expect(state.pendingProCode, 'QMRSARA1');
    expect(state.proCodeWaiting, isTrue);
    expect(state.proNotice, contains('kept on this phone'));
  });

  test('a link before there is an account waits on the phone, with a word on Welcome', () async {
    final state = AppState()..setLang(AppLang.en);
    QuickInvoke.apply(state, const QuickAction(kind: 'invite', text: 'QMR-9'));
    await Future<void>.delayed(Duration.zero);
    expect(state.pendingInvitationCode, 'QMR-9');
    expect(state.invitationNotice, contains('You have an invitation'));
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

  test('apply log with text opens the conversation as a meal, not a question', () {
    final state = AppState();
    QuickInvoke.apply(state, const QuickAction(kind: 'log', text: 'foul medames'));
    expect(state.chatOpen, isTrue);
    expect(state.screen, isNot(AppScreen.subscription));
  });
}
