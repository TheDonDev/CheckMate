// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io'; // Only needed for HttpStatus and Platform checks
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth
import 'package:flutter/foundation.dart' show kIsWeb; // Import kIsWeb constant
import 'package:http/http.dart' as http;

// Define Custom Exceptions for better error handling
class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, {this.statusCode});

  @override
  String toString() => message; // Keep it simple for SnackBar display
}

class ApiService {
  // --- Base URL Determination ----
  static const String _localIp = '192.168.50.156'; // <--- My IPv4 Address.
  static const String _androidEmulatorIp = '10.0.2.2';
  static const String _port = '5000'; // Your backend port

  // Select the base URL based on the platform
  late final String _baseUrl;

  ApiService() {
     if (kIsWeb) {
       // For web testing, assuming backend runs on localhost
       _baseUrl = 'http://localhost:$_port/api/firebase';
     } else {
       // Use dart:io Platform check only on non-web platforms
       try {
         if (Platform.isAndroid) {
           // Use 10.0.2.2 for Android Emulator to reach host's localhost
           _baseUrl = 'http://$_androidEmulatorIp:$_port/api/firebase';
         } else if (Platform.isIOS) {
           // Use localhost for iOS Simulator if backend is on the same Mac
           // Use _localIp if backend is on a different machine or for physical devices
           _baseUrl = 'http://localhost:$_port/api/firebase'; // Or use _localIp
         } else {
           // Default for other platforms (Linux, Windows, macOS desktop)
           _baseUrl = 'http://$_localIp:$_port/api/firebase';
         }
       } catch (e) {
         // Fallback if Platform check fails unexpectedly (e.g., unsupported platform)
         print("Platform check failed, defaulting to local IP: $e");
         _baseUrl = 'http://$_localIp:$_port/api/firebase';
       }
     }
     print("ApiService initialized with Base URL: $_baseUrl");
  }
  // --- End Base URL Determination ---


