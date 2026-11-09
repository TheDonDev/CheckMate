// lib/models/lecture.dart
import 'package:intl/intl.dart';

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
  final DateTime startTime;
  final DateTime endTime;
  final String venue;
  final String? onlineLink;
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
    this.onlineLink,
    required this.createdAt,
  });

  String get formattedDate => DateFormat.yMMMEd().format(lectureDate);
  String get formattedStartTime => DateFormat.jm().format(startTime.toLocal());
  String get formattedEndTime => DateFormat.jm().format(endTime.toLocal());

  factory Lecture.fromApiJson(Map<String, dynamic> json) {
    return Lecture(
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
      lectureDate: (json['lectureDate'] != null) ? DateTime.parse(json['lectureDate']) : DateTime(1970),
      startTime: (json['startTime'] != null) ? DateTime.parse(json['startTime']) : DateTime(1970),
      endTime: (json['endTime'] != null) ? DateTime.parse(json['endTime']) : DateTime(1970),
      venue: json['venue'] ?? '',
      onlineLink: json['onlineLink'] as String?,
      createdAt: (json['createdAt'] != null) ? DateTime.parse(json['createdAt']) : DateTime(1970),
    );
  }

  Map<String, dynamic> toApiJson() {
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
      'lectureDate': lectureDate.toIso8601String(),
      'startTime': startTime.toIso8601String(),
      'endTime': endTime.toIso8601String(),
      'venue': venue,
      'onlineLink': onlineLink,
    };
  }

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
    String? onlineLink,
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
      onlineLink: onlineLink ?? this.onlineLink,
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
    return other is Lecture && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
