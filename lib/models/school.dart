// lib/models/school.dart
import 'package:flutter/foundation.dart';

@immutable
class School {
  final String id;
  final String name;

  const School({required this.id, required this.name});

  School copyWith({
    String? id,
    String? name,
  }) {
    return School(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  @override
  String toString() => 'School(id: $id, name: $name)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is School && other.id == id && other.name == name;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}
