import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/booking_models.dart';
import 'auth_api.dart';

class BookingApi {
  BookingApi({
    required String accessToken,
    http.Client? client,
    String? baseUrl,
  }) : _accessToken = accessToken,
       _client = client ?? http.Client(),
       _baseUrl = Uri.parse(
         baseUrl ??
             const String.fromEnvironment(
               'API_BASE_URL',
               defaultValue: 'http://localhost:8080',
             ),
       );

  final String _accessToken;
  final http.Client _client;
  final Uri _baseUrl;

  Future<List<StudyRoom>> fetchRooms() async {
    final data = await _get('/api/rooms', query: {'status': 'OPEN'});
    return _list(data, StudyRoom.fromJson);
  }

  Future<List<TimeSlot>> fetchTimeSlots({
    String? reserveDate,
    int? roomId,
  }) async {
    final data = await _get(
      '/api/time-slots',
      query: {
        'status': 'true',
        'reserveDate': ?reserveDate,
        'roomId': ?roomId?.toString(),
      },
    );
    final slots = _list(data, TimeSlot.fromJson);
    slots.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return slots;
  }

  Future<SystemConfig> fetchSystemConfig() async {
    try {
      final data = await _get('/api/system-config');
      if (data is Map<String, dynamic>) {
        return SystemConfig.fromJson(data);
      }
    } on AuthApiException {
      // 配置端点不可用（如后端未更新）时退回保守默认，不阻断主流程。
    }
    return SystemConfig.fallback;
  }

  Future<SystemConfig> fetchReservationRules() async {
    try {
      final data = await _get('/api/reservations/rules');
      if (data is Map<String, dynamic>) {
        return SystemConfig.fromJson(data);
      }
    } on AuthApiException {
      // 规则端点不可用（如后端未更新）时仅显示当天。
    }
    return SystemConfig.fallback;
  }

  Future<List<SeatMapItem>> fetchSeatMap({
    required int roomId,
    required String reserveDate,
    required int slotId,
  }) async {
    final data = await _get(
      '/api/rooms/$roomId/seat-map',
      query: {'reserveDate': reserveDate, 'slotId': '$slotId'},
    );
    final map = data as Map<String, dynamic>;
    final items = _list(map['items'], SeatMapItem.fromJson);
    items.sort((a, b) {
      final rowCompare = a.y.compareTo(b.y);
      if (rowCompare != 0) return rowCompare;
      return a.x.compareTo(b.x);
    });
    return items;
  }

  Future<List<ReservationSummary>> fetchReservations() async {
    final data = await _get(
      '/api/reservations',
      query: {'page': '1', 'pageSize': '50'},
    );
    final page = data as Map<String, dynamic>;
    return _list(page['items'], ReservationSummary.fromJson);
  }

