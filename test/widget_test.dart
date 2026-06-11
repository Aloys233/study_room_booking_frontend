import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:study_room_booking_frontend/main.dart';
import 'package:study_room_booking_frontend/models/auth_models.dart';
import 'package:study_room_booking_frontend/models/booking_models.dart';
import 'package:study_room_booking_frontend/screens/home_page.dart';
import 'package:study_room_booking_frontend/screens/seat_map_layout.dart';
import 'package:study_room_booking_frontend/services/auth_api.dart';
import 'package:study_room_booking_frontend/services/booking_api.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('shows authentication entry', (WidgetTester tester) async {
    await tester.pumpWidget(const StudyRoomBookingApp());
    await tester.pump();

    expect(find.text('账号登录'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
    expect(find.text('管理员'), findsNothing);

    await tester.tap(find.text('注册'));
    await tester.pump();

    expect(find.text('校外人员注册'), findsOneWidget);
    expect(find.text('真实姓名'), findsOneWidget);
  });

  testWidgets('does not select the first available seat by default', (
    WidgetTester tester,
  ) async {
    final user = _studentUser();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          session: LoginSession(accessToken: 'token', user: user),
          onLogout: () {},
          authApi: _FakeAuthApi(user),
          bookingApi: _FakeBookingApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final submitButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '提交预约'),
    );
    expect(submitButton.onPressed, isNull);
  });

  testWidgets('seat map does not allow zooming out below fitted scale', (
    WidgetTester tester,
  ) async {
    final user = _studentUser();

    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          session: LoginSession(accessToken: 'token', user: user),
          onLogout: () {},
          authApi: _FakeAuthApi(user),
          bookingApi: _FakeBookingApi(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final interactiveViewer = tester.widget<InteractiveViewer>(
      find.byType(InteractiveViewer),
    );
    final expectedMetrics = computeSeatMapBoardMetrics(
      seats: const [
        SeatMapItem(
          id: 11,
          roomId: 1,
          seatNo: 'A1',
          tags: [],
          status: 'NORMAL',
          displayStatus: 'AVAILABLE',
          type: 'SEAT',
          x: 0,
          y: 0,
          w: 1,
          h: 1,
        ),
        SeatMapItem(
          id: 12,
          roomId: 1,
          seatNo: 'A2',
          tags: [],
          status: 'NORMAL',
          displayStatus: 'AVAILABLE',
          type: 'SEAT',
          x: 1,
          y: 0,
          w: 1,
          h: 1,
        ),
      ],
      maxWidth: tester.getSize(find.byType(InteractiveViewer)).width,
      compact: false,
    );

    expect(interactiveViewer.minScale, expectedMetrics.initialScale);
  });
}

UserProfile _studentUser() {
  return const UserProfile(
    id: 1,
    loginName: '20240001',
    userNo: '20240001',
    realName: '测试学生',
    email: 'student@example.test',
    activated: true,
    role: 'STUDENT',
    status: 'NORMAL',
  );
}

class _FakeAuthApi extends AuthApi {
  _FakeAuthApi(this.user) : super(accessToken: 'token');

  final UserProfile user;

  @override
  Future<UserProfile> getCurrentUser() async => user;
}

class _FakeBookingApi extends BookingApi {
  _FakeBookingApi() : super(accessToken: 'token');

  @override
  Future<List<StudyRoom>> fetchRooms() async {
    return const [
      StudyRoom(id: 1, name: '一号自习室', totalSeats: 2, status: 'OPEN'),
    ];
  }

  @override
  Future<List<TimeSlot>> fetchTimeSlots({
    String? reserveDate,
    int? roomId,
  }) async {
    return const [
      TimeSlot(
        id: 1,
        slotName: '全天',
        startTime: '00:00',
        endTime: '23:59',
        sortOrder: 1,
        status: true,
      ),
    ];
  }

  @override
  Future<SystemConfig> fetchSystemConfig() async => SystemConfig.fallback;

  @override
  Future<SystemConfig> fetchReservationRules() async => SystemConfig.fallback;

  @override
  Future<List<ReservationSummary>> fetchReservations() async => const [];

  @override
  Future<List<WaitingQueueEntry>> fetchWaitingQueues() async => const [];

  @override
  Future<List<RoomReservation>> fetchRoomReservations() async => const [];

  @override
  Future<List<SeatMapItem>> fetchSeatMap({
    required int roomId,
    required String reserveDate,
    required int slotId,
  }) async {
    return const [
      SeatMapItem(
        id: 11,
        roomId: 1,
        seatNo: 'A1',
        tags: [],
        status: 'NORMAL',
        displayStatus: 'AVAILABLE',
        type: 'SEAT',
        x: 0,
        y: 0,
        w: 1,
        h: 1,
      ),
      SeatMapItem(
        id: 12,
        roomId: 1,
        seatNo: 'A2',
        tags: [],
        status: 'NORMAL',
        displayStatus: 'AVAILABLE',
        type: 'SEAT',
        x: 1,
        y: 0,
        w: 1,
        h: 1,
      ),
    ];
  }
}
