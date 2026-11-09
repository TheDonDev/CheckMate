// lib/utils/date_utils.dart
DateTime? parseTimestamp(dynamic timestampData) {
  if (timestampData == null) return null;
  if (timestampData is String) {
    try {
      return DateTime.parse(timestampData);
    } catch (_) {
      return null;
    }
  } else if (timestampData is Map && timestampData.containsKey('_seconds')) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(
        (timestampData['_seconds'] as int) * 1000 +
            (timestampData['_nanoseconds'] as int? ?? 0) ~/ 1000000,
      );
    } catch (_) {
      return null;
    }
  } else if (timestampData is int) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(timestampData);
    } catch (_) {
      return null;
    }
  }
  return null;
}

String? toIso8601String(dynamic dateOrTimestamp) {
  if (dateOrTimestamp == null) return null;
  if (dateOrTimestamp is DateTime) {
    return dateOrTimestamp.toIso8601String();
  }
  if (dateOrTimestamp is String) {
    return dateOrTimestamp;
  }
  return null;
}
