import 'dart:async';

import 'package:flutter/services.dart';

import '../state/app_state.dart';

/// A system-level request to talk to Qamar without walking the in-app nav.
///
/// Comes from iPhone Back Tap / Siri Shortcuts, Android home-screen shortcuts,
/// or the `com.qamar.app://quick/...` URL.
class QuickAction {
  /// `ask` — open the companion and answer. `log` — treat speech/text as a meal.
  final String kind;
  final String? text;
  const QuickAction({required this.kind, this.text});

  bool get isLog => kind == 'log';
}

/// Parses and delivers shortcut / Back Tap / deep-link invocations.
class QuickInvoke {
  static const _method = MethodChannel('com.qamar.app/quick');
  static const _events = EventChannel('com.qamar.app/quick_events');

  /// `com.qamar.app://quick/ask?q=...` and `.../log`.
  static QuickAction? parseUri(Uri uri) {
    if (uri.scheme != 'com.qamar.app') return null;
    final host = uri.host;
    final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
    String? kind;
    if (host == 'quick' && segments.isNotEmpty) {
      kind = segments.first;
    } else if (host == 'ask' || host == 'log') {
      kind = host;
    } else if (segments.length >= 2 && segments[0] == 'quick') {
      kind = segments[1];
    }
    if (kind != 'ask' && kind != 'log') return null;
    final text = uri.queryParameters['q'] ?? uri.queryParameters['text'];
    return QuickAction(kind: kind!, text: (text == null || text.trim().isEmpty) ? null : text.trim());
  }

  static QuickAction? parseMap(dynamic raw) {
    if (raw is! Map) return null;
    final kind = raw['action']?.toString() ?? raw['kind']?.toString();
    if (kind != 'ask' && kind != 'log') return null;
    final text = raw['text']?.toString() ?? raw['q']?.toString();
    return QuickAction(kind: kind!, text: (text == null || text.trim().isEmpty) ? null : text.trim());
  }

  /// Applies the action to [state]: opens Ask Qamar, optionally starts listening.
  static void apply(AppState state, QuickAction action) {
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

  static Stream<QuickAction> events() {
    return _events.receiveBroadcastStream().map(parseMap).where((a) => a != null).cast<QuickAction>();
  }
}
