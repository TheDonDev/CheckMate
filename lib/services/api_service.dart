// lib/services/api_service.dart
import 'dart:convert';
import 'dart:io'; // Only needed for HttpStatus and Platform checks
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:firebase_auth/firebase_auth.dart'; // Import FirebaseAuth
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode; // Import kIsWeb/kDebugMode
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
  // TODO: Replace with your actual IP/domain and port
  static const String _localIp = '192.168.50.156'; // <-- Replace with your machine's local IP if testing on physical device
  static const String _androidEmulatorIp = '10.0.2.2'; // Standard for Android Emulator
  static const String _port = '5000'; // Your backend port (e.g., Flask, Node)
  // TODO: Replace with your deployed Firebase Functions URL if applicable
  // static const String _firebaseFunctionsUrl = 'https://your-region-your-project-id.cloudfunctions.net/api';

  // Select the base URL based on the platform and environment
  late final String _baseUrl;

  ApiService() {
    // --- CHOOSE YOUR BACKEND TYPE ---
    const bool useFirebaseFunctions = false; // Set to true if using Firebase Functions backend
    // --------------------------------

    if (useFirebaseFunctions) {
      // TODO: Uncomment and set your Firebase Functions URL
      // _baseUrl = _firebaseFunctionsUrl;
      // Placeholder if not set:
      _baseUrl = 'https://us-central1-checkmate-app-8489a.cloudfunctions.net/api'; // Example
      if (kDebugMode) print("ApiService using Firebase Functions URL: $_baseUrl");
    } else {
      // Determine URL for local/self-hosted backend
      if (kIsWeb) {
        // For web testing, assuming backend runs on localhost
        _baseUrl = 'http://localhost:$_port/api/firebase'; // Adjust path if needed
      } else {
        // Use dart:io Platform check only on non-web platforms
        try {
          if (Platform.isAndroid) {
            // Use 10.0.2.2 for Android Emulator to reach host's localhost
            _baseUrl = 'http://$_androidEmulatorIp:$_port/api/firebase'; // Adjust path if needed
          } else if (Platform.isIOS) {
            // Use localhost for iOS Simulator if backend is on the same Mac
            // Use _localIp if backend is on a different machine on the network
            _baseUrl = 'http://localhost:$_port/api/firebase'; // Or use _localIp, Adjust path if needed
          } else {
            // Default for other desktop platforms (Linux, Windows, macOS)
            // Assumes backend is accessible via the local IP
            _baseUrl = 'http://$_localIp:$_port/api/firebase'; // Adjust path if needed
          }
        } catch (e) {
          // Fallback if Platform check fails unexpectedly
          if (kDebugMode) print("Platform check failed, defaulting to local IP: $e");
          _baseUrl = 'http://$_localIp:$_port/api/firebase'; // Adjust path if needed
        }
      }
      if (kDebugMode) print("ApiService using Local/Self-Hosted URL: $_baseUrl");
    }
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
        // Force refresh? Set to true if you suspect token expiry issues often.
        final idToken = await user.getIdToken(false);
        if (idToken != null) {
          headers['Authorization'] = 'Bearer $idToken'; // Standard Bearer token format
           if (kDebugMode) print("Auth Token included in headers."); // Debug log
        } else {
           if (kDebugMode) print("Warning: Could not get ID token for authenticated user.");
           // Depending on API requirements, might need to throw here
           // throw ApiException("Authentication token unavailable.", statusCode: 401);
        }
      } catch (e) {
         if (kDebugMode) print("Error getting ID token: $e");
         // Throw an exception that can be caught and shown to the user
         throw ApiException("Failed to retrieve authentication token. Please try logging in again.", statusCode: 401);
      }
    } else {
       if (kDebugMode) print("Warning: No authenticated user found for API request.");
       // Throw an exception if authentication is strictly required for this endpoint
       // Example: For endpoints other than login/signup
       // throw ApiException("User not authenticated. Please log in.", statusCode: 401);
    }
    return headers;
  }


  // Helper for handling HTTP responses and errors
  dynamic _handleResponse(http.Response response) {
    final String responseBody = response.body;
    // Log request details and response status/body (truncated)
    if (kDebugMode) print("API Response (${response.statusCode}) to ${response.request?.method} ${response.request?.url}: ${responseBody.length > 500 ? '${responseBody.substring(0, 500)}...' : responseBody}");

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Success range (2xx)
      try {
        // Handle 204 No Content specifically
        if (response.statusCode == HttpStatus.noContent || responseBody.isEmpty) {
          return null;
        }
        // Decode JSON for other successful responses
        return jsonDecode(responseBody);
      } catch (e) {
        if (kDebugMode) print("API Success Response JSON Decode Error: $e");
        // Throw specific exception for parsing failure on success
        throw ApiException('Failed to parse successful response from server.', statusCode: response.statusCode);
      }
    } else {
      // Error range (4xx, 5xx)
      String errorMessage = 'An unknown API error occurred.';
      int? statusCode = response.statusCode;
      try {
        // Attempt to parse error message from JSON body
        final errorBody = jsonDecode(responseBody);
        if (errorBody is Map) {
            // Look for common error message keys
            errorMessage = errorBody['message'] ?? errorBody['error'] ?? errorBody['detail'] ?? jsonEncode(errorBody);
        } else if (errorBody is String) {
            // If the body is just a string error message
            errorMessage = errorBody;
        } else {
          // Fallback if body is not a map or string
          errorMessage = responseBody;
        }
      } catch (_) {
         // If body isn't valid JSON, use the raw body or status code
         errorMessage = responseBody.isNotEmpty ? responseBody : 'HTTP Error $statusCode';
      }
      if (kDebugMode) print("API Error ($statusCode): $errorMessage");
      // Throw custom exception with message and status code
      throw ApiException(errorMessage, statusCode: statusCode);
    }
  }


  // --- Lectures API Methods ---

  /// Fetches lectures created by a specific lecturer.
  Future<List<Lecture>> getLecturesForLecturer(String lecturerId) async {
    // Endpoint assumes backend route is /lectures/lecturer/{lecturerId}
    final uri = Uri.parse('$_baseUrl/lectures/lecturer/$lecturerId');
    if (kDebugMode) print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false), // Auth likely needed
      );
      final List<dynamic> data = _handleResponse(response);
      // Map the JSON list to a list of Lecture objects
      return data.map((item) => Lecture.fromApiJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
        if (kDebugMode) print("Error in getLecturesForLecturer: $e");
        if (e is ApiException) rethrow; // Rethrow specific API exceptions
        throw ApiException("Failed to fetch lecturer's lectures: ${e.toString()}"); // Wrap other errors
    }
  }

  /// Fetches lectures relevant to a student based on filters.
  Future<List<Lecture>> getStudentLectures(
      String? school, String? department, String? course, String? year, String? semester) async {
    final queryParams = <String, String>{
      // Use field names expected by the backend route
      if (school != null && school.isNotEmpty) 'school': school,
      if (department != null && department.isNotEmpty) 'department': department,
      if (course != null && course.isNotEmpty) 'course': course,
      if (year != null && year.isNotEmpty) 'yearOfStudy': year, // Ensure this matches backend parameter name
      if (semester != null && semester.isNotEmpty) 'semester': semester, // Ensure this matches backend parameter name
    };

    // Validate required filters (Year and Semester are crucial for student view)
    if (year == null || year.isEmpty || semester == null || semester.isEmpty) {
        if (kDebugMode) print("API Error: Year and Semester filters are required for student lectures.");
        // Throw an exception to be caught by the UI
        throw ApiException("Year and Semester must be selected to find lectures.");
    }

    // Endpoint assumes backend route is /lectures/student with query params
    final uri = Uri.parse('$_baseUrl/lectures/student').replace(queryParameters: queryParams);
    if (kDebugMode) print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false), // Auth likely needed
      );
      final List<dynamic> data = _handleResponse(response);
      return data.map((item) => Lecture.fromApiJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
        if (kDebugMode) print("Error in getStudentLectures: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch student lectures: ${e.toString()}");
    }
  }

  /// Creates a new lecture via the backend API.
  Future<Lecture> createLecture(Lecture lecture) async {
    // Endpoint assumes backend route is POST /lectures
    final uri = Uri.parse('$_baseUrl/lectures');
    // Use the lecture model's toApiJson method for the request body
    final requestBody = jsonEncode(lecture.toApiJson());
    if (kDebugMode) print("API Request: POST $uri with body: $requestBody");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(), // Auth needed
        body: requestBody,
      );
      final Map<String, dynamic> data = _handleResponse(response);
      // Expect the created lecture object back from the API
      return Lecture.fromApiJson(data);
    } catch (e) {
        if (kDebugMode) print("Error in createLecture: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to create lecture: ${e.toString()}");
    }
  }

  // --- Attendance API Methods ---

  /// Allows a student to join a lecture.
  /// Backend uses the auth token to get studentId and profile details.
  Future<AttendanceRecord> joinLecture(String lectureId) async {
    // Endpoint assumes backend route is POST /attendance/join/:lectureId
    // No request body needed as backend uses token and path param
    final uri = Uri.parse('$_baseUrl/attendance/join/$lectureId');
    if (kDebugMode) print("API Request: POST $uri");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(includeContentType: false), // Auth needed (student must be logged in), no body
      );
      final Map<String, dynamic> data = _handleResponse(response);
      // Expect the created/updated attendance record back
      return AttendanceRecord.fromApiJson(data);
    } catch (e) {
        if (kDebugMode) print("Error in joinLecture: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to join lecture: ${e.toString()}");
    }
  }

  /// Allows a lecturer to check in a student using their registration number.
  // *** CORRECTED SIGNATURE: Removed lecturerId parameter ***
  Future<AttendanceRecord> checkInStudent(String lectureId, String registrationNumber) async {
    // Endpoint assumes backend route is POST /attendance/checkin
    final uri = Uri.parse('$_baseUrl/attendance/checkin');
    final requestBody = jsonEncode({
        'lectureId': lectureId,
        'registrationNumber': registrationNumber, // Use registration number for lookup
        // 'lecturerId' is NOT sent; backend uses auth token
      });
    if (kDebugMode) print("API Request: POST $uri with body: $requestBody");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(), // Auth needed (lecturer must be logged in)
        body: requestBody,
      );
      final Map<String, dynamic> data = _handleResponse(response);
      // Expect the updated attendance record back
      return AttendanceRecord.fromApiJson(data);
    } catch (e) {
        if (kDebugMode) print("Error in checkInStudent: $e");
        // Provide more specific feedback based on potential API error messages
        if (e is ApiException) {
            if (e.statusCode == 404) { // Example: If backend returns 404 for not found/not joined
                throw ApiException('Check-in failed: Student with registration number $registrationNumber not found or has not joined this lecture.', statusCode: e.statusCode);
            } else if (e.statusCode == 409) { // Example: If backend returns 409 for already checked in
                 throw ApiException('Check-in failed: Student $registrationNumber is already checked in.', statusCode: e.statusCode);
            }
            // Add more specific status code handling if needed (e.g., 403 Forbidden)
            rethrow; // Rethrow other API exceptions
        }
        // Wrap generic errors
        throw ApiException("Failed to check in student: ${e.toString()}");
    }
  }

  /// Fetches attendance records for a specific lecture.
  Future<List<AttendanceRecord>> getLectureAttendance(String lectureId) async {
    // Endpoint assumes backend route is GET /attendance/lecture/{lectureId}
    final uri = Uri.parse('$_baseUrl/attendance/lecture/$lectureId');
    if (kDebugMode) print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false), // Auth likely needed
        );
      final List<dynamic> data = _handleResponse(response);
      // Map JSON list to AttendanceRecord list
      return data.map((item) => AttendanceRecord.fromApiJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
        if (kDebugMode) print("Error in getLectureAttendance: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch lecture attendance: ${e.toString()}");
    }
  }

  // --- Student Attendance Summary ---
  /// Fetches the student's attendance summary (records, percentage, counts).
  /// Backend calculates percentage based on relevant lectures for the student.
  Future<Map<String, dynamic>> getStudentAttendanceSummary(String userId) async {
    // Endpoint assumes backend route is GET /attendance/student/{userId}
    final uri = Uri.parse('$_baseUrl/attendance/student/$userId');
    if (kDebugMode) print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false), // Auth needed
        );
      // Expects a map like:
      // {
      //   "attendanceRecords": [...],
      //   "percentage": "80.00",
      //   "totalLectures": 10,
      //   "attendedLectures": 8
      // }
      final Map<String, dynamic> data = _handleResponse(response);

      // Parse the nested attendance records list
      if (data['attendanceRecords'] is List) {
         data['attendanceRecords'] = (data['attendanceRecords'] as List)
            .map((item) => AttendanceRecord.fromApiJson(item as Map<String, dynamic>))
            .toList();
      } else {
         // Handle case where attendanceRecords might be missing or not a list
         data['attendanceRecords'] = <AttendanceRecord>[];
      }
      // Ensure other fields exist, provide defaults if necessary
      data['percentage'] = data['percentage']?.toString() ?? '0.00';
      data['totalLectures'] = data['totalLectures'] as int? ?? 0;
      data['attendedLectures'] = data['attendedLectures'] as int? ?? 0;

      return data;
    } catch (e) {
        if (kDebugMode) print("Error in getStudentAttendanceSummary: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch student attendance summary: ${e.toString()}");
    }
  }

}
