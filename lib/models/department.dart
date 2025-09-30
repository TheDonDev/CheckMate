
import 'package:cloud_firestore/cloud_firestore.dart';

class Department {
  final String id;
  final String name;
  final String schoolId;

  Department({required this.id, required this.name, required this.schoolId});

  factory Department.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Department(
      id: doc.id,
      name: data['name'] ?? '',
      schoolId: data['schoolId'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'schoolId': schoolId,
    };
  }
}
