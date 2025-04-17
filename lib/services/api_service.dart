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
  // String toString() => "ApiException: $message (Status Code: $statusCode)"; // More detailed version
}

class ApiService {
  // --- Base URL Determination using --dart-define ---
  // Define compile-time constants using String.fromEnvironment.
  // These values are injected via the --dart-define flag during build/run.
  // Example Run Command:
  // flutter run --dart-define=BASE_URL_WEB=http://localhost:5001/your-project/us-central1/api --dart-define=BASE_URL_ANDROID=http://10.0.2.2:5001/your-project/us-central1/api
  static const String _webBaseUrl = String.fromEnvironment(
    'BASE_URL_WEB', // Variable name to define (e.g., --dart-define=BASE_URL_WEB=http://localhost:5000/api/firebase)
    defaultValue: 'http://localhost:5000/api/firebase', // Default for local web dev if not defined
  );
  static const String _mobileBaseUrlAndroid = String.fromEnvironment(
    'BASE_URL_ANDROID', // e.g., --dart-define=BASE_URL_ANDROID=http://10.0.2.2:5000/api/firebase
    defaultValue: 'http://10.0.2.2:5000/api/firebase', // Default for Android emulator
  );
  static const String _mobileBaseUrlIOS = String.fromEnvironment(
    'BASE_URL_IOS', // e.g., --dart-define=BASE_URL_IOS=http://localhost:5000/api/firebase
    defaultValue: 'http://localhost:5000/api/firebase', // Default for iOS simulator
  );
  // Add other platform defaults if needed (e.g., desktop)

  // Select the base URL based on the platform at runtime (kIsWeb is safe)
  // Platform.isAndroid/isIOS is only evaluated if kIsWeb is false.
  late final String _baseUrl;

  ApiService() {
     // Determine base URL in constructor or initializer list
     if (kIsWeb) {
       _baseUrl = _webBaseUrl;
     } else {
       // Use dart:io Platform check only on non-web platforms
       if (Platform.isAndroid) {
         _baseUrl = _mobileBaseUrlAndroid;
       } else if (Platform.isIOS) {
         _baseUrl = _mobileBaseUrlIOS;
       } else {
         // Default for other platforms (Linux, Windows, macOS) - adjust as needed
         _baseUrl = _mobileBaseUrlIOS; // Often localhost works for desktop too
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
    headers['Accept'] = 'application/json'; // Expect JSON responses

    // Attempt to get the current user's ID token for authorization
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        // Force refresh? Set to true if you suspect tokens might expire frequently
        // during testing, but false is usually fine for production.
        final idToken = await user.getIdToken(false);
        if (idToken != null) {
          headers['Authorization'] = 'Bearer $idToken';
        } else {
           print("Warning: Could not get ID token for authenticated user.");
           // Consider throwing an ApiException if auth is strictly required
           // throw ApiException("Authentication token unavailable.", statusCode: 401);
        }
      } catch (e) {
         print("Error getting ID token: $e");
         // Consider throwing an ApiException
         // throw ApiException("Failed to retrieve authentication token: $e", statusCode: 500);
      }
    } else {
       // Only print warning if request is intended for authenticated users
       // Some public endpoints might not require auth.
       print("Warning: No authenticated user found for API request (if required).");
       // Consider throwing an ApiException if auth is strictly required
       // throw ApiException("User not authenticated.", statusCode: 401);
    }
    return headers;
  }


  // Helper for handling HTTP responses and errors
  dynamic _handleResponse(http.Response response) {
    final String responseBody = response.body;
    // Log request URL along with response for better debugging
    print("API Response (${response.statusCode}) to ${response.request?.method} ${response.request?.url}: ${responseBody.length > 500 ? '${responseBody.substring(0, 500)}...' : responseBody}"); // Limit long responses

    // Check for successful status codes (2xx)
    if (response.statusCode >= 200 && response.statusCode < 300) {
      try {
        // Handle successful responses with no content (e.g., 204)
        if (responseBody.isEmpty && response.statusCode == HttpStatus.noContent) {
          return null;
        }
        // Decode JSON body for successful responses
        return jsonDecode(responseBody);
      } catch (e) {
        // Handle cases where the server returns 2xx but invalid JSON
        print("API Success Response JSON Decode Error: $e");
        throw ApiException('Failed to parse successful response from server.', statusCode: response.statusCode);
      }
    } else {
      // Handle client (4xx) or server (5xx) errors
      String errorMessage = 'API Error';
      int? statusCode = response.statusCode;
      try {
        // Attempt to parse a structured error message from the response body
        final errorBody = jsonDecode(responseBody);
        // Look for common error message keys (adjust based on your backend)
        if (errorBody is Map) {
            errorMessage = errorBody['message'] ?? errorBody['error'] ?? errorBody['detail'] ?? jsonEncode(errorBody);
        } else if (errorBody is String) {
            errorMessage = errorBody;
        } else {
          errorMessage = responseBody; // Use raw body if no known keys
        }
      } catch (_) {
         // Fallback if response body is not valid JSON
         errorMessage = responseBody.isNotEmpty ? responseBody : 'HTTP Error $statusCode';
      }
      print("API Error ($statusCode): $errorMessage");
      // Throw custom exception with message and status code
      throw ApiException(errorMessage, statusCode: statusCode);
    }
  }


