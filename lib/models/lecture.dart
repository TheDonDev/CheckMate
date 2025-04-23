// lib/models/lecture.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // For immutable annotation
import 'package:flutter/material.dart'; // Required for TimeOfDay (still needed for pickers)
import 'package:intl/intl.dart';

// --- Helper Functions ---

// Parses various timestamp formats into a nullable DateTime object (UTC).
DateTime? _parseDateTime(dynamic timestampData) {
  if (timestampData == null) return null;
  try {
    if (timestampData is Timestamp) {
      return timestampData.toDate().toUtc();
    } else if (timestampData is String) {
      // 1. Try parsing as full ISO 8601 string first
      final dtIso = DateTime.tryParse(timestampData);
      if (dtIso != null) return dtIso.toUtc();

      // 2. Fallback: Try parsing strictly as 'yyyy-MM-dd'
      DateTime? dtYmd;
      try {
        // Use parseStrict within a try-catch block
        final parsedDate = DateFormat('yyyy-MM-dd').parseStrict(timestampData);
        // If successful, create DateTime at midnight UTC
        dtYmd = DateTime.utc(parsedDate.year, parsedDate.month, parsedDate.day);
      } on FormatException {
        // If parseStrict fails, dtYmd remains null
        dtYmd = null;
      }
      if (dtYmd != null) return dtYmd; // Return if date-only parsing succeeded

    } else if (timestampData is Map && timestampData.containsKey('_seconds')) {
      // Handle potential Firestore Timestamp map representation
      final ts = Timestamp(timestampData['_seconds'], timestampData['_nanoseconds'] ?? 0);
      return ts.toDate().toUtc();
    } else if (timestampData is int) {
      // Handle millisecondsSinceEpoch
      return DateTime.fromMillisecondsSinceEpoch(timestampData, isUtc: true);
    }
  } catch (e) {
    if (kDebugMode) print("Error parsing DateTime: $timestampData, Error: $e");
  }
  // If none of the formats match or an error occurs
  if (kDebugMode) print("Unrecognized DateTime format: $timestampData");
  return null;
}

// Converts a nullable DateTime object to an ISO 8601 UTC string.
String? _toIso8601UtcString(DateTime? dateTime) {
  if (dateTime == null) return null;
  return dateTime.toUtc().toIso8601String(); // e.g., 2023-10-27T14:30:00.000Z
}

// Converts a nullable DateTime object to a 'yyyy-MM-dd' string (UTC date).
String? _toDateOnlyIsoString(DateTime? dateTime) {
  if (dateTime == null) return null;
  return DateFormat('yyyy-MM-dd').format(dateTime.toUtc());
}

// --- Lecture Model ---

@immutable
class Lecture {
  final String id;
  final String lecturerId;
  final String lecturerName;
  final String? lecturerPhone;
  final String school;
  final String department;
  final String course;
  final String yearOfStudy;
  final String semester;
  final String unitName;
  final String unitCode;
  final DateTime? lectureDate; // Can represent just the date or full timestamp depending on usage
  final DateTime? startTime;   // Represents the specific start date and time
  final DateTime? endTime;     // Represents the specific end date and time
  final String venue;
  final DateTime? createdAt;

  const Lecture({
    required this.id,
    required this.lecturerId,
    required this.lecturerName,
    this.lecturerPhone,
    required this.school,
    required this.department,
    required this.course,
    required this.yearOfStudy,
    required this.semester,
    required this.unitName,
    required this.unitCode,
    required this.lectureDate,
    required this.startTime,
    required this.endTime,
    required this.venue,
    this.createdAt,
  });

  // --- Formatting Getters ---
  String get formattedDate => lectureDate != null
      ? DateFormat.yMMMEd().format(lectureDate!.toLocal()) // Format date part
      : 'N/A';

