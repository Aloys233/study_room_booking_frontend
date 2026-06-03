import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_room_booking_frontend/models/auth_models.dart';
import 'package:study_room_booking_frontend/services/auth_session_store.dart';

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
}
