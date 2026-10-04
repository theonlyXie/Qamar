import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

/// Product analytics, behind a seam and behind consent.
///
/// Nothing here runs until the person has said yes to service improvement
/// in the consultation, and it stops the moment they say no. What goes
/// through is the blueprint's kill metrics and the handful of events that
/// explain them: names, a few small enums, a count, a duration. No body
/// data, no meal text, no photo, no email — the account id is the only
/// identifier, and it is the same opaque id the database already uses.
abstract class Analytics {
  /// Turns collection on. [userId] is the account id, or null when the app
  /// is running without one — then the SDK's own anonymous id is used.
  Future<void> enable(String? userId);

  /// Stops collection. Nothing leaves the phone again until [enable].
  Future<void> disable();

  Future<void> track(String event, Map<String, Object> props);

  Future<void> screen(String name);
}

/// PostHog. The SDK is not even initialised until the first [enable], so a
/// person who never consents never has it running.
class PosthogAnalytics implements Analytics {
  final String apiKey;
  final String host;
  bool _ready = false;
  bool _on = false;

  PosthogAnalytics({required this.apiKey, required this.host});

  @override
  Future<void> enable(String? userId) async {
    try {
      if (!_ready) {
        final config = PostHogConfig(apiKey)
          ..host = host
          // Flags are not used yet; skip the request on every launch.
          ..preloadFeatureFlags = false
          ..sendFeatureFlagEvents = false
          ..surveys = false
          ..sessionReplay = false;
        await Posthog().setup(config);
        _ready = true;
      } else if (!_on) {
        await Posthog().enable();
      }
      _on = true;
      if (userId != null) await Posthog().identify(userId: userId);
    } catch (e) {
      debugPrint('Qamar analytics: $e');
    }
  }

  @override
  Future<void> disable() async {
    if (!_ready || !_on) return;
    _on = false;
    try {
      await Posthog().disable();
    } catch (e) {
      debugPrint('Qamar analytics: $e');
    }
  }

  @override
  Future<void> track(String event, Map<String, Object> props) async {
    if (!_on) return;
    try {
      await Posthog().capture(eventName: event, properties: props);
    } catch (e) {
      debugPrint('Qamar analytics: $e');
    }
  }

  @override
  Future<void> screen(String name) async {
    if (!_on) return;
    try {
      await Posthog().screen(screenName: name);
    } catch (e) {
      debugPrint('Qamar analytics: $e');
    }
  }
}

/// Records what would have been sent. Tests, and any build without a key.
class MemoryAnalytics implements Analytics {
  final List<String?> enabledFor = [];
  int disables = 0;
  final List<({String name, Map<String, Object> props})> events = [];
  final List<String> screens = [];
  bool on = false;

  @override
  Future<void> enable(String? userId) async {
    enabledFor.add(userId);
    on = true;
  }

  @override
  Future<void> disable() async {
    disables++;
    on = false;
  }

  @override
  Future<void> track(String event, Map<String, Object> props) async {
    if (!on) return;
    events.add((name: event, props: Map.unmodifiable(props)));
  }

  @override
  Future<void> screen(String name) async {
    if (on) screens.add(name);
  }

  /// The events with this name, oldest first.
  List<Map<String, Object>> named(String name) => [for (final e in events) if (e.name == name) e.props];
}