  // Helper to get Headers including Firebase Auth ID Token
  Future<Map<String, String>> _getHeaders({bool includeContentType = true}) async {
    final headers = <String, String>{};
    if (includeContentType) {
      headers['Content-Type'] = 'application/json; charset=UTF-8';
    }
    headers['Accept'] = 'application/json';

    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        final idToken = await user.getIdToken(false); // Get token
        if (idToken != null) {
          headers['Authorization'] = 'Bearer $idToken'; // Add Bearer token
          // print("Auth Token included in headers."); // Debug log
        } else {
           print("Warning: Could not get ID token for authenticated user.");
        }
      } catch (e) {
         print("Error getting ID token: $e");
         // Consider throwing ApiException if auth is critical
         // throw ApiException("Failed to retrieve authentication token: $e", statusCode: 500);
      }
    } else {
       print("Warning: No authenticated user found for API request (if required).");
       // Consider throwing ApiException if auth is critical
       // throw ApiException("User not authenticated.", statusCode: 401);
    }
    return headers;
  }


  // Helper for handling HTTP responses and errors
  dynamic _handleResponse(http.Response response) {
    final String responseBody = response.body;
    print("API Response (${response.statusCode}) to ${response.request?.method} ${response.request?.url}: ${responseBody.length > 500 ? '${responseBody.substring(0, 500)}...' : responseBody}");

    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        if (responseBody.isEmpty && response.statusCode == HttpStatus.noContent) {
          return null; // Handle 204 No Content
        }
        return jsonDecode(responseBody);
      } catch (e) {
        print("API Success Response JSON Decode Error: $e");
        throw ApiException('Failed to parse successful response from server.', statusCode: response.statusCode);
      }
    } else {
      // Handle errors (4xx, 5xx)
      String errorMessage = 'API Error';
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
      print("API Error ($statusCode): $errorMessage");
      throw ApiException(errorMessage, statusCode: statusCode);
    }
  }


  // --- Lectures API Methods ---

  /// Fetches lectures created by a specific lecturer.
  Future<List<Lecture>> getLecturesForLecturer(String lecturerId) async {
    // --- CORRECTED ENDPOINT PATH ---
    final uri = Uri.parse('$_baseUrl/lectures/lecturer/$lecturerId');
    print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false), // Auth needed
      );
      final List<dynamic> data = _handleResponse(response);
      // Assuming Lecture.fromApiJson handles Firestore Timestamps correctly
      return data.map((item) => Lecture.fromApiJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
        print("Error in getLecturesForLecturer: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch lecturer's lectures: ${e.toString()}");
    }
  }

  /// Fetches lectures relevant to a student based on filters.
  Future<List<Lecture>> getStudentLectures(
      String? school, String? department, String? course, String? year, String? semester) async {
    final queryParams = <String, String>{
      // Use field names expected by the *corrected* backend route
      if (school != null && school.isNotEmpty) 'school': school,
      if (department != null && department.isNotEmpty) 'department': department,
      if (course != null && course.isNotEmpty) 'course': course,
      if (year != null && year.isNotEmpty) 'yearOfStudy': year, // Match backend
      if (semester != null && semester.isNotEmpty) 'semester': semester, // Match backend
    };

    // --- VALIDATE REQUIRED FILTERS ---
    // Assuming year and semester are always required for student view
    if (year == null || year.isEmpty || semester == null || semester.isEmpty) {
        print("Warning: Year and Semester filters are required for student lectures.");
        // Return empty list or throw error depending on desired UX
        return [];
        // throw ApiException("Year and Semester filters are required.");
    }

    final uri = Uri.parse('$_baseUrl/lectures/student').replace(queryParameters: queryParams);
    print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        // Include Auth if students need to be logged in to view lectures
        headers: await _getHeaders(includeContentType: false),
      );
      final List<dynamic> data = _handleResponse(response);
      return data.map((item) => Lecture.fromApiJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
        print("Error in getStudentLectures: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch student lectures: ${e.toString()}");
    }
  }

  /// Creates a new lecture via the backend API.
  Future<Lecture> createLecture(Lecture lecture) async {
    final uri = Uri.parse('$_baseUrl/lectures');
    // Ensure lecture.toApiJson() creates the correct JSON structure expected by backend
    final requestBody = jsonEncode(lecture.toApiJson());
    print("API Request: POST $uri with body: $requestBody");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(), // Auth needed
        body: requestBody,
      );
      final Map<String, dynamic> data = _handleResponse(response);
      return Lecture.fromApiJson(data); // Expect created lecture back
    } catch (e) {
        print("Error in createLecture: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to create lecture: ${e.toString()}");
    }
  }

  // --- Attendance API Methods (Keep as they were, assuming endpoints are correct) ---

  Future<AttendanceRecord> joinLecture(String lectureId, String userId) async {
    final uri = Uri.parse('$_baseUrl/attendance/join/$lectureId');
    final requestBody = jsonEncode({'userId': userId}); // Backend might get userId from token
     print("API Request: POST $uri with body: $requestBody");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: requestBody,
      );
      final Map<String, dynamic> data = _handleResponse(response);
      return AttendanceRecord.fromApiJson(data);
    } catch (e) {
        print("Error in joinLecture: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to join lecture: ${e.toString()}");
    }
  }

  Future<AttendanceRecord> checkInStudent(String lectureId, String visitNumber, String lecturerId) async {
    final uri = Uri.parse('$_baseUrl/attendance/checkin');
    final requestBody = jsonEncode({
        'lectureId': lectureId,
        'visitNumber': visitNumber,
        'lecturerId': lecturerId // Backend might get lecturerId from token
      });
    print("API Request: POST $uri with body: $requestBody");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: requestBody,
      );
      final Map<String, dynamic> data = _handleResponse(response);
      return AttendanceRecord.fromApiJson(data);
    } catch (e) {
        print("Error in checkInStudent: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to check in student: ${e.toString()}");
    }
  }

  Future<Map<String, dynamic>> getStudentAttendanceSummary(String userId) async {
    final uri = Uri.parse('$_baseUrl/attendance/student/$userId');
    print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false),
        );
      return _handleResponse(response);
    } catch (e) {
        print("Error in getStudentAttendanceSummary: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch student attendance summary: ${e.toString()}");
    }
  }

  Future<List<AttendanceRecord>> getLectureAttendance(String lectureId) async {
    final uri = Uri.parse('$_baseUrl/attendance/lecture/$lectureId');
    print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false),
        );
      final List<dynamic> data = _handleResponse(response);
      return data.map((item) => AttendanceRecord.fromApiJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
        print("Error in getLectureAttendance: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch lecture attendance: ${e.toString()}");
    }
  }
}
