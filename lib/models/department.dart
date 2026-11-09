// lib/models/department.dart
import 'package:flutter/foundation.dart';

class Department {
  final String id;
  final String name;
  final String schoolId;

  Department({required this.id, required this.name, required this.schoolId});

  Department copyWith({
    String? id,
    String? name,
    String? schoolId,
  }) {
    return Department(
      id: id ?? this.id,
      name: name ?? this.name,
      schoolId: schoolId ?? this.schoolId,
    );
  }

  @override
  String toString() => 'Department(id: $id, name: $name, schoolId: $schoolId)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Department &&
      other.id == id &&
      other.name == name &&
      other.schoolId == schoolId;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ schoolId.hashCode;
}
