import 'package:shared_preferences/shared_preferences.dart';

/// Preferences that belong to the phone, not the account: whether this
/// device has been shown the orb's three gestures, which digits it draws.
/// They are not profile data — a new phone starts fresh, and a linked account
/// does not drag another device's choices along.
abstract class DevicePrefs {
  Future<bool?> getBool(String key);
  Future<void> setBool(String key, bool value);
}

class SharedDevicePrefs implements DevicePrefs {
  @override
  Future<bool?> getBool(String key) async => (await SharedPreferences.getInstance()).getBool(key);

  @override
  Future<void> setBool(String key, bool value) async {
    await (await SharedPreferences.getInstance()).setBool(key, value);
  }
}

/// In memory. Tests, and any platform without a preference store.
class MemoryDevicePrefs implements DevicePrefs {
  final Map<String, bool> _bools = {};

  @override
  Future<bool?> getBool(String key) async => _bools[key];

  @override
  Future<void> setBool(String key, bool value) async => _bools[key] = value;
}
