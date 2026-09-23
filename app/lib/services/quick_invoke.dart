import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

import '../state/app_state.dart';

/// A system-level request to talk to Qamar without walking the in-app nav.
///
/// Comes from iPhone Back Tap / Siri Shortcuts, Android home-screen shortcuts,
/// or the `com.qamar.app://quick/...` URL.
class QuickAction {
  /// `ask` — open the companion and answer. `log` — treat speech/text as a
  /// meal. `plus` — back from Paymob. `invite` — an invitation code from a
  /// link, in [text]. `pro` — a nutritionist's code from a link, in [text].
  final String kind;
  final String? text;
  const QuickAction({required this.kind, this.text});

  bool get isLog => kind == 'log';
}

/// Parses and delivers shortcut / Back Tap / deep-link invocations.
class QuickInvoke {
  static const _method = MethodChannel('com.qamar.app/quick');
  static const _events = EventChannel('com.qamar.app/quick_events');

  /// The invitation code in a link, or null: `qamar://i/<code>`,
  /// `com.qamar.app://i/<code>`, or the site's `https://dr-qamar.com/i/<code>`
  /// that the shared message carries.
  static String? inviteCode(Uri uri) => _codeIn(uri, 'i');

  /// A nutritionist's code in a link, or null: `qamar://p/<code>`,
  /// `com.qamar.app://p/<code>`, or `https://dr-qamar.com/p/<code>` — the
  /// same doors as an invitation, with their own letter.
  static String? proCode(Uri uri) => _codeIn(uri, 'p');

  static String? _codeIn(Uri uri, String door) {
    final segs = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    if ((scheme == 'qamar' || scheme == 'com.qamar.app') && host == door && segs.isNotEmpty) {
      return segs.first.trim();
    }
    if ((scheme == 'https' || scheme == 'http') &&
        (host == 'dr-qamar.com' || host == 'www.dr-qamar.com') &&
        segs.length >= 2 &&
        segs[0] == door) {
      return segs[1].trim();
    }
    return null;
  }

  /// `com.qamar.app://quick/ask?q=...` and `.../log`, and invitation links.
  static QuickAction? parseUri(Uri uri) {
    final code = inviteCode(uri);
    if (code != null && code.isNotEmpty) return QuickAction(kind: 'invite', text: code);
    final pro = proCode(uri);
    if (pro != null && pro.isNotEmpty) return QuickAction(kind: 'pro', text: pro);
    if (uri.scheme != 'com.qamar.app') return null;
    final host = uri.host;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    String? kind;
    if (host == 'quick' && segments.isNotEmpty) {
      kind = segments.first;
    } else if (host == 'ask' || host == 'log' || host == 'plus') {
      kind = host;
    } else if (segments.length >= 2 && segments[0] == 'quick') {
      kind = segments[1];
    }
    if (kind == 'plus') return const QuickAction(kind: 'plus');
    if (kind != 'ask' && kind != 'log') return null;
    final text = uri.queryParameters['q'] ?? uri.queryParameters['text'];
    return QuickAction(kind: kind!, text: (text == null || text.trim().isEmpty) ? null : text.trim());
  }

  static QuickAction? parseMap(dynamic raw) {
    if (raw is! Map) return null;
    final kind = raw['action']?.toString() ?? raw['kind']?.toString();
    if (kind == 'plus') return const QuickAction(kind: 'plus');
    if (kind == 'invite' || kind == 'pro') {
      final code = (raw['text'] ?? raw['code'])?.toString().trim();
      return code == null || code.isEmpty ? null : QuickAction(kind: kind!, text: code);
    }
    if (kind != 'ask' && kind != 'log') return null;
    final text = raw['text']?.toString() ?? raw['q']?.toString();
    return QuickAction(kind: kind!, text: (text == null || text.trim().isEmpty) ? null : text.trim());
  }

  /// Applies the action to [state]: opens Ask Qamar, optionally starts listening.
  static void apply(AppState state, QuickAction action) {
    if (action.kind == 'plus') {
      state.onReturnedFromPaymob();
      return;
    }
    if (action.kind == 'invite') {
      state.acceptInvitationLink(action.text ?? '');
      return;
    }
    if (action.kind == 'pro') {
      state.acceptProLink(action.text ?? '');
      return;
    }
    if (action.isLog) {
      if (action.text != null) {
        state.quickLog(QuickLog.text);
        state.sendChatMsg(action.text!);
      } else {
        state.quickLog(QuickLog.voice);
      }
      return;
    }
    state.openChat();
    if (action.text != null) {
      state.sendChatMsg(action.text!);
    } else {
      state.tapOrbListen();
    }
  }

  static Future<QuickAction?> takePending() async {
    try {
      final raw = await _method.invokeMethod<dynamic>('takePending');
      return parseMap(raw);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  /// Shortcuts and links as they arrive. A browser has no such channel,
  /// and a platform without the plugin says so as an error on the stream:
  /// both are simply no shortcuts, not a failure to report.
  static Stream<QuickAction> events() {
    if (kIsWeb) return const Stream.empty();
    return _events
        .receiveBroadcastStream()
        .handleError((Object _) {}, test: (e) => e is MissingPluginException || e is PlatformException)
        .map(parseMap)
        .where((a) => a != null)
        .cast<QuickAction>();
  }
}
