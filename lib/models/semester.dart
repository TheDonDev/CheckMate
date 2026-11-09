// lib/models/semester.dart
import 'package:flutter/foundation.dart';

class Semester {
  final String id;
  final String name;

  Semester({required this.id, required this.name});

  Semester copyWith({
    String? id,
    String? name,
  }) {
    return Semester(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  @override
  String toString() => 'Semester(id: $id, name: $name)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Semester && other.id == id && other.name == name;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}
