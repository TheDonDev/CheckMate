// lib/models/attendance_record.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // For immutable annotation
import 'package:intl/intl.dart'; // For formatting dates/times in UI if needed

// Helper function to parse Timestamps from various formats (API/Firestore)
Timestamp? _parseTimestamp(dynamic timestampData) {
  if (timestampData == null) return null;
  if (timestampData is Timestamp) return timestampData;
  if (timestampData is String) {
    try {
      // Try parsing as ISO 8601 string
      return Timestamp.fromDate(DateTime.parse(timestampData).toUtc());
    } catch (e) {
      print("Error parsing timestamp string: $timestampData, Error: $e");
      return null;
    }
  } else if (timestampData is Map && timestampData.containsKey('_seconds')) {
    // Firestore-like map { _seconds: ..., _nanoseconds: ... }
    return Timestamp(timestampData['_seconds'], timestampData['_nanoseconds'] ?? 0);
  } else if (timestampData is int) {
    // Assuming milliseconds since epoch if it's an int
    try {
      return Timestamp.fromMillisecondsSinceEpoch(timestampData);
    } catch (e) {
       print("Error parsing timestamp int: $timestampData, Error: $e");
       return null;
    }
  }
  print("Unrecognized timestamp format: $timestampData");
  return null;
}

// Helper function to convert Timestamp/DateTime to ISO 8601 UTC string for API
String? _toIso8601String(dynamic dateOrTimestamp) {
  if (dateOrTimestamp == null) return null;
  DateTime dateTime;
  if (dateOrTimestamp is Timestamp) { dateTime = dateOrTimestamp.toDate(); }
  else if (dateOrTimestamp is DateTime) { dateTime = dateOrTimestamp; }
  else { return null; }
  return dateTime.toUtc().toIso8601String(); // Use UTC for consistency
}

@immutable // Mark class as immutable
class AttendanceRecord {
  final String id; // Firestore document ID or API ID
  final String lectureId;
  final String userId; 
  final String studentName; 
  final String registrationNumber;
  final Timestamp joinedAt; // When the student joined the lecture
  final Timestamp? checkInTime; 
  final bool checkedIn; 
  final String? checkedInBy; // Lecturer's User ID who checked them in

  const AttendanceRecord({ // Use const constructor
    required this.id,
    required this.lectureId,
    required this.userId, 
    required this.studentName,
    required this.registrationNumber,
    required this.joinedAt,
    required this.checkedIn, 
    this.checkInTime, 
    this.checkedInBy,
  });

  // --- Formatting Getters (Optional, for UI) ---
  String get formattedJoinedAt => DateFormat.jm().format(joinedAt.toDate().toLocal());
  // Getter name
  String? get formattedCheckInTime => checkInTime == null ? null : DateFormat.jm().format(checkInTime!.toDate().toLocal());


  // --- Firestore Conversion ---
  factory AttendanceRecord.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    return AttendanceRecord(
      id: doc.id,
      lectureId: data['lectureId'] as String? ?? '',
      userId: data['userId'] as String? ?? '',
      studentName: data['studentName'] as String? ?? 'Unknown Student',
      registrationNumber: data['registrationNumber'] as String? ?? 'N/A',
      joinedAt: _parseTimestamp(data['joinedAt']) ?? Timestamp.now(),
      checkedIn: data['checkedIn'] as bool? ?? false, 
      checkInTime: _parseTimestamp(data['checkInTime']), 
      checkedInBy: data['checkedInBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    // Used when writing data *to* Firestore from the client (less common for attendance)
    return {
      'lectureId': lectureId,
      'userId': userId, 
      'studentName': studentName,
      'registrationNumber': registrationNumber,
      'joinedAt': joinedAt, 
      'checkedIn': checkedIn,
      'checkInTime': checkInTime, 
      'checkedInBy': checkedInBy, 
    };
  }
  // --- End Firestore Conversion ---


  // --- API Conversion Methods (If interacting via backend API) ---
  factory AttendanceRecord.fromApiJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      // Use 'id' or '_id' from API, fallback
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      lectureId: json['lectureId'] as String? ?? '',
      userId: json['userId'] as String? ?? '', 
      studentName: json['studentName'] as String? ?? 'Unknown Student',
      registrationNumber: json['registrationNumber'] as String? ?? 'N/A',
      joinedAt: _parseTimestamp(json['joinedAt']) ?? Timestamp.now(), 
      checkedIn: json['checkedIn'] as bool? ?? false, 
      checkInTime: _parseTimestamp(json['checkInTime']), // nullable
      checkedInBy: json['checkedInBy'] as String?,
    );
  }

  Map<String, dynamic> toApiJson() {
    // Convert object to JSON map suitable for sending TO the API
    return {
      // 'id': id, // Usually not sent when creating/updating via actions
      'lectureId': lectureId,
      'userId': userId,
      'studentName': studentName,
      'registrationNumber': registrationNumber,
      'joinedAt': _toIso8601String(joinedAt), // Send as ISO string
      'checkedIn': checkedIn,
      'checkInTime': _toIso8601String(checkInTime), // Renamed, send as ISO string or null
      'checkedInBy': checkedInBy,
    };
  }
  // --- End API Conversion ---


  // --- Utility Methods ---
   AttendanceRecord copyWith({
    String? id,
    String? lectureId,
    String? userId, 
    String? studentName,
    String? registrationNumber,
    Timestamp? joinedAt,
    bool? checkedIn, 
    Timestamp? checkInTime, 
    String? checkedInBy,
    // Add bool flags to explicitly handle setting nullable fields to null
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
