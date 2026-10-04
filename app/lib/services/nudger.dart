import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/nudge.dart';

/// The phone's notification schedule, behind a seam.
///
/// The app decides *what* and *when* (see NudgeSchedule); this only puts it
/// on the phone, asks the OS for permission at the moment the app chooses,
/// and reports taps. Null in tests and wherever there is no notification
/// system, so AppState behaves the same with or without one.
abstract class Nudger {
  /// Asks the OS. True only when the person actually allowed it.
  Future<bool> requestPermission();

  /// Cancels whatever is scheduled and schedules exactly [nudges].
  Future<void> replaceAll(List<Nudge> nudges, {required bool ar});

  /// Payloads of notifications the person tapped while the app was alive.
  Stream<String> get taps;

  /// The payload the app was launched from, once, or null.
  Future<String?> takeLaunchPayload();
}

/// In memory: records what would have reached the phone.
class MemoryNudger implements Nudger {
  bool grant = true;
  int permissionAsks = 0;
  List<Nudge> scheduled = const [];
  bool? lastAr;
  String? launchPayload;
  final _taps = StreamController<String>.broadcast();

  @override
  Future<bool> requestPermission() async {
    permissionAsks++;
    return grant;
  }

  @override
  Future<void> replaceAll(List<Nudge> nudges, {required bool ar}) async {
    scheduled = List.unmodifiable(nudges);
    lastAr = ar;
  }

  @override
  Stream<String> get taps => _taps.stream;

  void tap(String payload) => _taps.add(payload);

  @override
  Future<String?> takeLaunchPayload() async {
    final p = launchPayload;
    launchPayload = null;
    return p;
  }
}

/// flutter_local_notifications, one channel, inexact timing.
///
/// Inexact on purpose: a question about lunch does not need an exact alarm,
/// and asking Android for SCHEDULE_EXACT_ALARM is one more permission prompt
/// the blueprint forbids. Each nudge is a one-shot at an absolute instant
/// (its local time converted to UTC), so no time-zone database lookup is
/// needed on the phone; the schedule is rebuilt every time the day changes.
class LocalNudger implements Nudger {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final _taps = StreamController<String>.broadcast();
  bool _ready = false;
  bool _initTried = false;

  static const _channelId = 'qamar_nudges';

  Future<bool> _init() async {
    if (_ready || _initTried) return _ready;
    _initTried = true;
    try {
      tzdata.initializeTimeZones();
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Permission is asked later, after the plan reveal, with the
          // reason on screen — not at initialisation.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
        onDidReceiveNotificationResponse: (response) {
          final p = response.payload;
          if (p != null && p.isNotEmpty) _taps.add(p);
        },
      );
      _ready = ok ?? false;
    } catch (e) {
      debugPrint('Qamar nudges: notifications unavailable — $e');
      _ready = false;
    }
    return _ready;
  }

  @override
  Future<bool> requestPermission() async {
    if (!await _init()) return false;
    try {
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        return await android?.requestNotificationsPermission() ?? false;
      }
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
        return await ios?.requestPermissions(alert: true, sound: true, badge: false) ?? false;
      }
    } catch (e) {
      debugPrint('Qamar nudges: permission request failed — $e');
    }
    return false;
  }

  @override
  Future<void> replaceAll(List<Nudge> nudges, {required bool ar}) async {
    if (!await _init()) return;
    try {
      await _plugin.cancelAll();
      for (final n in nudges) {
        await _plugin.zonedSchedule(
          id: n.id,
          title: ar ? 'قمر' : 'Qamar',
          body: n.text(ar: ar),
          scheduledDate: tz.TZDateTime.from(n.at.toUtc(), tz.UTC),
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channelId,
              ar ? 'أسئلة قمر' : 'Qamar’s questions',
              channelDescription: ar
                  ? 'سؤال في مواعيد أكلك. مرتين في اليوم كحد أقصى.'
                  : 'A question at your meal times. Two a day at most.',
              importance: Importance.defaultImportance,
              priority: Priority.defaultPriority,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: n.payload,
        );
      }
    } catch (e) {
      debugPrint('Qamar nudges: schedule failed — $e');
    }
  }

  @override
  Stream<String> get taps => _taps.stream;

  @override
  Future<String?> takeLaunchPayload() async {
    if (!await _init()) return null;
    try {
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      return details?.notificationResponse?.payload;
    } catch (_) {
      return null;
    }
  }
}
