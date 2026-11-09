// lib/models/year_of_study.dart
import 'package:flutter/foundation.dart';

class YearOfStudy {
  final String id;
  final String name;

  YearOfStudy({required this.id, required this.name});

  YearOfStudy copyWith({
    String? id,
    String? name,
  }) {
    return YearOfStudy(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  @override
  String toString() => 'YearOfStudy(id: $id, name: $name)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is YearOfStudy && other.id == id && other.name == name;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}
