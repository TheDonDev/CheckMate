// lib/models/venue.dart
import 'package:flutter/foundation.dart';

class Venue {
  final String id;
  final String name;

  Venue({required this.id, required this.name});

  Venue copyWith({
    String? id,
    String? name,
  }) {
    return Venue(
      id: id ?? this.id,
      name: name ?? this.name,
    );
  }

  @override
  String toString() => 'Venue(id: $id, name: $name)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Venue && other.id == id && other.name == name;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode;
}
