// lib/services/api_service.dart
import 'dart:async'; // Import for TimeoutException
import 'dart:convert';
import 'dart:io';
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:http/http.dart' as http;

// Define Custom Exceptions for better error handling
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message;
}

class ApiService {
  // --- Base URL Determination ----
  static const String _localIp = '192.168.50.156'; // Your local IP
  static const String _androidEmulatorIp = '10.0.2.2';
  static const String _port = '5000';
  // static const String _firebaseFunctionsUrl = 'https://us-central1-checkmate-app-8489a.cloudfunctions.net/api'; // Example

  late final String _baseUrl;
  // Define a default timeout duration
  static const Duration _defaultTimeout = Duration(seconds: 25); // Increased timeout

  ApiService() {
    const bool useFirebaseFunctions = false;
    const String localApiPath = '/api/firebase';
    const String functionsApiPath = '/api';

    if (useFirebaseFunctions) {
      // _baseUrl = _firebaseFunctionsUrl + functionsApiPath;
       _baseUrl = 'https://us-central1-checkmate-app-8489a.cloudfunctions.net/api' + functionsApiPath; // Example
      if (kDebugMode) print("ApiService using Firebase Functions URL: $_baseUrl");
    } else {
      if (kIsWeb) {
        _baseUrl = 'http://localhost:$_port$localApiPath';
      } else {
        try {
          if (Platform.isAndroid) {
            _baseUrl = 'http://$_androidEmulatorIp:$_port$localApiPath';
          } else if (Platform.isIOS) {
            _baseUrl = 'http://localhost:$_port$localApiPath';
          } else {
            _baseUrl = 'http://localhost:$_port$localApiPath';
          }
        } catch (e) {
          if (kDebugMode) print("Platform check failed, defaulting to localhost: $e");
          _baseUrl = 'http://localhost:$_port$localApiPath';
        }
      }
      if (kDebugMode) print("ApiService using Local/Self-Hosted URL: $_baseUrl");
    }
  }
  // --- End Base URL Determination ---


