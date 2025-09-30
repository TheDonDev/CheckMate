
import 'package:cloud_firestore/cloud_firestore.dart';

class Venue {
  final String id;
  final String name;

  Venue({required this.id, required this.name});

  factory Venue.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Venue(
      id: doc.id,
      name: data['name'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
    };
  }
}