  String get formattedStartTime => startTime != null
      ? DateFormat.jm().format(startTime!.toLocal()) // e.g., 9:30 AM
      : 'N/A';
  String get formattedEndTime => endTime != null
      ? DateFormat.jm().format(endTime!.toLocal()) // e.g., 11:00 AM
      : 'N/A';

  String get formattedCreatedAt => createdAt != null
      ? DateFormat.yMd().add_jm().format(createdAt!.toLocal()) // Full date and time
      : 'N/A';


  // --- Firestore Conversion ---
  factory Lecture.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};

    return Lecture(
      id: doc.id,
      lecturerId: data['lecturerId'] as String? ?? '',
      lecturerName: data['lecturerName'] as String? ?? 'N/A',
      lecturerPhone: data['lecturerPhone'] as String?,
      school: data['school'] as String? ?? '',
      department: data['department'] as String? ?? '',
      course: data['course'] as String? ?? '',
      yearOfStudy: data['yearOfStudy'] as String? ?? '',
      semester: data['semester'] as String? ?? '',
      unitName: data['unitName'] as String? ?? '',
      unitCode: data['unitCode'] as String? ?? '',
      lectureDate: _parseDateTime(data['lectureDate']),
      startTime: _parseDateTime(data['startTime']),
      endTime: _parseDateTime(data['endTime']),
      venue: data['venue'] as String? ?? '',
      createdAt: _parseDateTime(data['createdAt']),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'lecturerId': lecturerId,
      'lecturerName': lecturerName,
      if (lecturerPhone != null) 'lecturerPhone': lecturerPhone,
      'school': school,
      'department': department,
      'course': course,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'unitName': unitName,
      'unitCode': unitCode,
      'venue': venue,
      'lectureDate': lectureDate != null ? Timestamp.fromDate(lectureDate!) : null,
      'startTime': startTime != null ? Timestamp.fromDate(startTime!) : null,
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,
      // 'createdAt' is usually set by the server on creation
    };
  }
  // --- End Firestore Conversion ---


  // --- API Conversion Methods ---
  factory Lecture.fromApiJson(Map<String, dynamic> json) {
    return Lecture(
      id: json['id'] as String? ?? json['_id'] as String? ?? '',
      lecturerId: json['lecturerId'] as String? ?? '',
      lecturerName: json['lecturerName'] as String? ?? 'N/A',
      lecturerPhone: json['lecturerPhone'] as String?,
      school: json['school'] as String? ?? '',
      department: json['department'] as String? ?? '',
      course: json['course'] as String? ?? '',
      yearOfStudy: json['yearOfStudy'] as String? ?? '',
      semester: json['semester'] as String? ?? '',
      unitName: json['unitName'] as String? ?? '',
      unitCode: json['unitCode'] as String? ?? '',
      lectureDate: _parseDateTime(json['lectureDate']),
      startTime: _parseDateTime(json['startTime']),
      endTime: _parseDateTime(json['endTime']),
      venue: json['venue'] as String? ?? '',
      createdAt: _parseDateTime(json['createdAt']),
    );
  }

  Map<String, dynamic> toApiJson() {
    return {
      if (lecturerPhone != null) 'lecturerPhone': lecturerPhone,
      'school': school,
      'department': department,
      'course': course,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'unitName': unitName,
      'unitCode': unitCode,
      'venue': venue,
      // Send dates/times as full ISO 8601 UTC strings
      'lectureDate': _toDateOnlyIsoString(lectureDate), // Keep as 'yyyy-MM-dd' if backend expects that
      'startTime': _toIso8601UtcString(startTime), // Send full ISO string
      'endTime': _toIso8601UtcString(endTime),     // Send full ISO string
      // 'createdAt' is usually set by the server
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
    return 'Lecture(id: $id, unit: $unitName ($unitCode), lecturer: $lecturerName, date: ${_toDateOnlyIsoString(lectureDate)}, start: ${_toIso8601UtcString(startTime)}, end: ${_toIso8601UtcString(endTime)}, venue: $venue)';
  }

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
