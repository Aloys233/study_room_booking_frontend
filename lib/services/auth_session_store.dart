import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_models.dart';

class AuthSessionStore {
  AuthSessionStore({Future<SharedPreferences>? preferences})
    : _preferences = preferences ?? SharedPreferences.getInstance();

  static const _sessionKey = 'auth.loginSession';

  final Future<SharedPreferences> _preferences;

  Future<LoginSession?> loadSession() async {
    final preferences = await _preferences;
    final encoded = preferences.getString(_sessionKey);
    if (encoded == null || encoded.trim().isEmpty) {
      return null;
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map<String, dynamic>) {
        return LoginSession.fromJson(decoded);
      }
    } on FormatException {
      await clearSession();
      return null;
    } on TypeError {
      await clearSession();
      return null;
    }

    await clearSession();
    return null;
  }

  Future<void> saveSession(LoginSession session) async {
    final preferences = await _preferences;
    await preferences.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  Future<void> clearSession() async {
    final preferences = await _preferences;
    await preferences.remove(_sessionKey);
  }
}
