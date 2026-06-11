import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_room_booking_frontend/services/auth_api.dart';
import 'package:study_room_booking_frontend/services/booking_api.dart';

void main() {
  test('external registration uses documented auth register path', () async {
    late http.BaseRequest captured;
    Map<String, dynamic>? payload;
    final api = AuthApi(
      baseUrl: 'http://api.test',
      client: MockClient.streaming((request, bodyStream) async {
        captured = request;
        payload =
            jsonDecode(await utf8.decodeStream(bodyStream))
                as Map<String, dynamic>;
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'code': 0, 'data': null}))),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.registerStudent(
      email: 'visitor@example.test',
      realName: '校外访客',
      password: 'password',
      code: 'ABC123',
    );

    expect(captured.url.path, '/api/auth/register');
    expect(payload?['code'], 'ABC123');
    expect(payload?.containsKey('turnstileToken'), isFalse);
  });

  test('password reset request uses documented auth path', () async {
    late http.BaseRequest captured;
    Map<String, dynamic>? payload;
    final api = AuthApi(
      baseUrl: 'http://api.test',
      client: MockClient.streaming((request, bodyStream) async {
        captured = request;
        payload =
            jsonDecode(await utf8.decodeStream(bodyStream))
                as Map<String, dynamic>;
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'code': 0, 'data': null}))),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.requestPasswordReset(
      email: 'a@b.test',
      altchaPayload: 'payload',
    );

    expect(captured.url.path, '/api/auth/password-reset/request');
    expect(payload?['email'], 'a@b.test');
    expect(payload?['altchaPayload'], 'payload');
  });

  test('password reset confirm uses documented auth path', () async {
    late http.BaseRequest captured;
    Map<String, dynamic>? payload;
    final api = AuthApi(
      baseUrl: 'http://api.test',
      client: MockClient.streaming((request, bodyStream) async {
        captured = request;
        payload =
            jsonDecode(await utf8.decodeStream(bodyStream))
                as Map<String, dynamic>;
        return http.StreamedResponse(
          Stream.value(utf8.encode(jsonEncode({'code': 0, 'data': null}))),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.confirmPasswordReset(
      email: 'a@b.test',
      code: '123456',
      newPassword: 'password',
      altchaPayload: 'payload',
    );

    expect(captured.url.path, '/api/auth/password-reset/confirm');
    expect(payload?['email'], 'a@b.test');
    expect(payload?['code'], '123456');
    expect(payload?['newPassword'], 'password');
    expect(payload?['altchaPayload'], 'payload');
  });

  test('backend message field is surfaced for business failures', () async {
    final api = AuthApi(
      baseUrl: 'http://api.test',
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({'code': 500, 'message': '人机验证失败'}),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    expect(
      () => api.loginUser(
        loginName: '2024001',
        password: 'bad',
        altchaPayload: 'payload',
      ),
      throwsA(
        isA<AuthApiException>().having(
          (error) => error.message,
          'message',
          '人机验证失败',
        ),
      ),
    );
  });

  test(
    'reservation rules use the authenticated effective-rules path',
    () async {
      late http.BaseRequest captured;
      final api = BookingApi(
        accessToken: 'access-token',
        baseUrl: 'http://api.test',
        client: MockClient((request) async {
          captured = request;
          return http.Response(
            jsonEncode({
              'code': 0,
              'data': {'allowAdvanceReservation': false, 'maxAdvanceDays': 0},
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      final rules = await api.fetchReservationRules();

      expect(captured.url.path, '/api/reservations/rules');
      expect(rules.effectiveAdvanceDays, 0);
    },
  );

  test(
    'waiting queue request supports documented slotId and backend timeSlotId',
    () async {
      Map<String, dynamic>? payload;
      final api = BookingApi(
        accessToken: 'access-token',
        baseUrl: 'http://api.test',
        client: MockClient.streaming((request, bodyStream) async {
          payload =
              jsonDecode(await utf8.decodeStream(bodyStream))
                  as Map<String, dynamic>;
          return http.StreamedResponse(
            Stream.value(
              utf8.encode(
                jsonEncode({
                  'code': 0,
                  'data': {
                    'id': 1,
                    'roomId': 2,
                    'reserveDate': '2026-05-24',
                    'slotId': 3,
                    'queueNo': 1,
                    'status': 'WAITING',
                    'seatTags': <String>[],
                  },
                }),
              ),
            ),
            201,
            headers: {'content-type': 'application/json'},
          );
        }),
      );

      await api.joinWaitingQueue(
        roomId: 2,
        reserveDate: '2026-05-24',
        slotId: 3,
      );

      expect(payload?['slotId'], 3);
      expect(payload?['timeSlotId'], 3);
    },
  );

  test('time slot lookup sends selected reserve date', () async {
    late http.BaseRequest captured;
    final api = BookingApi(
      accessToken: 'access-token',
      baseUrl: 'http://api.test',
      client: MockClient.streaming((request, bodyStream) async {
        captured = request;
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({
                'code': 0,
                'data': [
                  {
                    'id': 1,
                    'slotName': '上午',
                    'startTime': '08:00:00',
                    'endTime': '10:00:00',
                    'sortOrder': 1,
                    'status': true,
                  },
                ],
              }),
            ),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final slots = await api.fetchTimeSlots(reserveDate: '2026-05-26');

    expect(captured.url.path, '/api/time-slots');
    expect(captured.url.queryParameters['status'], 'true');
    expect(captured.url.queryParameters['reserveDate'], '2026-05-26');
    expect(slots.single.label, '上午 08:00:00-10:00:00');
  });

  test('delete APIs do not require a structured data body', () async {
    final api = BookingApi(
      accessToken: 'access-token',
      baseUrl: 'http://api.test',
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(
          Stream.value(
            utf8.encode(
              jsonEncode({'code': 0, 'message': '取消成功', 'data': '取消成功'}),
            ),
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    await api.cancelReservation(1);
    await api.cancelWaiting(2);
    await api.cancelRoomReservation(3);
  });
}