  // --- Lectures API Methods ---

  /// Fetches lectures created by a specific lecturer.
  Future<List<Lecture>> getLecturesForLecturer(String lecturerId) async {
    final uri = Uri.parse('$_baseUrl/lectures/lecturer/$lecturerId');
    print("API Request: GET $uri"); // Log request
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false),
      );
      final List<dynamic> data = _handleResponse(response);
      // Map the JSON list to a list of Lecture objects
      return data.map((item) => Lecture.fromApiJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
        print("Error in getLecturesForLecturer: $e");
        // Re-throw as ApiException or handle appropriately
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch lecturer's lectures: ${e.toString()}");
    }
  }

  /// Fetches lectures relevant to a student based on filters.
  Future<List<Lecture>> getStudentLectures(
      String? school, String? department, String? course, String? year, String? semester) async {
    // Build query parameters, excluding null values
    final queryParams = <String, String>{
      if (school != null && school.isNotEmpty) 'school': school,
      if (department != null && department.isNotEmpty) 'department': department,
      if (course != null && course.isNotEmpty) 'course': course,
      if (year != null && year.isNotEmpty) 'year': year,
      if (semester != null && semester.isNotEmpty) 'semester': semester,
    };
    // Ensure required parameters are present if needed by the backend
    if (queryParams.isEmpty) {
        // Or handle based on backend requirements - maybe fetch all?
        print("Warning: Fetching student lectures with no filters.");
        // throw ApiException("Required filters (e.g., year, semester) missing for student lectures.");
    }

    final uri = Uri.parse('$_baseUrl/lectures/student').replace(queryParameters: queryParams);
    print("API Request: GET $uri"); // Log request
    try {
      final response = await http.get(
        uri,
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
    final requestBody = jsonEncode(lecture.toApiJson());
    print("API Request: POST $uri with body: $requestBody"); // Log request
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(), // Includes Content-Type and Auth
        body: requestBody,
      );
      // Expecting the created lecture object back from the API
      final Map<String, dynamic> data = _handleResponse(response);
      return Lecture.fromApiJson(data);
    } catch (e) {
        print("Error in createLecture: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to create lecture: ${e.toString()}");
    }
  }

  // --- Attendance API Methods ---

  /// Allows a student to join a lecture.
  Future<AttendanceRecord> joinLecture(String lectureId, String userId) async {
    // Backend might infer userId from Auth token, check API design
    final uri = Uri.parse('$_baseUrl/attendance/join/$lectureId');
    // Body might be optional if backend uses Auth token for userId
    final requestBody = jsonEncode({'userId': userId});
     print("API Request: POST $uri with body: $requestBody"); // Log request
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: requestBody, // Send body if required by backend
      );
      // Expecting the created attendance record back
      final Map<String, dynamic> data = _handleResponse(response);
      return AttendanceRecord.fromApiJson(data);
    } catch (e) {
        print("Error in joinLecture: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to join lecture: ${e.toString()}");
    }
  }

  /// Allows a lecturer to check-in a student using their visit number for a specific lecture.
  Future<AttendanceRecord> checkInStudent(String lectureId, String visitNumber, String lecturerId) async {
    // Backend might infer lecturerId from Auth token, check API design
    final uri = Uri.parse('$_baseUrl/attendance/checkin'); // Endpoint might include lectureId e.g., /attendance/checkin/$lectureId
    final requestBody = jsonEncode({
        'lectureId': lectureId, // May not be needed if in URL
        'visitNumber': visitNumber,
        'lecturerId': lecturerId // May not be needed if using Auth token
      });
    print("API Request: POST $uri with body: $requestBody"); // Log request
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(),
        body: requestBody,
      );
      // Expecting the updated attendance record back
      final Map<String, dynamic> data = _handleResponse(response);
      return AttendanceRecord.fromApiJson(data);
    } catch (e) {
        print("Error in checkInStudent: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to check in student: ${e.toString()}");
    }
  }

  /// Fetches an attendance summary for a student (structure defined by backend).
  Future<Map<String, dynamic>> getStudentAttendanceSummary(String userId) async {
    // Backend might infer userId from Auth token, check API design
    final uri = Uri.parse('$_baseUrl/attendance/student/$userId'); // Or just /attendance/student if using token
    print("API Request: GET $uri"); // Log request
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false),
        );
      // Returns the raw map as the structure might vary
      return _handleResponse(response);
    } catch (e) {
        print("Error in getStudentAttendanceSummary: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch student attendance summary: ${e.toString()}");
    }
  }

  /// Fetches the list of attendees (AttendanceRecord) for a specific lecture.
  Future<List<AttendanceRecord>> getLectureAttendance(String lectureId) async {
    final uri = Uri.parse('$_baseUrl/attendance/lecture/$lectureId');
    print("API Request: GET $uri"); // Log request
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false),
        );
      final List<dynamic> data = _handleResponse(response);
      // Map the JSON list to a list of AttendanceRecord objects
      return data.map((item) => AttendanceRecord.fromApiJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
        print("Error in getLectureAttendance: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to fetch lecture attendance: ${e.toString()}");
    }
  }
}
