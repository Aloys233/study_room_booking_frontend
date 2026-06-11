import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_models.dart';

abstract class CredentialsStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureCredentialsStorage implements CredentialsStorage {
  SecureCredentialsStorage({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) {
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) {
    return _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) {
    return _storage.delete(key: key);
  }
}

class AuthSessionStore {
  AuthSessionStore({
    Future<SharedPreferences>? preferences,
    CredentialsStorage? credentialsStorage,
  }) : _preferences = preferences ?? SharedPreferences.getInstance(),
       _credentialsStorage =
           credentialsStorage ?? SecureCredentialsStorage();

  static const _sessionKey = 'auth.loginSession';
  static const _rememberedCredentialsKey = 'auth.rememberedCredentials';

  final Future<SharedPreferences> _preferences;
  final CredentialsStorage _credentialsStorage;

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

  Future<RememberedCredentials?> loadRememberedCredentials() async {
    final encoded = await _credentialsStorage.read(_rememberedCredentialsKey);
    if (encoded == null || encoded.trim().isEmpty) {
      await _clearLegacyRememberedCredentials();
      return null;
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is Map<String, dynamic>) {
        await _clearLegacyRememberedCredentials();
        return RememberedCredentials.fromJson(decoded);
      }
    } on FormatException {
      await clearRememberedCredentials();
      return null;
    } on TypeError {
      await clearRememberedCredentials();
      return null;
    }

    await clearRememberedCredentials();
    return null;
  }

  Future<void> saveRememberedCredentials(
    RememberedCredentials credentials,
  ) async {
    await _credentialsStorage.write(
      _rememberedCredentialsKey,
      jsonEncode(credentials.toJson()),
    );
    await _clearLegacyRememberedCredentials();
  }

  Future<void> clearSession() async {
    final preferences = await _preferences;
    await preferences.remove(_sessionKey);
  }

  Future<void> clearRememberedCredentials() async {
    await _credentialsStorage.delete(_rememberedCredentialsKey);
    await _clearLegacyRememberedCredentials();
  }

  Future<void> _clearLegacyRememberedCredentials() async {
    final preferences = await _preferences;
    await preferences.remove(_rememberedCredentialsKey);
  }
}
