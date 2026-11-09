// lib/models/attendance_record.dart
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

bool _parseBool(dynamic boolData) {
  if (boolData == null) return false;
  if (boolData is bool) return boolData;
  if (boolData is String) return boolData.toLowerCase() == 'true';
  if (boolData is int) return boolData == 1;
  return false;
}

@immutable
class AttendanceRecord {
  final String id;
  final String lectureId;
  final String userId;
  final String studentName;
  final String registrationNumber;
  final DateTime joinedAt;
  final DateTime? checkInTime;
  final bool checkedIn;
  final String? checkedInBy;
  final String? percentage;

  const AttendanceRecord({
    required this.id,
    required this.lectureId,
    required this.userId,
    required this.studentName,
    required this.registrationNumber,
    required this.joinedAt,
    required this.checkedIn,
    this.checkInTime,
    this.checkedInBy,
    this.percentage,
  });

  String get formattedJoinedAt => DateFormat.jm().format(joinedAt.toLocal());
  String? get formattedCheckInTime => checkInTime == null ? null : DateFormat.jm().format(checkInTime!.toLocal());

  factory AttendanceRecord.fromApiJson(Map<String, dynamic> json) {
    String? percentageValue;
    if (json['percentage'] != null) {
      percentageValue = json['percentage'].toString();
    }
    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      if (v is String) return DateTime.tryParse(v);
      return null;
    }
    return AttendanceRecord(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      lectureId: json['lectureId'] as String? ?? '',
      userId: json['userId'] as String? ?? '',
      studentName: json['studentName'] as String? ?? 'Unknown Student',
      registrationNumber: json['registrationNumber'] as String? ?? 'N/A',
      joinedAt: parseDt(json['joinedAt']) ?? DateTime(1970),
      checkedIn: _parseBool(json['checkedIn']),
      checkInTime: parseDt(json['checkInTime']),
      checkedInBy: json['checkedInBy'] as String?,
      percentage: percentageValue,
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      'lectureId': lectureId,
      'userId': userId,
      'studentName': studentName,
      'registrationNumber': registrationNumber,
      'joinedAt': joinedAt.toIso8601String(),
      'checkedIn': checkedIn,
      'checkInTime': checkInTime?.toIso8601String(),
      'checkedInBy': checkedInBy,
    };
  }

  AttendanceRecord copyWith({
    String? id,
    String? lectureId,
    String? userId,
    String? studentName,
    String? registrationNumber,
    DateTime? joinedAt,
    bool? checkedIn,
    DateTime? checkInTime,
    String? checkedInBy,
    bool setCheckInTimeNull = false,
    bool setCheckedInByNull = false,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      lectureId: lectureId ?? this.lectureId,
      userId: userId ?? this.userId,
      studentName: studentName ?? this.studentName,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      joinedAt: joinedAt ?? this.joinedAt,
      checkedIn: checkedIn ?? this.checkedIn,
      checkInTime: setCheckInTimeNull ? null : (checkInTime ?? this.checkInTime),
      checkedInBy: setCheckedInByNull ? null : (checkedInBy ?? this.checkedInBy),
    );
  }

  @override
  String toString() {
    return 'AttendanceRecord(id: $id, lectureId: $lectureId, userId: $userId, studentName: $studentName, regNo: $registrationNumber, joinedAt: $joinedAt, checkedIn: $checkedIn, checkInTime: $checkInTime, checkedInBy: $checkedInBy)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AttendanceRecord &&
        other.id == id &&
        other.lectureId == lectureId &&
        other.userId == userId &&
        other.studentName == studentName &&
        other.registrationNumber == registrationNumber &&
        other.joinedAt == joinedAt &&
        other.checkedIn == checkedIn &&
        other.checkInTime == checkInTime &&
        other.checkedInBy == checkedInBy;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      lectureId.hashCode ^
      userId.hashCode ^
      studentName.hashCode ^
      registrationNumber.hashCode ^
      joinedAt.hashCode ^
      checkedIn.hashCode ^
      checkInTime.hashCode ^
      checkedInBy.hashCode;
}
