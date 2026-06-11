import 'package:flutter_test/flutter_test.dart';
import 'package:study_room_booking_frontend/models/booking_models.dart';
import 'package:study_room_booking_frontend/screens/seat_map_layout.dart';

void main() {
  test('small seat maps keep enough viewport height for padded content', () {
    final metrics = computeSeatMapBoardMetrics(
      seats: const [
        SeatMapItem(
          id: 1,
          roomId: 1,
          seatNo: 'A1',
          tags: [],
          status: 'AVAILABLE',
          displayStatus: 'AVAILABLE',
          type: 'SEAT',
          x: 0,
          y: 0,
          w: 1,
          h: 1,
        ),
        SeatMapItem(
          id: 2,
          roomId: 1,
          seatNo: 'A2',
          tags: [],
          status: 'AVAILABLE',
          displayStatus: 'AVAILABLE',
          type: 'SEAT',
          x: 1,
          y: 0,
          w: 1,
          h: 1,
        ),
      ],
      maxWidth: 360,
      compact: true,
    );

    expect(metrics.boardHeight, 54);
    expect(metrics.viewportHeight, 78);
  });

  test('large seat maps still clamp viewport height', () {
    final metrics = computeSeatMapBoardMetrics(
      seats: List.generate(
        64,
        (index) => SeatMapItem(
          id: index + 1,
          roomId: 1,
          seatNo: 'S$index',
          tags: const [],
          status: 'AVAILABLE',
          displayStatus: 'AVAILABLE',
          type: 'SEAT',
          x: (index % 8).toDouble(),
          y: (index ~/ 8).toDouble(),
          w: 1,
          h: 1,
        ),
      ),
      maxWidth: 768,
      compact: false,
    );

    expect(metrics.viewportHeight, 520);
    expect(metrics.initialScale, lessThanOrEqualTo(1));
  });
}
