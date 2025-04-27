// lib/models/lecture.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

// Helper function (can be placed here or in a utility file)
Timestamp? _parseTimestamp(dynamic timestampData) {
  if (timestampData == null) return null;
  // Assuming API sends ISO 8601 string or Firestore-like map { _seconds: ..., _nanoseconds: ... }
  if (timestampData is String) {
    try {
      return Timestamp.fromDate(DateTime.parse(timestampData));
    } catch (e) {
      print("Error parsing timestamp string: $timestampData, Error: $e");
      return null; // Or return a default Timestamp
    }
  } else if (timestampData is Map && timestampData.containsKey('_seconds')) {
    return Timestamp(timestampData['_seconds'], timestampData['_nanoseconds'] ?? 0);
  } else if (timestampData is int) {
    // Assuming milliseconds since epoch if it's an int
    return Timestamp.fromMillisecondsSinceEpoch(timestampData);
  }
  print("Unrecognized timestamp format: $timestampData");
  return null; // Or throw error
}

// Helper to convert Timestamp/DateTime to ISO string for API
String? _toIso8601String(dynamic dateOrTimestamp) {
  if (dateOrTimestamp == null) return null;
  if (dateOrTimestamp is Timestamp) {
    return dateOrTimestamp.toDate().toIso8601String();
  } else if (dateOrTimestamp is DateTime) {
    return dateOrTimestamp.toIso8601String();
  }
  return null;
}


class Lecture {
  final String id;
  final String lecturerId;
  final String lecturerName;
  final String lecturerPhone;
  final String school;
  final String department;
  final String course;
  final String yearOfStudy;
  final String semester;
  final String unitName;
  final String unitCode;
  final DateTime lectureDate; 
  final Timestamp startTime;
  final Timestamp endTime;
  final String venue;
  final DateTime createdAt; 

  Lecture({
    required this.id,
    required this.lecturerId,
    required this.lecturerName,
    required this.lecturerPhone,
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
    required this.createdAt,
  });

  // --- Formatting Getters ---
  String get formattedDate => DateFormat.yMMMEd().format(lectureDate);
  String get formattedStartTime => DateFormat.jm().format(startTime.toDate());
  String get formattedEndTime => DateFormat.jm().format(endTime.toDate());

  // --- Firestore Conversion ---
  Map<String, dynamic> toFirestore() {
    return {
      'lecturerId': lecturerId,
      'lecturerName': lecturerName,
      'lecturerPhone': lecturerPhone,
      'school': school,
      'department': department,
      'course': course,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'unitName': unitName,
      'unitCode': unitCode,
      // Store DateTime as Timestamp for Firestore
      'lectureDate': Timestamp.fromDate(lectureDate),
      'startTime': startTime, 
      'endTime': endTime,    
      'venue': venue,
      // Store DateTime as Timestamp for Firestore
      'createdAt': Timestamp.fromDate(createdAt),
      // Use FieldValue.serverTimestamp() when creating if possible and if createdAt is not set manually
      // 'createdAt': FieldValue.serverTimestamp(),
    };
  }

  factory Lecture.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {}; // Handle null data

    // Helper to safely convert Firestore Timestamp to DateTime, providing a default
    DateTime timestampToDateTime(Timestamp? timestamp) {

      return timestamp?.toDate() ?? DateTime(1970);
    }

