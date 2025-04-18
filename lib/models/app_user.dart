// lib/models/app_user.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class User {
  final String id; // Firestore document ID (should match Firebase Auth UID)
  final String name;
  final String email;
  final String role; // 'student' or 'lecturer'
  final String? school;
  final String? department;
  final String? course;
  final String? registrationNumber; // Added for students, nullable

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    this.school,
    this.department,
    this.course,
    this.registrationNumber, // Added
  });

  // --- Factory constructor to create a User from a Firestore DocumentSnapshot ---
  factory User.fromFirestore(DocumentSnapshot doc) {
    // Get the data map, ensuring it's not null
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};

    return User(
      id: doc.id, // Use the document ID from the snapshot
      name: data['name'] ?? '', // Get name, default if missing
      email: data['email'] ?? '', // Get email, default if missing
      role: data['role'] ?? 'student', // Get role, default to 'student' if missing
      school: data['school'] as String?, // Get school, cast as nullable String
      department: data['department'] as String?, // Get department
      course: data['course'] as String?, // Get course
      registrationNumber: data['registrationNumber'] as String?, // Added: Get registration number
    );
  }

  // --- Method to convert User object to a Map for Firestore ---
  Map<String, dynamic> toFirestore() {
    return {
      // 'id' is the document ID, not stored as a field within the document
      'name': name,
      'email': email,
      'role': role,
      // Only include non-null values
      if (school != null) 'school': school,
      if (department != null) 'department': department,
      if (course != null) 'course': course,
      if (registrationNumber != null) 'registrationNumber': registrationNumber, // Added
      // 'createdAt' could be added here using FieldValue.serverTimestamp() during creation
      // 'createdAt': FieldValue.serverTimestamp(), // Example for creation time
    };
  }

  // --- Optional: Add copyWith, toString, ==, hashCode for convenience ---

   User copyWith({
    String? id,
    String? name,
    String? email,
    String? role,
    String? school,
    String? department,
    String? course,
    String? registrationNumber, // Added
    // Flags to explicitly set fields to null if needed
    bool setSchoolNull = false,
    bool setDepartmentNull = false,
    bool setCourseNull = false,
    bool setRegistrationNumberNull = false, // Added
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      school: setSchoolNull ? null : (school ?? this.school),
      department: setDepartmentNull ? null : (department ?? this.department),
      course: setCourseNull ? null : (course ?? this.course),
      registrationNumber: setRegistrationNumberNull ? null : (registrationNumber ?? this.registrationNumber), // Added
    );
  }

   @override
  String toString() {
    return 'User(id: $id, name: $name, email: $email, role: $role, school: $school, department: $department, course: $course, registrationNumber: $registrationNumber)'; // Added registrationNumber
  }

   @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is User &&
      other.id == id &&
      other.name == name &&
      other.email == email &&
      other.role == role &&
      other.school == school &&
      other.department == department &&
      other.course == course &&
      other.registrationNumber == registrationNumber; // Added registrationNumber
  }

   @override
  int get hashCode {
    return id.hashCode ^
      name.hashCode ^
      email.hashCode ^
      role.hashCode ^
      school.hashCode ^
      department.hashCode ^
      course.hashCode ^
      registrationNumber.hashCode; // Added registrationNumber
  }
}
