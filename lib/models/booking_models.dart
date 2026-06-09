class StudyRoom {
  const StudyRoom({
    required this.id,
    required this.name,
    required this.totalSeats,
    required this.status,
    this.campus,
    this.building,
    this.floor,
    this.locationDetail,
    this.description,
    this.openWeekdays = const [],
    this.openSchedule = const [],
  });

  final int id;
  final String name;
  final String? campus;
  final String? building;
  final String? floor;
  final String? locationDetail;
  final int totalSeats;
  final String status;
  final String? description;
  final List<int> openWeekdays;
  final List<RoomOpenSchedule> openSchedule;

  factory StudyRoom.fromJson(Map<String, dynamic> json) {
    return StudyRoom(
      id: _asInt(json['id']),
      name: json['name'] as String,
      campus: json['campus'] as String?,
      building: json['building'] as String?,
      floor: json['floor'] as String?,
      locationDetail: json['locationDetail'] as String?,
      totalSeats: _asInt(json['totalSeats']),
      status: json['status'] as String,
      description: json['description'] as String?,
      openWeekdays: (json['openWeekdays'] as List<dynamic>? ?? const [])
          .map(_asInt)
          .toList(),
      openSchedule: (json['openSchedule'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(RoomOpenSchedule.fromJson)
          .toList(),
    );
  }

  String get location {
    return [
      campus,
      building,
      floor,
      locationDetail,
    ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' / ');
  }
}

class RoomOpenSchedule {
  const RoomOpenSchedule({required this.weekday, required this.slotIds});

  final int weekday;
  final List<int> slotIds;

  factory RoomOpenSchedule.fromJson(Map<String, dynamic> json) {
    return RoomOpenSchedule(
      weekday: _asInt(json['weekday']),
      slotIds: (json['slotIds'] as List<dynamic>? ?? const [])
          .map(_asInt)
          .toList(),
    );
  }
}

class TimeSlot {
  const TimeSlot({
    required this.id,
    required this.slotName,
    required this.startTime,
    required this.endTime,
    required this.sortOrder,
    required this.status,
  });

  final int id;
  final String slotName;
  final String startTime;
  final String endTime;
  final int sortOrder;
  final bool status;

  factory TimeSlot.fromJson(Map<String, dynamic> json) {
    return TimeSlot(
      id: _asInt(json['id']),
      slotName: json['slotName'] as String,
      startTime: json['startTime'] as String,
      endTime: json['endTime'] as String,
      sortOrder: _asInt(json['sortOrder']),
      status: json['status'] as bool,
    );
  }

  String get label => '$slotName $startTime-$endTime';
}

class Seat {
  const Seat({
    required this.id,
    required this.roomId,
    required this.seatNo,
    required this.tags,
    required this.status,
    this.seatType,
  });

  final int id;
  final int roomId;
  final String seatNo;
  final String? seatType;
  final List<String> tags;
  final String status;

  factory Seat.fromJson(Map<String, dynamic> json) {
    return Seat(
      id: _asInt(json['id']),
      roomId: _asInt(json['roomId']),
      seatNo: json['seatNo'] as String,
      seatType: json['seatType'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      status: json['status'] as String,
    );
  }
}

class SeatMapItem extends Seat {
  const SeatMapItem({
    required super.id,
    required super.roomId,
    required super.seatNo,
    required super.tags,
    required super.status,
    required this.displayStatus,
    required this.type,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.label,
    super.seatType,
  });

  final String displayStatus;
  final String type;
  final double x;
  final double y;
  final double w;
  final double h;
  final String? label;

  bool get isSeat => type == 'SEAT';
  bool get isAvailable => isSeat && displayStatus == 'AVAILABLE' && id > 0;

  factory SeatMapItem.fromJson(Map<String, dynamic> json) {
    final type = json['type'] as String? ?? 'SEAT';
    return SeatMapItem(
      id: _asOptionalInt(json['id']) ?? 0,
      roomId: _asOptionalInt(json['roomId']) ?? 0,
      seatNo: json['seatNo'] as String? ?? '',
      seatType: json['seatType'] as String?,
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      status: json['status'] as String? ?? type,
      displayStatus: json['displayStatus'] as String? ?? type,
      type: type,
      x: _asDouble(json['x']),
      y: _asDouble(json['y']),
      w: _asDouble(json['w'], fallback: 1),
      h: _asDouble(json['h'], fallback: 1),
      label: json['label'] as String?,
    );
  }
}

class ReservationSummary {
  const ReservationSummary({
    required this.id,
    required this.roomId,
    required this.roomName,
    required this.seatId,
    required this.seatNo,
    required this.reserveDate,
    required this.slotId,
    required this.status,
    this.slotName,
    this.reserveStartAt,
    this.reserveEndAt,
  });

  final int id;
  final int roomId;
  final String roomName;
  final int seatId;
  final String seatNo;
  final String reserveDate;
  final int slotId;
  final String? slotName;
  final String status;
  final String? reserveStartAt;
  final String? reserveEndAt;

  factory ReservationSummary.fromJson(Map<String, dynamic> json) {
    return ReservationSummary(
      id: _asInt(json['id']),
      roomId: _asInt(json['roomId']),
      roomName: json['roomName'] as String,
      seatId: _asInt(json['seatId']),
      seatNo: json['seatNo'] as String,
      reserveDate: json['reserveDate'] as String,
      slotId: _asInt(json['slotId']),
      slotName: json['slotName'] as String?,
      status: json['status'] as String,
      reserveStartAt: json['reserveStartAt'] as String?,
      reserveEndAt: json['reserveEndAt'] as String?,
    );
  }
}

class WaitingQueueEntry {
  const WaitingQueueEntry({
    required this.id,
    required this.roomId,
    required this.reserveDate,
    required this.timeSlotId,
    required this.status,
    this.roomName,
    this.campus,
    this.building,
    this.slotName,
    this.startTime,
    this.endTime,
  });

  final int id;
  final int roomId;
  final String? roomName;
  final String? campus;
  final String? building;
  final String reserveDate;
  final int timeSlotId;
  final String? slotName;
  final String? startTime;
  final String? endTime;
  final String status;

  factory WaitingQueueEntry.fromJson(Map<String, dynamic> json) {
    return WaitingQueueEntry(
      id: _asInt(json['id']),
      roomId: _asInt(json['roomId']),
      roomName: json['roomName'] as String?,
      campus: json['campus'] as String?,
      building: json['building'] as String?,
      reserveDate: json['reserveDate'] as String,
      timeSlotId: _asInt(json['timeSlotId'] ?? json['slotId']),
      slotName: json['slotName'] as String?,
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
      status: json['status'] as String,
    );
  }

  String get location => [
    campus,
    building,
  ].whereType<String>().where((part) => part.trim().isNotEmpty).join(' / ');
}

class RoomReservation {
  const RoomReservation({
    required this.id,
    required this.roomId,
    required this.purpose,
    required this.reserveDate,
    required this.slotId,
    required this.status,
    this.roomName,
    this.slotName,
    this.startTime,
    this.endTime,
    this.remark,
  });

  final int id;
  final int roomId;
  final String? roomName;
  final String purpose;
  final String reserveDate;
  final int slotId;
  final String? slotName;
  final String? startTime;
  final String? endTime;
  final String status;
  final String? remark;

  factory RoomReservation.fromJson(Map<String, dynamic> json) {
    return RoomReservation(
      id: _asInt(json['id']),
      roomId: _asInt(json['roomId']),
      roomName: json['roomName'] as String?,
      purpose: json['purpose'] as String,
      reserveDate: json['reserveDate'] as String,
      slotId: _asInt(json['slotId']),
      slotName: json['slotName'] as String?,
      startTime: json['startTime'] as String?,
      endTime: json['endTime'] as String?,
      status: json['status'] as String,
      remark: json['remark'] as String?,
    );
  }
}

class SystemConfig {
  const SystemConfig({
    required this.allowAdvanceReservation,
    required this.maxAdvanceDays,
    required this.allowWaiting,
    this.maxDailyReservation,
    this.maxActiveReservation,
    this.checkinTimeoutMinutes,
    this.waitingConfirmMinutes,
    this.cancelDeadlineMinutes,
  });

  final bool allowAdvanceReservation;
  final int maxAdvanceDays;
  final bool allowWaiting;
  final int? maxDailyReservation;
  final int? maxActiveReservation;
  final int? checkinTimeoutMinutes;
  final int? waitingConfirmMinutes;
  final int? cancelDeadlineMinutes;

  /// 配置加载失败时的保守默认：仅当天、允许候补。后端仍会做最终校验。
  static const fallback = SystemConfig(
    allowAdvanceReservation: false,
    maxAdvanceDays: 0,
    allowWaiting: true,
  );

  /// 实际可提前预约的天数（关闭提前预约或非法值时为 0，即仅当天）。
  int get effectiveAdvanceDays {
    if (!allowAdvanceReservation || maxAdvanceDays < 0) {
      return 0;
    }
    return maxAdvanceDays;
  }

  factory SystemConfig.fromJson(Map<String, dynamic> json) {
    return SystemConfig(
      allowAdvanceReservation:
          json['allowAdvanceReservation'] as bool? ?? false,
      maxAdvanceDays: _asOptionalInt(json['maxAdvanceDays']) ?? 0,
      allowWaiting: json['allowWaiting'] as bool? ?? true,
      maxDailyReservation: _asOptionalInt(json['maxDailyReservation']),
      maxActiveReservation: _asOptionalInt(json['maxActiveReservation']),
      checkinTimeoutMinutes: _asOptionalInt(json['checkinTimeoutMinutes']),
      waitingConfirmMinutes: _asOptionalInt(json['waitingConfirmMinutes']),
      cancelDeadlineMinutes: _asOptionalInt(json['cancelDeadlineMinutes']),
    );
  }
}

int _asInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  throw FormatException('Expected integer, got $value');
}

int? _asOptionalInt(Object? value) {
  if (value == null) {
    return null;
  }
  return _asInt(value);
}

double _asDouble(Object? value, {double fallback = 0}) {
  if (value is num) {
    return value.toDouble();
  }
  return fallback;
}
