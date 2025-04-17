import 'package:cloud_firestore/cloud_firestore.dart';

class Attendance {
  final String id;
  final String lectureId;
  final String userId;
  final String visitNumber;
  final DateTime? checkInTime;
  final bool CheckedIn;

  Attendance({
    required this.id,
    required this.lectureId,
    required this.userId,
    required this.visitNumber,
    this.checkInTime,
    required this.CheckedIn,
  });

  Map<String, dynamic> toMap() {
    return {
      'lectureId': lectureId,
      'userId': userId,
      'visitNumber': visitNumber,
      'checkInTime': checkInTime,
      'CheckedIn': CheckedIn,
    };
  }

  factory Attendance.fromMap(Map<String, dynamic> map, String id) {
    return Attendance(
      id: id,
      lectureId: map['lectureId'] ?? '',
      userId: map['userId'] ?? '',
      visitNumber: map['visitNumber'] ?? '',
      checkInTime: map['checkInTime'] != null ? (map['checkInTime'] as Timestamp).toDate() : null,
      CheckedIn: map['CheckedIn'] ?? false,
    );
  }
}