  Future<ReservationSummary> createReservation({
    required int roomId,
    required int seatId,
    required String reserveDate,
    required int slotId,
  }) async {
    final data = await _post(
      '/api/reservations',
      expectedStatus: 201,
      body: {
        'roomId': roomId,
        'seatId': seatId,
        'reserveDate': reserveDate,
        'slotId': slotId,
      },
    );
    return ReservationSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<void> cancelReservation(int reservationId) async {
    await _delete('/api/reservations/$reservationId');
  }

  Future<ReservationSummary> checkInReservation(int reservationId) async {
    final data = await _post(
      '/api/reservations/$reservationId/check-in',
      expectedStatuses: const {200, 201},
      body: {'checkinType': 'MANUAL'},
    );
    return ReservationSummary.fromJson(data as Map<String, dynamic>);
  }

  Future<List<WaitingQueueEntry>> fetchWaitingQueues() async {
    final data = await _get('/api/waiting-queues');
    return _list(data, WaitingQueueEntry.fromJson);
  }

  Future<WaitingQueueEntry> joinWaitingQueue({
    required int roomId,
    required String reserveDate,
    required int slotId,
  }) async {
    final data = await _post(
      '/api/waiting-queues',
      expectedStatus: 201,
      body: {
        'roomId': roomId,
        'reserveDate': reserveDate,
        'slotId': slotId,
        'timeSlotId': slotId,
      },
    );
    return WaitingQueueEntry.fromJson(data as Map<String, dynamic>);
  }

  Future<void> cancelWaiting(int waitingId) async {
    await _delete('/api/waiting-queues/$waitingId');
  }

  Future<void> acceptWaiting(int waitingId) async {
    await _post(
      '/api/waiting-queues/$waitingId/accept',
      expectedStatuses: const {200, 201},
      body: const {},
    );
  }

  Future<List<RoomReservation>> fetchRoomReservations() async {
    final data = await _get('/api/room-reservations');
    return _list(data ?? const [], RoomReservation.fromJson);
  }

  Future<RoomReservation> createRoomReservation({
    required int roomId,
    required String purpose,
    required String reserveDate,
    required int slotId,
    String? remark,
  }) async {
    final data = await _post(
      '/api/room-reservations',
      expectedStatus: 201,
      body: {
        'roomId': roomId,
        'purpose': purpose,
        'reserveDate': reserveDate,
        'slotId': slotId,
        if (remark != null && remark.trim().isNotEmpty) 'remark': remark,
      },
    );
    return RoomReservation.fromJson(data as Map<String, dynamic>);
  }

  Future<void> cancelRoomReservation(int roomReservationId) async {
    await _delete('/api/room-reservations/$roomReservationId');
  }

  Future<Object?> _get(String path, {Map<String, String?> query = const {}}) {
    return _send('GET', path, query: query);
  }

  Future<Object?> _post(
    String path, {
    required Map<String, Object?> body,
    int expectedStatus = 200,
    Set<int>? expectedStatuses,
  }) {
    return _send(
      'POST',
      path,
      body: body,
      expectedStatus: expectedStatus,
      expectedStatuses: expectedStatuses,
    );
  }

  Future<Object?> _delete(String path) {
    return _send('DELETE', path);
  }

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String?> query = const {},
    Map<String, Object?>? body,
    int expectedStatus = 200,
    Set<int>? expectedStatuses,
  }) async {
    final cleanQuery = {
      for (final entry in query.entries)
        if (entry.value != null && entry.value!.isNotEmpty)
          entry.key: entry.value!,
    };
    final uri = _baseUrl.resolve(path).replace(queryParameters: cleanQuery);
    final request = http.Request(method, uri)
      ..headers.addAll({
        'Accept': 'application/json',
        'Authorization': 'Bearer $_accessToken',
        if (body != null) 'Content-Type': 'application/json',
      });
    if (body != null) {
      request.body = jsonEncode(body);
    }

    final streamed = await _client.send(request);
    final response = await http.Response.fromStream(streamed);
    final decoded = _decodeResponse(response);
    final allowedStatuses = expectedStatuses ?? {expectedStatus};
    if (!allowedStatuses.contains(response.statusCode)) {
      throw AuthApiException(_messageFrom(decoded, '请求失败，请稍后重试'));
    }
    final code = decoded['code'];
    if (code != 0) {
      throw AuthApiException(_messageFrom(decoded, '业务处理失败'));
    }
    return decoded['data'];
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final body = utf8.decode(response.bodyBytes);
      if (body.trim().isEmpty) {
        return const {'code': 0};
      }
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } on FormatException {
      throw const AuthApiException('服务器返回格式不正确');
    }
    throw const AuthApiException('服务器返回格式不正确');
  }

  String _messageFrom(Map<String, dynamic> response, String fallback) {
    final msg = response['msg'];
    if (msg is String && msg.trim().isNotEmpty) {
      return msg;
    }
    final message = response['message'];
    return message is String && message.trim().isNotEmpty ? message : fallback;
  }

  List<T> _list<T>(Object? data, T Function(Map<String, dynamic>) fromJson) {
    return (data as List<dynamic>? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(fromJson)
        .toList();
  }
}
