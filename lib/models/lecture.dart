// lib/models/lecture.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode and immutable annotation
import 'package:intl/intl.dart';

// --- Helper Functions ---

// Helper to parse various date/time formats from API/Firestore into a UTC DateTime
DateTime? _parseDateTimeToUtc(dynamic timestampData) {
  if (timestampData == null) return null;
  try {
    if (timestampData is Timestamp) {
      return timestampData.toDate(); // UTC
    } else if (timestampData is String) {
      final dtIso = DateTime.tryParse(timestampData);
      if (dtIso != null) {
        
        if (kDebugMode) print("[ParseHelper] Parsed ISO '$timestampData' to DateTime (isUtc: ${dtIso.isUtc}): ${dtIso.toIso8601String()} -> UTC: ${dtIso.toUtc().toIso8601String()}");
        return dtIso.toUtc(); // Ensured it's UTC
      }
      DateTime? dtYmd;
      try {
        final parsedDate = DateFormat('yyyy-MM-dd').parseStrict(timestampData);
        dtYmd = DateTime.utc(parsedDate.year, parsedDate.month, parsedDate.day);
        if (kDebugMode) print("[ParseHelper] Parsed YMD '$timestampData' to DateTime UTC: ${dtYmd.toIso8601String()}");
      } on FormatException { dtYmd = null; }
      if (dtYmd != null) return dtYmd; // UTC

    } else if (timestampData is Map && timestampData.containsKey('_seconds')) {
      final ts = Timestamp(timestampData['_seconds'], timestampData['_nanoseconds'] ?? 0);
      if (kDebugMode) print("[ParseHelper] Parsed Map Timestamp to DateTime UTC: ${ts.toDate().toIso8601String()}");
      return ts.toDate(); //  UTC
    } else if (timestampData is int) {
      final dt = DateTime.fromMillisecondsSinceEpoch(timestampData, isUtc: true);
      if (kDebugMode) print("[ParseHelper] Parsed Int Epoch to DateTime UTC: ${dt.toIso8601String()}");
      return dt;
    }
  } catch (e) { if (kDebugMode) print("[ParseHelper] Error parsing DateTime to UTC: $timestampData, Error: $e"); }
  if (kDebugMode) print("[ParseHelper] Unrecognized DateTime format for UTC parsing: $timestampData");
  return null;
}

// Helper to convert a DateTime (assumed UTC) to an ISO 8601 UTC string
String? _toIso8601UtcString(DateTime? dateTime) {
  if (dateTime == null) return null;
  return dateTime.toUtc().toIso8601String();
}

