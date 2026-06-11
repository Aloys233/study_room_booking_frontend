import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_room_booking_frontend/models/auth_models.dart';
import 'package:study_room_booking_frontend/services/auth_session_store.dart';

class InMemoryCredentialsStorage implements CredentialsStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }

  @override
  Future<String?> read(String key) async {
    return _values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('saves and reloads login session for app restarts', () async {
    final store = AuthSessionStore();
    const session = LoginSession(
      accessToken: 'access-token',
      user: UserProfile(
        id: 1,
        loginName: '2024001',
        realName: '张三',
        role: 'STUDENT',
        status: 'ACTIVE',
        activated: true,
        email: 'student@example.test',
      ),
    );

    await store.saveSession(session);

    final restored = await AuthSessionStore().loadSession();
    expect(restored?.accessToken, 'access-token');
    expect(restored?.user.loginName, '2024001');
    expect(restored?.user.realName, '张三');
  });

  test('clears malformed stored session', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.auth.loginSession': '{not-json',
    });
    final store = AuthSessionStore();

    expect(await store.loadSession(), isNull);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth.loginSession'), isNull);
  });

  test('saves and reloads remembered credentials', () async {
    final secureStorage = InMemoryCredentialsStorage();
    final store = AuthSessionStore(credentialsStorage: secureStorage);
    const credentials = RememberedCredentials(
      loginName: '2024001',
      password: 'secret123',
    );

    await store.saveRememberedCredentials(credentials);

    final restored = await AuthSessionStore(
      credentialsStorage: secureStorage,
    ).loadRememberedCredentials();
    expect(restored?.loginName, '2024001');
    expect(restored?.password, 'secret123');

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth.rememberedCredentials'), isNull);
  });

  test('clears malformed remembered credentials', () async {
    final secureStorage = InMemoryCredentialsStorage();
    await secureStorage.write('auth.rememberedCredentials', '{not-json');
    final store = AuthSessionStore(credentialsStorage: secureStorage);

    expect(await store.loadRememberedCredentials(), isNull);

    expect(await secureStorage.read('auth.rememberedCredentials'), isNull);
  });

  test('clears legacy plaintext remembered credentials from shared preferences', () async {
    SharedPreferences.setMockInitialValues({
      'flutter.auth.rememberedCredentials':
          '{"loginName":"2024001","password":"plaintext"}',
    });
    final secureStorage = InMemoryCredentialsStorage();
    final store = AuthSessionStore(credentialsStorage: secureStorage);

    expect(await store.loadRememberedCredentials(), isNull);

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('auth.rememberedCredentials'), isNull);
  });
}
