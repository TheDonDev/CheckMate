// lib/models/attendance_record.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart'; // For formatting dates/times in UI if needed

// Helper function to parse Timestamps from various formats (API/Firestore)
Timestamp? _parseTimestamp(dynamic timestampData) {
  if (timestampData == null) return null;
  if (timestampData is Timestamp) return timestampData; // Already a Timestamp
  if (timestampData is String) {
    try { return Timestamp.fromDate(DateTime.parse(timestampData).toUtc()); } // Assume ISO 8601 UTC string from API
    catch (e) { print("Error parsing timestamp string: $timestampData, Error: $e"); return null; }
  } else if (timestampData is Map && timestampData.containsKey('_seconds')) {
    // Firestore-like map { _seconds: ..., _nanoseconds: ... }
    return Timestamp(timestampData['_seconds'], timestampData['_nanoseconds'] ?? 0);
  } else if (timestampData is int) {
    // Assuming milliseconds since epoch if it's an int
    return Timestamp.fromMillisecondsSinceEpoch(timestampData);
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


class AttendanceRecord {
  final String id; // Firestore document ID or API ID
  final String lectureId;
  final String studentId;
  final String studentName; // Denormalized for easier display
  final String studentCourse; // Denormalized
  final String registrationNumber; // Changed from visitNumber
  final Timestamp joinedAt; // When the student joined the lecture
  final Timestamp? checkedInAt; // When the lecturer checked the student in
  final String? checkedInBy; // Lecturer's User ID who checked them in

  AttendanceRecord({
    required this.id,
    required this.lectureId,
    required this.studentId,
    required this.studentName,
    required this.studentCourse,
    required this.registrationNumber, // Changed
    required this.joinedAt,
    this.checkedInAt,
    this.checkedInBy,
  });

  // --- Formatting Getters (Optional, for UI) ---
  String get formattedJoinedAt => DateFormat.jm().format(joinedAt.toDate().toLocal());
  String? get formattedCheckedInAt => checkedInAt == null ? null : DateFormat.jm().format(checkedInAt!.toDate().toLocal());


  // --- Firestore Conversion (If storing/reading directly from Firestore) ---
  factory AttendanceRecord.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};
    return AttendanceRecord(
      id: doc.id,
      lectureId: data['lectureId'] ?? '', // Get lectureId
      studentId: data['studentId'] ?? '',
      studentName: data['studentName'] ?? 'Unknown Student',
      studentCourse: data['studentCourse'] ?? 'Unknown Course',
      registrationNumber: data['registrationNumber'] ?? 'N/A', // Changed, provide default
      joinedAt: _parseTimestamp(data['joinedAt']) ?? Timestamp.now(), // Use helper, provide default
      checkedInAt: _parseTimestamp(data['checkedInAt']), // Use helper, nullable
      checkedInBy: data['checkedInBy'] as String?, // Nullable
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'lectureId': lectureId,
      'studentId': studentId,
      'studentName': studentName,
      'studentCourse': studentCourse,
      'registrationNumber': registrationNumber, // Changed
      'joinedAt': joinedAt, // Store as Timestamp
      // Use FieldValue for server-side timestamp on creation/update if possible
      // 'checkedInAt': checkedInAt ?? FieldValue.delete(), // Store Timestamp or remove if null
      'checkedInAt': checkedInAt, // Store Timestamp or null
      'checkedInBy': checkedInBy, // Store String or null
    };
  }
  // --- End Firestore Conversion ---


  // --- API Conversion Methods (If interacting via a separate backend API) ---
  factory AttendanceRecord.fromApiJson(Map<String, dynamic> json) {
    // Adapt based on your specific API structure
    return AttendanceRecord(
      // Use 'id' or '_id' from API, fallback if needed
      id: json['id'] ?? json['_id'] ?? json['registrationNumber'] ?? '', // Example fallbacks
      lectureId: json['lectureId'] ?? '', // Expect lectureId from API
      studentId: json['studentId'] ?? '',
      studentName: json['studentName'] ?? 'Unknown Student',
      studentCourse: json['studentCourse'] ?? 'Unknown Course',
      registrationNumber: json['registrationNumber'] ?? 'N/A', // Changed
      joinedAt: _parseTimestamp(json['joinedAt']) ?? Timestamp.now(), // Provide default
      checkedInAt: _parseTimestamp(json['checkedInAt']), // Nullable
      checkedInBy: json['checkedInBy'] as String?, // Nullable
    );
  }

  Map<String, dynamic> toApiJson() {
    // Convert object to JSON map suitable for sending TO the API
    // Only include fields the API expects for creation/update
    // This method might not be needed if records are only created/updated via specific API actions (join, checkin)
    return {
      // 'id': id, // Usually not sent when creating/updating via actions
      'lectureId': lectureId,
      'studentId': studentId,
      'studentName': studentName, // May be redundant if backend gets from studentId
      'studentCourse': studentCourse, // May be redundant
      'registrationNumber': registrationNumber, // Changed
      'joinedAt': _toIso8601String(joinedAt), // Send as ISO string
      'checkedInAt': _toIso8601String(checkedInAt), // Send as ISO string or null
      'checkedInBy': checkedInBy,
    };
  }
  // --- End API Conversion ---


  // --- Utility Methods ---
   AttendanceRecord copyWith({
    String? id,
    String? lectureId,
    String? studentId,
    String? studentName,
    String? studentCourse,
    String? registrationNumber, // Changed
    Timestamp? joinedAt,
    Timestamp? checkedInAt,
    String? checkedInBy,
    // Add bool flags to explicitly handle setting nullable fields to null
    bool setCheckedInAtNull = false,
    bool setCheckedInByNull = false,
  }) {
    return AttendanceRecord(
      id: id ?? this.id,
      lectureId: lectureId ?? this.lectureId,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      studentCourse: studentCourse ?? this.studentCourse,
      registrationNumber: registrationNumber ?? this.registrationNumber, // Changed
      joinedAt: joinedAt ?? this.joinedAt,
      checkedInAt: setCheckedInAtNull ? null : (checkedInAt ?? this.checkedInAt),
      checkedInBy: setCheckedInByNull ? null : (checkedInBy ?? this.checkedInBy),
    );
  }

   @override
  String toString() {
    return 'AttendanceRecord(id: $id, lectureId: $lectureId, studentName: $studentName, regNo: $registrationNumber, joinedAt: $joinedAt, checkedIn: ${checkedInAt != null})'; // Changed
  }

   @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AttendanceRecord &&
        other.id == id &&
        other.lectureId == lectureId &&
        other.studentId == studentId &&
        other.registrationNumber == registrationNumber; // Changed: Compare key fields
  }

  @override
  int get hashCode =>
      id.hashCode ^
      lectureId.hashCode ^
      studentId.hashCode ^
      registrationNumber.hashCode; // Changed: Hash key fields
}
