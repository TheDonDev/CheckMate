// lib/models/attendance_record.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // For immutable annotation and kDebugMode
import 'package:intl/intl.dart'; // For formatting dates/times in UI if needed

// Helper function to parse Timestamps from various formats (API/Firestore)
Timestamp? _parseTimestamp(dynamic timestampData) {
  if (timestampData == null) return null;
  if (timestampData is Timestamp) return timestampData;
  if (timestampData is String) {
    try {
      // Try parsing as ISO 8601 string (ensure UTC if no offset)
      return Timestamp.fromDate(DateTime.parse(timestampData).toUtc());
    } catch (e) {
      if (kDebugMode) print("Error parsing timestamp string: $timestampData, Error: $e");
      return null;
    }
  } else if (timestampData is Map && timestampData.containsKey('_seconds')) {
    // Firestore-like map { _seconds: ..., _nanoseconds: ... }
    try {
       return Timestamp(timestampData['_seconds'] as int, timestampData['_nanoseconds'] as int? ?? 0);
    } catch (e) {
       if (kDebugMode) print("Error parsing timestamp map: $timestampData, Error: $e");
       return null;
    }
  } else if (timestampData is int) {
    // Assuming milliseconds since epoch if it's an int
    try {
      return Timestamp.fromMillisecondsSinceEpoch(timestampData);
    } catch (e) {
       if (kDebugMode) print("Error parsing timestamp int: $timestampData, Error: $e");
       return null;
    }
  }
  if (kDebugMode) print("Unrecognized timestamp format: $timestampData");
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

// Helper function to safely parse boolean from various formats
bool _parseBool(dynamic boolData) {
  if (boolData == null) return false;
  if (boolData is bool) return boolData;
  if (boolData is String) return boolData.toLowerCase() == 'true';
  if (boolData is int) return boolData == 1;
  return false; // Default to false for unrecognized types
}


@immutable // Mark class as immutable
class AttendanceRecord {
  final String id; // Firestore document ID or API ID
  final String lectureId;
  final String userId; // Using userId as per your provided code
  final String studentName;
  final String registrationNumber;
  final Timestamp joinedAt; // When the student joined the lecture
  final Timestamp? checkInTime;
  final bool checkedIn; // Using checkedIn as per your provided code
  final String? checkedInBy; // Lecturer's User ID who checked them in
  final String? percentage; 

  const AttendanceRecord({ // Use const constructor
    required this.id,
    required this.lectureId,
    required this.userId,
    required this.studentName,
    required this.registrationNumber,
    required this.joinedAt,
    required this.checkedIn, // Use checkedIn
    this.checkInTime,
    this.checkedInBy,
    this.percentage,
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
      userId: data['userId'] as String? ?? '', // Use userId
      studentName: data['studentName'] as String? ?? 'Unknown Student',
      registrationNumber: data['registrationNumber'] as String? ?? 'N/A',
      joinedAt: _parseTimestamp(data['joinedAt']) ?? Timestamp.now(),
      checkedIn: _parseBool(data['checkedIn']), // Use checkedIn and safe parsing
      checkInTime: _parseTimestamp(data['checkInTime']),
      checkedInBy: data['checkedInBy'] as String?,
      percentage: data['percentage'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    // Used when writing data *to* Firestore from the client (less common for attendance)
    return {
      'lectureId': lectureId,
      'userId': userId, // Use userId
      'studentName': studentName,
      'registrationNumber': registrationNumber,
      'joinedAt': joinedAt,
      'checkedIn': checkedIn, // Use checkedIn
      'checkInTime': checkInTime,
      'checkedInBy': checkedInBy,
      'percentage': percentage,
    };
  }
  // --- End Firestore Conversion ---


  // --- API Conversion Methods (If interacting via backend API) ---
  factory AttendanceRecord.fromApiJson(Map<String, dynamic> json) {
    return AttendanceRecord(
      // Use 'id' or '_id' from API, fallback
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      lectureId: json['lectureId'] as String? ?? '',
      userId: json['userId'] as String? ?? '', // Use userId
      studentName: json['studentName'] as String? ?? 'Unknown Student',
      registrationNumber: json['registrationNumber'] as String? ?? 'N/A',
      joinedAt: _parseTimestamp(json['joinedAt']) ?? Timestamp.now(),
      checkedIn: _parseBool(json['checkedIn']), // Use checkedIn and safe parsing
      checkInTime: _parseTimestamp(json['checkInTime']), // nullable
      checkedInBy: json['checkedInBy'] as String?,
    );
  }

  Map<String, dynamic> toApiJson() {
    // Convert object to JSON map suitable for sending TO the API
    return {
      // 'id': id, // Usually not sent when creating/updating via actions
      'lectureId': lectureId,
      'userId': userId, // Use userId
      'studentName': studentName,
      'registrationNumber': registrationNumber,
      'joinedAt': _toIso8601String(joinedAt), // Send as ISO string
      'checkedIn': checkedIn, // Use checkedIn
      'checkInTime': _toIso8601String(checkInTime), // Send as ISO string or null
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
    bool? checkedIn, // Use checkedIn
    Timestamp? checkInTime,
    String? checkedInBy,
    // Add bool flags to explicitly handle setting nullable fields to null
    bool setCheckInTimeNull = false,
    bool setCheckedInByNull = false,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      lectureId: lectureId ?? this.lectureId,
      userId: userId ?? this.userId, // Use userId
      studentName: studentName ?? this.studentName,
      registrationNumber: registrationNumber ?? this.registrationNumber,
      joinedAt: joinedAt ?? this.joinedAt,
      checkedIn: checkedIn ?? this.checkedIn, // Use checkedIn
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
        other.userId == userId && // Use userId
        other.studentName == studentName &&
        other.registrationNumber == registrationNumber &&
        other.joinedAt == joinedAt &&
        other.checkedIn == checkedIn && // Use checkedIn
        other.checkInTime == checkInTime &&
        other.checkedInBy == checkedInBy;
  }

  @override
  int get hashCode =>
      id.hashCode ^
      lectureId.hashCode ^
      userId.hashCode ^ // Use userId
      studentName.hashCode ^
      registrationNumber.hashCode ^
      joinedAt.hashCode ^
      checkedIn.hashCode ^ // Use checkedIn
      checkInTime.hashCode ^
      checkedInBy.hashCode;
}