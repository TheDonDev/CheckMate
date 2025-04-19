// lib/models/lecture.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // For immutable annotation
import 'package:intl/intl.dart';

// --- Helper Functions (Consider moving to a dedicated utility file) ---

// Parses various timestamp formats (Firestore Timestamp, ISO String, int milliseconds)
// into a nullable DateTime object (UTC).
DateTime? _parseDateTime(dynamic timestampData) {
  if (timestampData == null) return null;
  try {
    if (timestampData is Timestamp) {
      return timestampData.toDate().toUtc(); // Convert Firestore Timestamp to UTC DateTime
    } else if (timestampData is String) {
      // Assume ISO 8601 string
      return DateTime.parse(timestampData).toUtc();
    } else if (timestampData is Map && timestampData.containsKey('_seconds')) {
      // Handle Firestore-like map (less common on client)
      final ts = Timestamp(timestampData['_seconds'], timestampData['_nanoseconds'] ?? 0);
      return ts.toDate().toUtc();
    } else if (timestampData is int) {
      // Assume milliseconds since epoch
      return DateTime.fromMillisecondsSinceEpoch(timestampData, isUtc: true);
    }
  } catch (e) {
    print("Error parsing DateTime: $timestampData, Error: $e");
  }
  print("Unrecognized DateTime format: $timestampData");
  return null; // Return null if parsing fails
}

// Converts a nullable DateTime object to an ISO 8601 UTC string.
String? _toIso8601UtcString(DateTime? dateTime) {
  if (dateTime == null) return null;
  // Ensure the DateTime is treated as UTC before formatting
  return dateTime.toUtc().toIso8601String();
}

// --- Lecture Model ---

@immutable // Mark class as immutable
class Lecture {
  final String id;
  final String lecturerId;
  final String lecturerName;
  final String? lecturerPhone; // Made nullable to match backend logic
  final String school;
  final String department;
  final String course;
  final String yearOfStudy;
  final String semester;
  final String unitName;
  final String unitCode;
  final DateTime? lectureDate; // Changed to nullable DateTime
  final DateTime? startTime;   // Changed to nullable DateTime
  final DateTime? endTime;     // Changed to nullable DateTime
  final String venue;
  final DateTime? createdAt;   // Changed to nullable DateTime

  const Lecture({ // Use const constructor
    required this.id,
    required this.lecturerId,
    required this.lecturerName,
    this.lecturerPhone, // Nullable
    required this.school,
    required this.department,
    required this.course,
    required this.yearOfStudy,
    required this.semester,
    required this.unitName,
    required this.unitCode,
    required this.lectureDate, // Keep required based on backend validation
    required this.startTime,   // Keep required based on backend validation
    required this.endTime,     // Keep required based on backend validation
    required this.venue,
    this.createdAt, // Nullable, often set by server
  });

  // --- Formatting Getters (for UI display, handle nulls) ---
  String get formattedDate => lectureDate != null ? DateFormat.yMMMEd().format(lectureDate!.toLocal()) : 'N/A';
  String get formattedStartTime => startTime != null ? DateFormat.jm().format(startTime!.toLocal()) : 'N/A';
  String get formattedEndTime => endTime != null ? DateFormat.jm().format(endTime!.toLocal()) : 'N/A';
  String get formattedCreatedAt => createdAt != null ? DateFormat.yMd().add_jm().format(createdAt!.toLocal()) : 'N/A';


