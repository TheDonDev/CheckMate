// lib/models/lecture.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // For immutable annotation
// Removed unused Material import
import 'package:intl/intl.dart';

// --- Helper Functions (Keep as they are) ---
DateTime? _parseDateTime(dynamic timestampData) {
  // ... (no changes needed here)
  if (timestampData == null) return null;
  try {
    if (timestampData is Timestamp) {
      return timestampData.toDate().toUtc();
    } else if (timestampData is String) {
      final dtIso = DateTime.tryParse(timestampData);
      if (dtIso != null) return dtIso.toUtc();
      DateTime? dtYmd;
      try {
        final parsedDate = DateFormat('yyyy-MM-dd').parseStrict(timestampData);
        dtYmd = DateTime.utc(parsedDate.year, parsedDate.month, parsedDate.day);
      } on FormatException { dtYmd = null; }
      if (dtYmd != null) return dtYmd;
    } else if (timestampData is Map && timestampData.containsKey('_seconds')) {
      final ts = Timestamp(timestampData['_seconds'], timestampData['_nanoseconds'] ?? 0);
      return ts.toDate().toUtc();
    } else if (timestampData is int) {
      return DateTime.fromMillisecondsSinceEpoch(timestampData, isUtc: true);
    }
  } catch (e) { if (kDebugMode) print("Error parsing DateTime: $timestampData, Error: $e"); }
  if (kDebugMode) print("Unrecognized DateTime format: $timestampData");
  return null;
}
String? _toIso8601UtcString(DateTime? dateTime) {
  // ... (no changes needed here)
  if (dateTime == null) return null;
  return dateTime.toUtc().toIso8601String();
}
String? _toDateOnlyIsoString(DateTime? dateTime) {
  // ... (no changes needed here)
  if (dateTime == null) return null;
  return DateFormat('yyyy-MM-dd').format(dateTime.toUtc());
}
// --- End Helper Functions ---


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
  final DateTime? lectureDate;
  final DateTime? startTime;
  final DateTime? endTime;
  final String venue;
  final DateTime? createdAt;
  // --- ADDED: Online Link Field ---
  final String? onlineLink;
  // --- END ADDED ---

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
    // --- ADDED: To constructor ---
    this.onlineLink,
    // --- END ADDED ---
  });

  // --- Formatting Getters (Keep as they are) ---
  String get formattedDate => lectureDate != null ? DateFormat.yMMMEd().format(lectureDate!.toLocal()) : 'N/A';
  String get formattedStartTime => startTime != null ? DateFormat.jm().format(startTime!.toLocal()) : 'N/A';
  String get formattedEndTime => endTime != null ? DateFormat.jm().format(endTime!.toLocal()) : 'N/A';
  String get formattedCreatedAt => createdAt != null ? DateFormat.yMd().add_jm().format(createdAt!.toLocal()) : 'N/A';
  // --- End Formatting Getters ---


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
      // --- ADDED: Parse from Firestore data ---
      onlineLink: data['onlineLink'] as String?,
      // --- END ADDED ---
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
      // --- ADDED: Include in Firestore data if not null ---
      if (onlineLink != null) 'onlineLink': onlineLink,
      // --- END ADDED ---
      // 'createdAt' is usually set by the server
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
      // --- ADDED: Parse from API JSON ---
      onlineLink: json['onlineLink'] as String?,
      // --- END ADDED ---
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
      'lectureDate': _toDateOnlyIsoString(lectureDate),
      'startTime': _toIso8601UtcString(startTime),
      'endTime': _toIso8601UtcString(endTime),
      // --- ADDED: Include in API JSON if not null ---
      if (onlineLink != null) 'onlineLink': onlineLink,
      // --- END ADDED ---
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
    // --- ADDED: onlineLink parameter ---
    String? onlineLink,
    // --- END ADDED ---
    bool setLecturerPhoneNull = false,
    bool setLectureDateNull = false,
    bool setStartTimeNull = false,
    bool setEndTimeNull = false,
    bool setCreatedAtNull = false,
    // --- ADDED: Flag for onlineLink ---
    bool setOnlineLinkNull = false,
    // --- END ADDED ---
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
      // --- ADDED: Handle onlineLink in copyWith ---
      onlineLink: setOnlineLinkNull ? null : (onlineLink ?? this.onlineLink),
      // --- END ADDED ---
    );
  }

  @override
  String toString() {
    // Add onlineLink to toString if present
    String linkInfo = onlineLink != null ? ', link: $onlineLink' : '';
    return 'Lecture(id: $id, unit: $unitName ($unitCode), lecturer: $lecturerName, date: ${_toDateOnlyIsoString(lectureDate)}, start: ${_toIso8601UtcString(startTime)}, end: ${_toIso8601UtcString(endTime)}, venue: $venue$linkInfo)';
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
      other.createdAt == createdAt &&
      // --- ADDED: Compare onlineLink ---
      other.onlineLink == onlineLink;
      // --- END ADDED ---
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
        // --- ADDED: Hash onlineLink ---
        onlineLink,
        // --- END ADDED ---
      );
}
