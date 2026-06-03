import 'package:flutter_test/flutter_test.dart';

import 'package:study_room_booking_frontend/main.dart';

void main() {
  testWidgets('shows authentication entry', (WidgetTester tester) async {
    await tester.pumpWidget(const StudyRoomBookingApp());

    expect(find.text('账号登录'), findsOneWidget);
    expect(find.text('注册'), findsOneWidget);
    expect(find.text('管理员'), findsNothing);

    await tester.tap(find.text('注册'));
    await tester.pump();

    expect(find.text('校外人员注册'), findsOneWidget);
    expect(find.text('真实姓名'), findsOneWidget);
  });
}
