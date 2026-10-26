import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/user_preferences.dart';

// A remote profile repository can implement this interface later.
abstract interface class PreferencesStore {
  Future<UserPreferences> load();
  Future<void> save(UserPreferences preferences);
}

class LocalPreferencesStore implements PreferencesStore {
  final SharedPreferencesAsync _storage = SharedPreferencesAsync();
  static const storageKey = 'my_closet.preferences.v1';

  @override
  Future<UserPreferences> load() async {
    final value = await _storage.getString(storageKey);
    if (value == null) return const UserPreferences();
    try {
      final decoded = jsonDecode(value);
      return decoded is Map<String, dynamic>
          ? UserPreferences.fromJson(decoded)
          : const UserPreferences();
    } on FormatException {
      return const UserPreferences();
    }
  }

  @override
  Future<void> save(UserPreferences preferences) =>
      _storage.setString(storageKey, jsonEncode(preferences.toJson()));
}