// Helper to convert a DateTime (assumed UTC) to 'YYYY-MM-DD' string
String? _toDateOnlyIsoString(DateTime? dateTime) {
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
  final DateTime? lectureDate; // Store as DateTime (internally UTC after parsing)
  final DateTime? startTime;   // Store as DateTime (internally UTC after parsing)
  final DateTime? endTime;     // Store as DateTime (internally UTC after parsing)
  final String venue;
  final DateTime? createdAt;   // Store as DateTime (internally UTC after parsing)
  final String? onlineLink;

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
    this.onlineLink,
  });

  // --- Formatting Getters ---
  String get formattedDate {
    final localDate = lectureDate?.toLocal();
   
    if (kDebugMode) print("[Lecture Format] Formatting lectureDate (UTC: ${lectureDate?.toIso8601String()}) to Local: ${localDate?.toIso8601String()}");
    return localDate != null ? DateFormat.yMMMEd().format(localDate) : 'N/A';
  }
  String get formattedStartTime {
    final localStartTime = startTime?.toLocal();
   
    if (kDebugMode) print("[Lecture Format] Formatting startTime (UTC: ${startTime?.toIso8601String()}) to Local: ${localStartTime?.toIso8601String()}");
    return localStartTime != null ? DateFormat.jm().format(localStartTime) : 'N/A';
  }
  String get formattedEndTime {
     final localEndTime = endTime?.toLocal();
   
    if (kDebugMode) print("[Lecture Format] Formatting endTime (UTC: ${endTime?.toIso8601String()}) to Local: ${localEndTime?.toIso8601String()}");
    return localEndTime != null ? DateFormat.jm().format(localEndTime) : 'N/A';
  }
  String get formattedCreatedAt {
    final localCreatedAt = createdAt?.toLocal();
  
    if (kDebugMode) print("[Lecture Format] Formatting createdAt (UTC: ${createdAt?.toIso8601String()}) to Local: ${localCreatedAt?.toIso8601String()}");
    return localCreatedAt != null ? DateFormat.yMd().add_jm().format(localCreatedAt) : 'N/A';
  }
  // --- End Formatting Getters ---


  // --- Firestore Conversion ---
  factory Lecture.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};

    if (kDebugMode) print("[Lecture fromFirestore] Raw data: $data");
    final lecture = Lecture(
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
      lectureDate: _parseDateTimeToUtc(data['lectureDate']), // Parse to UTC
      startTime: _parseDateTimeToUtc(data['startTime']),     // Parse to UTC
      endTime: _parseDateTimeToUtc(data['endTime']),         // Parse to UTC
      venue: data['venue'] as String? ?? '',
      createdAt: _parseDateTimeToUtc(data['createdAt']),     // Parse to UTC
      onlineLink: data['onlineLink'] as String?,
    );
    if (kDebugMode) print("[Lecture fromFirestore] Parsed Lecture object: $lecture");
    return lecture;
  }

  Map<String, dynamic> toFirestore() {
    // When sending TO Firestore, convert the UTC DateTime objects to Firestore Timestamps
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
      'lectureDate': lectureDate != null ? Timestamp.fromDate(lectureDate!) : null, // Assumes lectureDate is UTC
      'startTime': startTime != null ? Timestamp.fromDate(startTime!) : null,       // Assumes startTime is UTC
      'endTime': endTime != null ? Timestamp.fromDate(endTime!) : null,           // Assumes endTime is UTC
      if (onlineLink != null) 'onlineLink': onlineLink,
      // 'createdAt' is usually set by the server
    };
  }
  // --- End Firestore Conversion ---


  // --- API Conversion Methods ---
  factory Lecture.fromApiJson(Map<String, dynamic> json) {
    if (kDebugMode) print("[Lecture fromApiJson] Raw JSON received: $json");
    final lecture = Lecture(
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
      lectureDate: _parseDateTimeToUtc(json['lectureDate']), // Parse to UTC
      startTime: _parseDateTimeToUtc(json['startTime']),     // Parse to UTC
      endTime: _parseDateTimeToUtc(json['endTime']),         // Parse to UTC
      venue: json['venue'] as String? ?? '',
      createdAt: _parseDateTimeToUtc(json['createdAt']),     // Parse to UTC
      onlineLink: json['onlineLink'] as String?,
    );
    if (kDebugMode) print("[Lecture fromApiJson] Parsed Lecture object: $lecture");
    return lecture;
  }

  Map<String, dynamic> toApiJson() {
    // When sending TO the API, use helpers that convert the UTC DateTime to specific string formats
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
      'lectureDate': _toDateOnlyIsoString(lectureDate), // Send as 'YYYY-MM-DD'
      'startTime': _toIso8601UtcString(startTime),     // Send as ISO UTC string
      'endTime': _toIso8601UtcString(endTime),         // Send as ISO UTC string
      if (onlineLink != null) 'onlineLink': onlineLink,
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
    String? onlineLink,
    bool setLecturerPhoneNull = false,
    bool setLectureDateNull = false,
    bool setStartTimeNull = false,
    bool setEndTimeNull = false,
    bool setCreatedAtNull = false,
    bool setOnlineLinkNull = false,
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
      onlineLink: setOnlineLinkNull ? null : (onlineLink ?? this.onlineLink),
    );
  }

  @override
  String toString() {
    String linkInfo = onlineLink != null ? ', link: $onlineLink' : '';
    String utcStart = startTime != null ? startTime!.toUtc().toIso8601String() : 'null';
    String utcEnd = endTime != null ? endTime!.toUtc().toIso8601String() : 'null';
    return 'Lecture(id: $id, unit: $unitName ($unitCode), lecturer: $lecturerName, date: $formattedDate, start: $formattedStartTime (UTC: $utcStart), end: $formattedEndTime (UTC: $utcEnd), venue: $venue$linkInfo)';
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
      other.lectureDate == lectureDate && // Compare the underlying UTC DateTime objects
      other.startTime == startTime &&     // Compare the underlying UTC DateTime objects
      other.endTime == endTime &&         // Compare the underlying UTC DateTime objects
      other.venue == venue &&
      other.createdAt == createdAt &&     // Compare the underlying UTC DateTime objects
      other.onlineLink == onlineLink;
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
        lectureDate, // Hash the underlying UTC DateTime objects
        startTime,   // Hash the underlying UTC DateTime objects
        endTime,     // Hash the underlying UTC DateTime objects
        venue,
        createdAt,   // Hash the underlying UTC DateTime objects
        onlineLink,
      );
}