  // --- Firestore Conversion ---
  // Creates a Lecture object from a Firestore DocumentSnapshot
  factory Lecture.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};

    return Lecture(
      id: doc.id,
      lecturerId: data['lecturerId'] as String? ?? '',
      lecturerName: data['lecturerName'] as String? ?? 'N/A',
      lecturerPhone: data['lecturerPhone'] as String?, // Nullable
      school: data['school'] as String? ?? '',
      department: data['department'] as String? ?? '',
      course: data['course'] as String? ?? '',
      yearOfStudy: data['yearOfStudy'] as String? ?? '',
      semester: data['semester'] as String? ?? '',
      unitName: data['unitName'] as String? ?? '',
      unitCode: data['unitCode'] as String? ?? '',
      lectureDate: _parseDateTime(data['lectureDate']), // Use helper
      startTime: _parseDateTime(data['startTime']),     // Use helper
      endTime: _parseDateTime(data['endTime']),         // Use helper
      venue: data['venue'] as String? ?? '',
      createdAt: _parseDateTime(data['createdAt']),     // Use helper
    );
  }

  // Converts Lecture object to a Map suitable for writing TO Firestore
  // Less common if creation/updates happen via API, but useful for direct interaction.
  Map<String, dynamic> toFirestore() {
    return {
      // 'id' is the document ID, not usually stored within the document itself
      'lecturerId': lecturerId,
      'lecturerName': lecturerName,
      if (lecturerPhone != null) 'lecturerPhone': lecturerPhone, // Only include if not null
      'school': school,
      'department': department,
      'course': course,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'unitName': unitName,
      'unitCode': unitCode,
      'venue': venue,
      // Convert DateTime back to Firestore Timestamp or null
      'lectureDate': lectureDate != null ? Timestamp.fromDate(lectureDate!) : null,
      'startTime': startTime != null ? Timestamp.fromDate(startTime!) : null,
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      // 'createdAt' is usually set by the server (FieldValue.serverTimestamp()) on creation
      // Only include if explicitly updating or needing to store client-set time
      // 'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : null,
    };
  }
  // --- End Firestore Conversion ---


  // --- API Conversion Methods ---
  // Creates a Lecture object from a JSON map received FROM the API
  factory Lecture.fromApiJson(Map<String, dynamic> json) {
    return Lecture(
      // Use 'id' or '_id' depending on your backend API convention
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      lecturerId: json['lecturerId'] as String? ?? '',
      lecturerName: json['lecturerName'] as String? ?? 'N/A',
      lecturerPhone: json['lecturerPhone'] as String?, // Nullable
      school: json['school'] as String? ?? '',
      department: json['department'] as String? ?? '',
      course: json['course'] as String? ?? '',
      yearOfStudy: json['yearOfStudy'] as String? ?? '',
      semester: json['semester'] as String? ?? '',
      unitName: json['unitName'] as String? ?? '',
      unitCode: json['unitCode'] as String? ?? '',
      // Parse dates/times from API format (likely ISO strings) using helper
      lectureDate: _parseDateTime(json['lectureDate']),
      startTime: _parseDateTime(json['startTime']),
      endTime: _parseDateTime(json['endTime']),
      venue: json['venue'] as String? ?? '',
      createdAt: _parseDateTime(json['createdAt']), // Use 'createdAt' or API field name
    );
  }

  // Converts Lecture object to a JSON map suitable for sending TO the API
  Map<String, dynamic> toApiJson() {
    return {
      // Don't usually send 'id' when creating via API
      // 'lecturerId' might be inferred from auth token on backend
      // 'lecturerName' might be inferred from auth token on backend
      if (lecturerPhone != null) 'lecturerPhone': lecturerPhone, // Send if available
      'school': school,
      'department': department,
      'course': course,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'unitName': unitName,
      'unitCode': unitCode,
      'venue': venue,
      // Send dates/timestamps as ISO strings (UTC)
      'lectureDate': _toIso8601UtcString(lectureDate),
      'startTime': _toIso8601UtcString(startTime),
      'endTime': _toIso8601UtcString(endTime),
      // 'createdAt' is usually set by the server, don't send unless API requires it
    };
  }
  // --- End API Conversion ---


  // --- Utility Methods ---
   Lecture copyWith({
    String? id,
    String? lecturerId,
    String? lecturerName,
    String? lecturerPhone,
    String? school,
    String? department,
    String? course,
    String? yearOfStudy,
    String? semester,
    String? unitName,
    String? unitCode,
    DateTime? lectureDate,
    DateTime? startTime,
    DateTime? endTime,
    String? venue,
    DateTime? createdAt,
    // Flags for explicitly setting nullable fields to null
    bool setLecturerPhoneNull = false,
    bool setLectureDateNull = false,
    bool setStartTimeNull = false,
    bool setEndTimeNull = false,
    bool setCreatedAtNull = false,
  }) {
    return Lecture(
      id: id ?? this.id,
      lecturerId: lecturerId ?? this.lecturerId,
      lecturerName: lecturerName ?? this.lecturerName,
      lecturerPhone: setLecturerPhoneNull ? null : (lecturerPhone ?? this.lecturerPhone),
      school: school ?? this.school,
      department: department ?? this.department,
      course: course ?? this.course,
      yearOfStudy: yearOfStudy ?? this.yearOfStudy,
      semester: semester ?? this.semester,
      unitName: unitName ?? this.unitName,
      unitCode: unitCode ?? this.unitCode,
      lectureDate: setLectureDateNull ? null : (lectureDate ?? this.lectureDate),
      startTime: setStartTimeNull ? null : (startTime ?? this.startTime),
      endTime: setEndTimeNull ? null : (endTime ?? this.endTime),
      venue: venue ?? this.venue,
      createdAt: setCreatedAtNull ? null : (createdAt ?? this.createdAt),
    );
  }

  @override
  String toString() {
    // Provide a more informative default toString
    return 'Lecture(id: $id, unit: $unitName ($unitCode), lecturer: $lecturerName, date: ${lectureDate?.toIso8601String()}, start: ${startTime?.toIso8601String()}, end: ${endTime?.toIso8601String()}, venue: $venue)';
  }

  // Implement == and hashCode based on all fields for proper comparison
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is Lecture &&
      other.id == id &&
      other.lecturerId == lecturerId &&
      other.lecturerName == lecturerName &&
      other.lecturerPhone == lecturerPhone &&
      other.school == school &&
      other.department == department &&
      other.course == course &&
      other.yearOfStudy == yearOfStudy &&
      other.semester == semester &&
      other.unitName == unitName &&
      other.unitCode == unitCode &&
      other.lectureDate == lectureDate &&
      other.startTime == startTime &&
      other.endTime == endTime &&
      other.venue == venue &&
      other.createdAt == createdAt;
  }

  @override
  int get hashCode => Object.hash(
        id,
        lecturerId,
        lecturerName,
        lecturerPhone,
        school,
        department,
        course,
        yearOfStudy,
        semester,
        unitName,
        unitCode,
        lectureDate,
        startTime,
        endTime,
        venue,
        createdAt,
      );
}
