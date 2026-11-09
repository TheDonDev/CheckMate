// lib/models/app_user.dart
import 'package:flutter/foundation.dart';

@immutable
class User {
  final String id;
  final String name;
  final String email;
  final String phoneNumber;
  final String role;
  final bool isVerified;
  final String? school;
  final String? department;
  final String? course;
  final String? registrationNumber;
  final String? yearOfStudy;
  final String? semester;
  final DateTime? createdAt;

  const User({
    required this.id,
    required this.name,
    required this.email,
    required this.phoneNumber,
    required this.role,
    required this.isVerified,
    this.school,
    this.department,
    this.course,
    this.registrationNumber,
    this.yearOfStudy,
    this.semester,
    this.createdAt,
  });

  factory User.fromApiJson(Map<String, dynamic> data) {
    final rawCreatedAt = data['createdAt'];
    DateTime? createdAt;
    if (rawCreatedAt is String) {
      createdAt = DateTime.tryParse(rawCreatedAt);
    }
    return User(
      id: data['id']?.toString() ?? data['uid']?.toString() ?? '',
      name: data['name']?.toString() ?? '',
      email: data['email']?.toString() ?? '',
      phoneNumber: data['phoneNumber']?.toString() ?? '',
      role: data['role']?.toString() ?? 'student',
      isVerified: data['isVerified'] == true,
      school: data['school']?.toString(),
      department: data['department']?.toString(),
      course: data['course']?.toString(),
      registrationNumber: data['registrationNumber']?.toString(),
      yearOfStudy: data['yearOfStudy']?.toString(),
      semester: data['semester']?.toString(),
      createdAt: createdAt,
    );
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? phoneNumber,
    String? role,
    bool? isVerified,
    String? school,
    String? department,
    String? course,
    String? registrationNumber,
    String? yearOfStudy,
    String? semester,
    DateTime? createdAt,
    bool setSchoolNull = false,
    bool setDepartmentNull = false,
    bool setCourseNull = false,
    bool setRegistrationNumberNull = false,
    bool setYearOfStudyNull = false,
    bool setSemesterNull = false,
    bool setCreatedAtNull = false,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      role: role ?? this.role,
      isVerified: isVerified ?? this.isVerified,
      school: setSchoolNull ? null : (school ?? this.school),
      department: setDepartmentNull ? null : (department ?? this.department),
      course: setCourseNull ? null : (course ?? this.course),
      registrationNumber: setRegistrationNumberNull ? null : (registrationNumber ?? this.registrationNumber),
      yearOfStudy: setYearOfStudyNull ? null : (yearOfStudy ?? this.yearOfStudy),
      semester: setSemesterNull ? null : (semester ?? this.semester),
      createdAt: setCreatedAtNull ? null : (createdAt ?? this.createdAt),
    );
  }

  @override
  String toString() {
    return 'User(id: $id, name: $name, email: $email, phoneNumber: $phoneNumber, role: $role, isVerified: $isVerified, school: $school, department: $department, course: $course, registrationNumber: $registrationNumber, yearOfStudy: $yearOfStudy, semester: $semester, createdAt: $createdAt)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is User &&
      other.id == id &&
      other.name == name &&
      other.email == email &&
      other.phoneNumber == phoneNumber &&
      other.role == role &&
      other.isVerified == isVerified &&
      other.school == school &&
      other.department == department &&
      other.course == course &&
      other.registrationNumber == registrationNumber &&
      other.yearOfStudy == yearOfStudy &&
      other.semester == semester &&
      other.createdAt == createdAt;
  }

  @override
  int get hashCode {
    return id.hashCode ^
      name.hashCode ^
      email.hashCode ^
      phoneNumber.hashCode ^
      role.hashCode ^
      isVerified.hashCode ^
      school.hashCode ^
      department.hashCode ^
      course.hashCode ^
      registrationNumber.hashCode ^
      yearOfStudy.hashCode ^
      semester.hashCode ^
      createdAt.hashCode;
  }
}
