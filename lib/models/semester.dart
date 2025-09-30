
import 'package:cloud_firestore/cloud_firestore.dart';

class Semester {
  final String id;
  final String name;

  Semester({required this.id, required this.name});

  factory Semester.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Semester(
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
