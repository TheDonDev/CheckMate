// lib/services/lecture_service.dart
String? _toIso8601String(dynamic dateOrTimestamp) {
  if (dateOrTimestamp == null) return null;
  if (dateOrTimestamp is DateTime) {
    return dateOrTimestamp.toIso8601String();
  }
  if (dateOrTimestamp is String) {
    return dateOrTimestamp;
  }
  return null;
}

DateTime? _parseDateTime(dynamic timestampData) {
  if (timestampData == null) return null;
  if (timestampData is DateTime) return timestampData;
  if (timestampData is String) {
    try {
      return DateTime.parse(timestampData);
    } catch (_) {
      return null;
    }
  }
  if (timestampData is int) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(timestampData);
    } catch (_) {
      return null;
    }
  }
  return null;
}