  // Helper to get Headers
  Future<Map<String, String>> _getHeaders({bool includeContentType = true}) async {
    // ... (previous code remains the same) ...
     final headers = <String, String>{};
    if (includeContentType) {
      headers['Content-Type'] = 'application/json; charset=UTF-8';
    }
    headers['Accept'] = 'application/json';

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final idToken = await user.getIdToken(false);
        if (idToken != null) {
          headers['Authorization'] = 'Bearer $idToken';
           if (kDebugMode) print("Auth Token included in headers.");
        } else {
           if (kDebugMode) print("Warning: Could not get ID token for authenticated user.");
           throw ApiException("Authentication token unavailable.", statusCode: 401);
        }
      } catch (e) {
         if (kDebugMode) print("Error getting ID token: $e");
         throw ApiException("Failed to retrieve authentication token. Please try logging in again.", statusCode: 401);
      }
    } else {
       if (kDebugMode) print("Warning: No authenticated user found for API request.");
       throw ApiException("User not authenticated. Please log in.", statusCode: 401);
    }
    return headers;
  }


  // Helper for handling HTTP responses
  dynamic _handleResponse(http.Response response) {
    // ... (previous code remains the same) ...
     final String responseBody = response.body;
    if (kDebugMode) print("API Response (${response.statusCode}) to ${response.request?.method} ${response.request?.url}: ${responseBody.length > 500 ? '${responseBody.substring(0, 500)}...' : responseBody}");

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        if (response.statusCode == HttpStatus.noContent || responseBody.isEmpty) {
          return null;
        }
        return jsonDecode(responseBody);
      } catch (e) {
        if (kDebugMode) print("API Success Response JSON Decode Error: $e");
        throw ApiException('Failed to parse successful response from server.', statusCode: response.statusCode);
      }
    } else {
      String errorMessage = 'An unknown API error occurred.';
      int? statusCode = response.statusCode;
      try {
        final errorBody = jsonDecode(responseBody);
        if (errorBody is Map) {
            errorMessage = errorBody['message'] ?? errorBody['error'] ?? errorBody['detail'] ?? jsonEncode(errorBody);
        } else if (errorBody is String) {
            errorMessage = errorBody;
        } else {
          errorMessage = responseBody;
        }
      } catch (_) {
         errorMessage = responseBody.isNotEmpty ? responseBody : 'HTTP Error $statusCode';
      }
      if (kDebugMode) print("API Error ($statusCode): $errorMessage");
      throw ApiException(errorMessage, statusCode: statusCode);
    }
  }


  // --- Lectures API Methods ---

  Future<List<Lecture>> getLecturesForLecturer(String lecturerId) async {
    final uri = Uri.parse('$_baseUrl/lectures/lecturer/$lecturerId');
    if (kDebugMode) print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false),
      ).timeout(_defaultTimeout); // Added timeout
      final List<dynamic> data = _handleResponse(response);
      return data.map((item) => Lecture.fromApiJson(item as Map<String, dynamic>)).toList();
    } on TimeoutException catch (_) {
        if (kDebugMode) print("Timeout fetching lecturer lectures for $lecturerId");
        throw ApiException("Request timed out. Please check your connection or try again later.", statusCode: 408);
    } catch (e) {
        if (kDebugMode) print("Error in getLecturesForLecturer: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch lecturer's lectures: ${e.toString()}");
    }
  }

  Future<List<Lecture>> getStudentLectures(
      String? school, String? department, String? course, String? year, String? semester) async {
    final queryParams = <String, String>{
      if (school != null && school.isNotEmpty) 'school': school,
      if (department != null && department.isNotEmpty) 'department': department,
      if (course != null && course.isNotEmpty) 'course': course,
      if (year != null && year.isNotEmpty) 'year': year,
      if (semester != null && semester.isNotEmpty) 'semester': semester,
    };

    if (school == null || school.isEmpty || department == null || department.isEmpty || course == null || course.isEmpty || year == null || year.isEmpty || semester == null || semester.isEmpty) {
        throw ApiException("All filters (School, Department, Course, Year, Semester) must be selected to find lectures.");
    }

    final uri = Uri.parse('$_baseUrl/lectures/student').replace(queryParameters: queryParams);
    if (kDebugMode) print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false),
      ).timeout(_defaultTimeout); // Added timeout
      final List<dynamic> data = _handleResponse(response);
      return data.map((item) => Lecture.fromApiJson(item as Map<String, dynamic>)).toList();
    } on TimeoutException catch (_) {
        if (kDebugMode) print("Timeout fetching student lectures with filters: $queryParams");
        throw ApiException("Request timed out. Please check your connection or try again later.", statusCode: 408);
    } catch (e) {
        if (kDebugMode) print("Error in getStudentLectures: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch student lectures: ${e.toString()}");
    }
  }

  Future<Lecture> createLecture(Lecture lecture) async {
    final uri = Uri.parse('$_baseUrl/lectures');
    final requestBody = jsonEncode(lecture.toApiJson());
    if (kDebugMode) print("API Request: POST $uri with body: $requestBody");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: requestBody,
      ).timeout(_defaultTimeout); // Added timeout
      final Map<String, dynamic> data = _handleResponse(response);
      return Lecture.fromApiJson(data);
    } on TimeoutException catch (_) {
        if (kDebugMode) print("Timeout creating lecture");
        throw ApiException("Request timed out. Please check your connection or try again later.", statusCode: 408);
    } catch (e) {
        if (kDebugMode) print("Error in createLecture: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to create lecture: ${e.toString()}");
    }
  }

  Future<Lecture> updateLecture(String lectureId, Map<String, dynamic> lectureData) async {
    final uri = Uri.parse('$_baseUrl/lectures/$lectureId');
    final requestBody = jsonEncode(lectureData);
    if (kDebugMode) print("API Request: PUT $uri with body: $requestBody");
    try {
      final response = await http.put(
        uri,
        headers: await _getHeaders(),
        body: requestBody,
      ).timeout(_defaultTimeout); // Added timeout
      final Map<String, dynamic> data = _handleResponse(response);
      return Lecture.fromApiJson(data);
    } on TimeoutException catch (_) {
        if (kDebugMode) print("Timeout updating lecture $lectureId");
        throw ApiException("Request timed out. Please check your connection or try again later.", statusCode: 408);
    } catch (e) {
        if (kDebugMode) print("Error in updateLecture: $e");
        if (e is ApiException) { /* ... specific error handling ... */ rethrow; }
        throw ApiException("Failed to update lecture: ${e.toString()}");
    }
  }


  // --- Attendance API Methods ---

  Future<AttendanceRecord> joinLecture(String lectureId) async {
    final uri = Uri.parse('$_baseUrl/attendance/join/$lectureId');
    if (kDebugMode) print("API Request (Student Join): POST $uri");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(includeContentType: false),
      ).timeout(_defaultTimeout); // Added timeout
      final Map<String, dynamic> data = _handleResponse(response);
      return AttendanceRecord.fromApiJson(data);
    } on TimeoutException catch (_) {
        if (kDebugMode) print("Timeout joining lecture $lectureId");
        throw ApiException("Request timed out. Please check your connection or try again later.", statusCode: 408);
    } catch (e) {
        if (kDebugMode) print("Error in joinLecture: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to join lecture: ${e.toString()}");
    }
  }

  Future<AttendanceRecord> checkInViaLectureQr(String lectureId) async {
    final uri = Uri.parse('$_baseUrl/attendance/checkin/student/$lectureId');
    if (kDebugMode) print("API Request (Student Check-In via QR): POST $uri");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(includeContentType: false),
      ).timeout(_defaultTimeout); // Added timeout
      final Map<String, dynamic> data = _handleResponse(response);
      return AttendanceRecord.fromApiJson(data);
    } on TimeoutException catch (_) {
        if (kDebugMode) print("Timeout checking in via QR for lecture $lectureId");
        throw ApiException("Request timed out. Please check your connection or try again later.", statusCode: 408);
    } catch (e) {
        if (kDebugMode) print("Error in checkInViaLectureQr: $e");
        if (e is ApiException) { /* ... specific error handling ... */ rethrow; }
        throw ApiException("Failed to check-in via QR: ${e.toString()}");
    }
  }

  Future<AttendanceRecord> checkInStudent(String lectureId, String registrationNumber) async {
    final uri = Uri.parse('$_baseUrl/attendance/checkin');
    final requestBody = jsonEncode({
        'lectureId': lectureId,
        'registrationNumber': registrationNumber,
      });
    if (kDebugMode) print("API Request (Lecturer Check-In): POST $uri with body: $requestBody");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: requestBody,
      ).timeout(_defaultTimeout); // Added timeout
      final Map<String, dynamic> data = _handleResponse(response);
      return AttendanceRecord.fromApiJson(data);
    } on TimeoutException catch (_) {
        if (kDebugMode) print("Timeout checking in student $registrationNumber for lecture $lectureId");
        throw ApiException("Request timed out. Please check your connection or try again later.", statusCode: 408);
    } catch (e) {
        if (kDebugMode) print("Error in checkInStudent: $e");
        if (e is ApiException) { /* ... specific error handling ... */ rethrow; }
        throw ApiException("Failed to check in student: ${e.toString()}");
    }
  }

  Future<List<AttendanceRecord>> getLectureAttendance(String lectureId) async {
    final uri = Uri.parse('$_baseUrl/attendance/lecture/$lectureId');
    if (kDebugMode) print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false),
        ).timeout(_defaultTimeout); // Added timeout
      final List<dynamic> data = _handleResponse(response);
      // Add robust parsing for the list items
      return data.map((item) {
          try {
              return AttendanceRecord.fromApiJson(item as Map<String, dynamic>);
          } catch (parseError) {
              if (kDebugMode) print("Error parsing individual attendance record: $parseError, Data: $item");
              // Depending on requirements, you might:
              // 1. Skip the record: return null and filter later (see below)
              // 2. Throw an error to fail the whole request
              // 3. Return a default/placeholder record
              return null; // Option 1: Skip invalid records
          }
      }).whereType<AttendanceRecord>().toList(); // Filter out nulls if skipping
    } on TimeoutException catch (_) {
        if (kDebugMode) print("Timeout fetching attendance for lecture $lectureId");
        throw ApiException("Request timed out. Please check your connection or try again later.", statusCode: 408);
    } catch (e) {
        if (kDebugMode) print("Error in getLectureAttendance: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch lecture attendance: ${e.toString()}");
    }
  }

  Future<Map<String, dynamic>> getStudentAttendanceSummary(
    String userId, {
    String? year,
    String? semester,
  }) async {
    final queryParams = <String, String>{};
    if (year != null && year.isNotEmpty) queryParams['year'] = year;
    if (semester != null && semester.isNotEmpty) queryParams['semester'] = semester;

    final uri = Uri.parse('$_baseUrl/attendance/student/$userId').replace(
      queryParameters: queryParams.isNotEmpty ? queryParams : null,
    );

    if (kDebugMode) print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false),
        ).timeout(_defaultTimeout); // Added timeout
      final Map<String, dynamic> data = _handleResponse(response);

      // Data Sanitization & Parsing
      List<AttendanceRecord> records = [];
      if (data['attendanceRecords'] is List) {
         try {
           records = (data['attendanceRecords'] as List)
              .map((item) {
                  try {
                      return AttendanceRecord.fromApiJson(item as Map<String, dynamic>);
                  } catch (parseError) {
                      if (kDebugMode) print("Error parsing individual summary attendance record: $parseError, Data: $item");
                      return null; // Skip invalid records
                  }
              })
              .whereType<AttendanceRecord>() // Filter out nulls
              .toList();
         } catch (listError) {
            if (kDebugMode) print("Error processing attendanceRecords list: $listError");
         }
      }

      final String percentage = data['percentage']?.toString() ?? '0.00';
      final int totalLectures = data['totalLectures'] is int ? data['totalLectures'] : (int.tryParse(data['totalLectures']?.toString() ?? '0') ?? 0);
      final int attendedLectures = data['attendedLectures'] is int ? data['attendedLectures'] : (int.tryParse(data['attendedLectures']?.toString() ?? '0') ?? 0);

      return {
        'attendanceRecords': records,
        'percentage': percentage,
        'totalLectures': totalLectures,
        'attendedLectures': attendedLectures,
      };
    } on TimeoutException catch (_) {
        if (kDebugMode) print("Timeout fetching student summary for $userId");
        throw ApiException("Request timed out. Please check your connection or try again later.", statusCode: 408);
    } catch (e) {
        if (kDebugMode) print("Error in getStudentAttendanceSummary: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch student attendance summary: ${e.toString()}");
    }
  }

} // End of ApiService class
