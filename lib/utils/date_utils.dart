// lib/utils/date_utils.dart
import 'package:cloud_firestore/cloud_firestore.dart'; // Keep for Timestamp type

Timestamp? parseTimestamp(dynamic timestampData) {
  if (timestampData == null) return null;
  if (timestampData is String) {
    try {
      return Timestamp.fromDate(DateTime.parse(timestampData));
    } catch (e) {
      print("Error parsing timestamp string: $timestampData, Error: $e");
      return null;
    }
  } else if (timestampData is Map && timestampData.containsKey('_seconds')) {
    return Timestamp(timestampData['_seconds'], timestampData['_nanoseconds'] ?? 0);
  } else if (timestampData is int) {
    return Timestamp.fromMillisecondsSinceEpoch(timestampData);
  }
  print("Unrecognized timestamp format: $timestampData");
  return null;
}

String? toIso8601String(dynamic dateOrTimestamp) {
  if (dateOrTimestamp == null) return null;
  if (dateOrTimestamp is Timestamp) {
    return dateOrTimestamp.toDate().toIso8601String();
  } else if (dateOrTimestamp is DateTime) {
    return dateOrTimestamp.toIso8601String();
  }
  return null;
}
