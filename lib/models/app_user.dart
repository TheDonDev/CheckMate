// lib/models/app_user.dart
import 'package:cloud_firestore/cloud_firestore.dart';

class User {
  final String id; // Firestore document ID
  final String uid; // Firebase Auth UID (often same as id)
  final String name;
  final String email;
  final String role; // e.g., 'student', 'lecturer'
  final String? school; // Nullable if not always present
  final String? department; // Nullable
  final String? course; // Nullable
  final DateTime? createdAt; // Nullable or provide default

  User({
    required this.id,
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.school,
    this.department,
    this.course,
    this.createdAt,
  });

  // --- Factory constructor to create a User from a Firestore DocumentSnapshot ---
  factory User.fromFirestore(DocumentSnapshot doc) {
    // Get the data map, ensuring it's not null
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>? ?? {};

    // Helper to safely convert Firestore Timestamp to DateTime
    DateTime? timestampToDateTime(Timestamp? timestamp) {
      return timestamp?.toDate();
    }

    return User(
      id: doc.id, // Use the document ID from the snapshot
      uid: data['uid'] ?? '', // Get UID from data, default to empty string
      name: data['name'] ?? '', // Get name, default if missing
      email: data['email'] ?? '', // Get email, default if missing
      role: data['role'] ?? 'student', // Get role, default to 'student' if missing
      school: data['school'] as String?, // Get school, cast as nullable String
      department: data['department'] as String?, // Get department
      course: data['course'] as String?, // Get course
      createdAt: timestampToDateTime(data['createdAt'] as Timestamp?), // Convert timestamp
    );
  }

  // --- Method to convert User object to a Map for Firestore ---
  // Useful for updating user data, though signup uses a manual map currently
  Map<String, dynamic> toFirestore() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'role': role,
      // Only include non-null values if desired, or use FieldValue.delete
      if (school != null) 'school': school,
      if (department != null) 'department': department,
      if (course != null) 'course': course,
      // Use FieldValue.serverTimestamp() when creating/updating if possible
      // Otherwise, convert DateTime back to Timestamp if storing a specific time
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
    };
  }

  // --- Optional: Add copyWith, toString, ==, hashCode for convenience ---

   User copyWith({
    String? id,
    String? uid,
    String? name,
    String? email,
    String? role,
    String? school,
    String? department,
    String? course,
    DateTime? createdAt,
    // Flags to explicitly set fields to null if needed
    bool setSchoolNull = false,
    bool setDepartmentNull = false,
    bool setCourseNull = false,
    bool setCreatedAtNull = false,
  }) {
    return User(
      id: id ?? this.id,
      uid: uid ?? this.uid,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      school: setSchoolNull ? null : (school ?? this.school),
      department: setDepartmentNull ? null : (department ?? this.department),
      course: setCourseNull ? null : (course ?? this.course),
      createdAt: setCreatedAtNull ? null : (createdAt ?? this.createdAt),
    );
  }

   @override
  String toString() {
    return 'User(id: $id, uid: $uid, name: $name, email: $email, role: $role, school: $school, department: $department, course: $course, createdAt: $createdAt)';
  }

   @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is User &&
      other.id == id &&
      other.uid == uid &&
      other.name == name &&
      other.email == email &&
      other.role == role &&
      other.school == school &&
      other.department == department &&
      other.course == course &&
      other.createdAt == createdAt;
  }

   @override
  int get hashCode {
    return id.hashCode ^
      uid.hashCode ^
      name.hashCode ^
      email.hashCode ^
      role.hashCode ^
      school.hashCode ^
      department.hashCode ^
      course.hashCode ^
      createdAt.hashCode;
  }
}
