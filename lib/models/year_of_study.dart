
import 'package:cloud_firestore/cloud_firestore.dart';

class YearOfStudy {
  final String id;
  final String name;

  YearOfStudy({required this.id, required this.name});

  factory YearOfStudy.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return YearOfStudy(
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
