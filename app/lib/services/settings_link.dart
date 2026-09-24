import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

/// Whether this phone can be taken straight to Qamar's page in Settings.
/// An iPhone can ('app-settings:'); Android has no URL for it that the app
/// can open, so there the words say where to go instead.
bool get canOpenAppSettings => !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

/// Opens Qamar's page in the phone's Settings, where the camera is allowed.
Future<bool> openAppSettings() => launchUrl(Uri.parse('app-settings:'));
