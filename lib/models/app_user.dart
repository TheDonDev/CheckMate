// lib/models/app_user.dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart'; // For immutable annotation

@immutable // Mark class as immutable
class User {
  final String id; // Firestore document ID (matches Firebase Auth UID)
  final String name;
  final String email;
  final String phoneNumber; 
  final String role; // 'student', 'lecturer', or 'admin'
  final bool isVerified; 
  final String? school;
  final String? department;
  final String? course;
  final String? registrationNumber; // Specific to students
  final String? yearOfStudy;        // Specific to students
  final String? semester;           // Specific to students
  final Timestamp? createdAt;        // Timestamp of creation

  const User({ // const constructor for immutable class
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

  // --- Factory constructor to create a User from a Firestore DocumentSnapshot ---
  factory User.fromFirestore(DocumentSnapshot doc) {
    // Get the data map, ensuring it's not null
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};

    // Helper to safely get Timestamp
    Timestamp? parseTimestamp(dynamic value) {
      if (value is Timestamp) {
        return value;
      }
      return null;
    }

    return User(
      id: doc.id, // the document ID from the snapshot
      name: data['name'] as String? ?? '', // Provide default if missing
      email: data['email'] as String? ?? '', // Provide default if missing
      phoneNumber: data['phoneNumber'] as String? ?? '', // Provide default if missing
      role: data['role'] as String? ?? 'student', // Default to 'student' if missing
      isVerified: data['isVerified'] as bool? ?? false, // Default to false if missing
      school: data['school'] as String?,
      department: data['department'] as String?,
      course: data['course'] as String?,
      registrationNumber: data['registrationNumber'] as String?,
      yearOfStudy: data['yearOfStudy'] as String?, 
      semester: data['semester'] as String?,       
      createdAt: parseTimestamp(data['createdAt']),
    );
  }

  factory User.fromApiJson(Map<String, dynamic> data) {
    final rawCreatedAt = data['createdAt'];
    DateTime? createdAt;
    if (rawCreatedAt is Timestamp) {
      createdAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is String) {
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
      createdAt: createdAt == null ? null : Timestamp.fromDate(createdAt),
    );
  }

  // --- Method to convert User object to a Map for Firestore ---
  // This is typically used when *creating* or *updating* data FROM the client.
  Map<String, dynamic> toFirestore() {
    return {
      // 'id' is the document ID, not stored as a field within the document.
      // 'uid' might be stored explicitly if needed for queries (as done in AuthService).
      'uid': id,
      'name': name,
      'email': email,
      'phoneNumber': phoneNumber, 
      'role': role,
      'isVerified': isVerified, // verification status (might be updated by backend trigger/function)

      // Only include non-null values for optional fields
      if (school != null) 'school': school,
      if (department != null) 'department': department,
      if (course != null) 'course': course,

      // student-specific fields only if they are non-null (relevant for students)
      if (registrationNumber != null) 'registrationNumber': registrationNumber,
      if (yearOfStudy != null) 'yearOfStudy': yearOfStudy, 
      if (semester != null) 'semester': semester,
    };
  }

  // --- Utility Methods (copyWith, toString, ==, hashCode) ---

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
    Timestamp? createdAt,
    // Flags to explicitly set nullable fields to null
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
