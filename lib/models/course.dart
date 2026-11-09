// lib/models/course.dart
import 'package:flutter/foundation.dart';

class Course {
  final String id;
  final String name;
  final String departmentId;

  Course({required this.id, required this.name, required this.departmentId});

  Course copyWith({
    String? id,
    String? name,
    String? departmentId,
  }) {
    return Course(
      id: id ?? this.id,
      name: name ?? this.name,
      departmentId: departmentId ?? this.departmentId,
    );
  }

  @override
  String toString() => 'Course(id: $id, name: $name, departmentId: $departmentId)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Course &&
      other.id == id &&
      other.name == name &&
      other.departmentId == departmentId;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ departmentId.hashCode;
}