    return Lecture(
      id: doc.id,
      lecturerId: data['lecturerId'] ?? '',
      lecturerName: data['lecturerName'] ?? '',
      lecturerPhone: data['lecturerPhone'] ?? '',
      school: data['school'] ?? '',
      department: data['department'] ?? '',
      course: data['course'] ?? '',
      yearOfStudy: data['yearOfStudy'] ?? '',
      semester: data['semester'] ?? '',
      unitName: data['unitName'] ?? '',
      unitCode: data['unitCode'] ?? '',
      // Convert Timestamps back to DateTime for the model fields
      lectureDate: timestampToDateTime(data['lectureDate'] as Timestamp?),
      // Ensure startTime/endTime are Timestamps, provide default if null/wrong type
      startTime: data['startTime'] as Timestamp? ?? Timestamp.fromDate(DateTime(1970)),
      endTime: data['endTime'] as Timestamp? ?? Timestamp.fromDate(DateTime(1970)),
      venue: data['venue'] ?? '',
      // Convert Timestamps back to DateTime for the model fields
      createdAt: timestampToDateTime(data['createdAt'] as Timestamp?),
    );
  }

  // --- API Conversion Methods  ---
  factory Lecture.fromApiJson(Map<String, dynamic> json) {
    // Adapt this based on the actual structure returned by your API
    return Lecture(
      // 'id' or '_id' depending on your backend convention
      id: json['id'] ?? json['_id'] ?? '',
      lecturerId: json['lecturerId'] ?? '',
      lecturerName: json['lecturerName'] ?? '',
      lecturerPhone: json['lecturerPhone'] ?? '',
      school: json['school'] ?? '',
      department: json['department'] ?? '',
      course: json['course'] ?? '',
      yearOfStudy: json['yearOfStudy'] ?? '',
      semester: json['semester'] ?? '',
      unitName: json['unitName'] ?? '',
      unitCode: json['unitCode'] ?? '',
      // Parse Timestamps carefully based on API format (e.g., ISO string)
      lectureDate: (json['lectureDate'] != null) ? DateTime.parse(json['lectureDate']) : DateTime(1970),
      startTime: _parseTimestamp(json['startTime']) ?? Timestamp.fromDate(DateTime(1970)),
      endTime: _parseTimestamp(json['endTime']) ?? Timestamp.fromDate(DateTime(1970)),
      venue: json['venue'] ?? '',
      //  'createdAt' or other field name from API
      createdAt: (json['createdAt'] != null) ? DateTime.parse(json['createdAt']) : DateTime(1970),
    );
  }

  Map<String, dynamic> toApiJson() {
    // Convert object to JSON map suitable for sending TO the API
    return {
      // Don't usually send 'id' when creating
      'lecturerId': lecturerId,
      'lecturerName': lecturerName,
      'lecturerPhone': lecturerPhone,
      'school': school,
      'department': department,
      'course': course,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
      'unitName': unitName,
      'unitCode': unitCode,
      // Send dates/timestamps as ISO strings (common practice)
      'lectureDate': _toIso8601String(lectureDate),
      'startTime': _toIso8601String(startTime),
      'endTime': _toIso8601String(endTime),
      'venue': venue,
      // 'createdAt' is usually set by the server, but send if API requires it
      // 'createdAt': _toIso8601String(createdAt),
    };
  }
  // --- End API Conversion ---


  // copyWith, toString, ==, hashCode remain largely the same
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
    Timestamp? startTime,
    Timestamp? endTime,
    String? venue,
    DateTime? createdAt,
  }) {
    return Lecture(
      id: id ?? this.id,
      lecturerId: lecturerId ?? this.lecturerId,
      lecturerName: lecturerName ?? this.lecturerName,
      lecturerPhone: lecturerPhone ?? this.lecturerPhone,
      school: school ?? this.school,
      department: department ?? this.department,
      course: course ?? this.course,
      yearOfStudy: yearOfStudy ?? this.yearOfStudy,
      semester: semester ?? this.semester,
      unitName: unitName ?? this.unitName,
      unitCode: unitCode ?? this.unitCode,
      lectureDate: lectureDate ?? this.lectureDate,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      venue: venue ?? this.venue,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() {
    return 'Lecture(id: $id, unit: $unitName ($unitCode), lecturer: $lecturerName, year: $yearOfStudy, sem: $semester, date: $formattedDate, time: $formattedStartTime-$formattedEndTime)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    // more fields for a robust comparison if needed
    return other is Lecture && other.id == id;
  }

  @override
  // more fields for a robust hash code if needed
  int get hashCode => id.hashCode;
}
