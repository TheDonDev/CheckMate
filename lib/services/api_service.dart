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
  // TODO: Replace with your actual IP/domain and port if not using localhost/emulator defaults
  static const String _localIp = '192.168.50.156'; // <-- Replace with your machine's local IP if testing on physical device AND backend is on same network
  static const String _androidEmulatorIp = '10.0.2.2'; // Standard for Android Emulator accessing host's localhost
  static const String _port = '5000'; // Your backend port (e.g., Node.js)
  // TODO: Replace with your deployed Firebase Functions URL if applicable
  // static const String _firebaseFunctionsUrl = 'https://your-region-your-project-id.cloudfunctions.net/api'; // Example

  // Select the base URL based on the platform and environment
  late final String _baseUrl;

  ApiService() {
    // --- CHOOSE YOUR BACKEND TYPE ---
    // Set to true if using Firebase Functions backend, false for local Node.js/other
    const bool useFirebaseFunctions = false;
    // --------------------------------

    // --- CHOOSE YOUR BACKEND API PATH ---
    // Adjust if your Node.js routes are not under '/api/firebase'
    const String localApiPath = '/api/firebase';
    // Adjust if your Firebase Functions entry point is different
    const String functionsApiPath = '/api'; // Often just '/api' if using Express within functions
    // ------------------------------------

    if (useFirebaseFunctions) {
      // TODO: Uncomment and set your Firebase Functions URL if using them
      // _baseUrl = _firebaseFunctionsUrl + functionsApiPath;
      // Placeholder if not set:
      _baseUrl = 'https://us-central1-checkmate-app-8489a.cloudfunctions.net/api' + functionsApiPath; // Example
      if (kDebugMode) print("ApiService using Firebase Functions URL: $_baseUrl");
    } else {
      // Determine URL for local/self-hosted backend
      if (kIsWeb) {
        // For web testing, assuming backend runs on localhost
        _baseUrl = 'http://localhost:$_port$localApiPath';
      } else {
        // Use dart:io Platform check only on non-web platforms
        try {
          if (Platform.isAndroid) {
            // Use 10.0.2.2 for Android Emulator to reach host's localhost
            _baseUrl = 'http://$_androidEmulatorIp:$_port$localApiPath';
          } else if (Platform.isIOS) {
            // Use localhost for iOS Simulator if backend is on the same Mac
            // Use _localIp if backend is on a different machine on the network
            _baseUrl = 'http://localhost:$_port$localApiPath'; // Or use _localIp
          } else {
            // Default for other desktop platforms (Linux, Windows, macOS)
            // Assumes backend is accessible via the local IP or localhost
            _baseUrl = 'http://localhost:$_port$localApiPath'; // Or use _localIp
          }
        } catch (e) {
          // Fallback if Platform check fails unexpectedly (e.g., unsupported platform)
          if (kDebugMode) print("Platform check failed, defaulting to localhost: $e");
          _baseUrl = 'http://localhost:$_port$localApiPath'; // Fallback to localhost
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
        final idToken = await user.getIdToken(false); // false = don't force refresh unless expired
        if (idToken != null) {
          headers['Authorization'] = 'Bearer $idToken'; // Standard Bearer token format
           if (kDebugMode) print("Auth Token included in headers."); // Debug log
        } else {
           if (kDebugMode) print("Warning: Could not get ID token for authenticated user.");
           // Depending on API requirements, might need to throw here
           throw ApiException("Authentication token unavailable.", statusCode: 401);
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
       throw ApiException("User not authenticated. Please log in.", statusCode: 401);
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
          return null; // Indicate success with no body
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
      // Use _handleResponse which throws on error or returns decoded JSON
      final List<dynamic> data = _handleResponse(response);
      // Map the JSON list to a list of Lecture objects
      // Ensure Lecture.fromApiJson exists and handles the structure returned by your API
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

    // --- *** CORRECTED QUERY PARAMETER KEYS *** ---
    final queryParams = <String, String>{
      // Use field names EXACTLY as expected by the backend req.query
      if (school != null && school.isNotEmpty) 'school': school,
      if (department != null && department.isNotEmpty) 'department': department,
      if (course != null && course.isNotEmpty) 'course': course,
      if (year != null && year.isNotEmpty) 'year': year, // Changed from 'yearOfStudy'
      if (semester != null && semester.isNotEmpty) 'semester': semester, // Correct key
    };
    // --- *** END CORRECTION *** ---

    // Validate required filters (Year and Semester are crucial for student view)
    // Also include school/dept/course as backend validation requires them now
    if (school == null || school.isEmpty ||
        department == null || department.isEmpty ||
        course == null || course.isEmpty ||
        year == null || year.isEmpty ||
        semester == null || semester.isEmpty) {
        if (kDebugMode) print("API Error: All filter parameters (school, dept, course, year, semester) are required for student lectures.");
        // Throw an exception to be caught by the UI
        throw ApiException("All filters (School, Department, Course, Year, Semester) must be selected to find lectures.");
    }

    // Endpoint assumes backend route is /lectures/student with query params
    final uri = Uri.parse('$_baseUrl/lectures/student').replace(queryParameters: queryParams);
    if (kDebugMode) print("API Request: GET $uri"); // Log the exact URL being requested
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false), // Auth likely needed
      );
      // Use _handleResponse which throws on error or returns decoded JSON
      final List<dynamic> data = _handleResponse(response);
      // Ensure Lecture.fromApiJson exists and handles the structure returned by your API
      return data.map((item) => Lecture.fromApiJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
        if (kDebugMode) print("Error in getStudentLectures: $e");
        if (e is ApiException) rethrow; // Rethrow specific API exceptions
        throw ApiException("Failed to fetch student lectures: ${e.toString()}"); // Wrap other errors
    }
  }

  /// Creates a new lecture via the backend API.
  Future<Lecture> createLecture(Lecture lecture) async {
    // Endpoint assumes backend route is POST /lectures
    final uri = Uri.parse('$_baseUrl/lectures');
    // Use the lecture model's toApiJson method for the request body
    // Ensure lecture.toApiJson() exists and formats data correctly (esp. DateTime)
    final requestBody = jsonEncode(lecture.toApiJson());
    if (kDebugMode) print("API Request: POST $uri with body: $requestBody");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(), // Auth needed, Content-Type included
        body: requestBody,
      );
      // Use _handleResponse which throws on error or returns decoded JSON
      final Map<String, dynamic> data = _handleResponse(response);
      // Expect the created lecture object back from the API
      // Ensure Lecture.fromApiJson exists and handles the structure returned by your API
      return Lecture.fromApiJson(data);
    } catch (e) {
        if (kDebugMode) print("Error in createLecture: $e");
        if (e is ApiException) rethrow; // Rethrow specific API exceptions
        throw ApiException("Failed to create lecture: ${e.toString()}"); // Wrap other errors
    }
  }

  // --- ADDED: Update Lecture Method ---
  /// Updates an existing lecture via the backend API.
  /// Requires authentication, backend must verify ownership or admin role.
  Future<Lecture> updateLecture(String lectureId, Map<String, dynamic> lectureData) async {
    // Endpoint assumes backend route is PUT or PATCH /lectures/{lectureId}
    final uri = Uri.parse('$_baseUrl/lectures/$lectureId');
    final requestBody = jsonEncode(lectureData);
    if (kDebugMode) print("API Request: PUT $uri with body: $requestBody"); // Assuming PUT, change if PATCH
    try {
      final response = await http.put( // Use http.patch if your backend uses PATCH
        uri,
        headers: await _getHeaders(), // Auth needed, Content-Type included
        body: requestBody,
      );
      // Use _handleResponse which throws on error or returns decoded JSON
      final Map<String, dynamic> data = _handleResponse(response);
      // Expect the updated lecture object back from the API
      return Lecture.fromApiJson(data);
    } catch (e) {
        if (kDebugMode) print("Error in updateLecture: $e");
        // Provide more specific feedback based on potential API error messages
        if (e is ApiException) {
            if (e.statusCode == 403) { // Forbidden
                throw ApiException('Unauthorized: You do not have permission to update this lecture.', statusCode: e.statusCode);
            } else if (e.statusCode == 404) { // Not Found
                throw ApiException('Update failed: Lecture not found.', statusCode: e.statusCode);
            } else if (e.statusCode == 400) { // Bad Request
                throw ApiException('Update failed: Invalid data provided. ${e.message}', statusCode: e.statusCode);
            }
            rethrow; // Rethrow other specific API exceptions
        }
        // Wrap generic errors
        throw ApiException("Failed to update lecture: ${e.toString()}");
    }
  }
  // --- END Update Lecture Method ---


  // --- Attendance API Methods ---

  /// Allows a student to join a lecture (MANUAL JOIN BUTTON).
  /// Backend uses the auth token to get studentId and profile details.
  /// Backend MUST ensure isCheckedIn is set to false or remains unchanged.
  Future<AttendanceRecord> joinLecture(String lectureId) async {
    // Endpoint assumes backend route is POST /attendance/join/{lectureId}
    final uri = Uri.parse('$_baseUrl/attendance/join/$lectureId');
    if (kDebugMode) print("API Request (Student Join): POST $uri");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(includeContentType: false), // Auth needed (student)
      );
      final Map<String, dynamic> data = _handleResponse(response);
      return AttendanceRecord.fromApiJson(data);
    } catch (e) {
        if (kDebugMode) print("Error in joinLecture: $e");
        if (e is ApiException) rethrow;
        throw ApiException("Failed to join lecture: ${e.toString()}");
    }
  }

  // --- NEW METHOD for Student Check-in via Lecture QR ---
  /// Allows a student to check-in by scanning the LECTURER's QR code.
  /// Backend MUST verify the student has already joined (isCheckedIn == false).
  Future<AttendanceRecord> checkInViaLectureQr(String lectureId) async {
    // Endpoint assumes backend route is POST /attendance/checkin/student/{lectureId}
    final uri = Uri.parse('$_baseUrl/attendance/checkin/student/$lectureId'); // Adjust if your backend route differs
    if (kDebugMode) print("API Request (Student Check-In via QR): POST $uri");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(includeContentType: false), // Auth needed (student)
      );
      final Map<String, dynamic> data = _handleResponse(response);
      return AttendanceRecord.fromApiJson(data);
    } catch (e) {
        if (kDebugMode) print("Error in checkInViaLectureQr: $e");
        // Provide more specific feedback based on potential API error messages
        if (e is ApiException) {
            if (e.statusCode == 404 || e.statusCode == 400) { // Example: Not Found or Bad Request if not joined
                throw ApiException('Check-in failed: You must join the lecture first.', statusCode: e.statusCode);
            } else if (e.statusCode == 409) { // Example: Conflict if already checked in
                 throw ApiException('Check-in failed: You are already checked in.', statusCode: e.statusCode);
            }
            rethrow; // Rethrow other API exceptions
        }
        throw ApiException("Failed to check-in via QR: ${e.toString()}");
    }
  }
  // --- END NEW METHOD ---

  /// Allows a lecturer to check in a student using their registration number.
  /// Assumes backend handles lookup and record creation/update.
  Future<AttendanceRecord> checkInStudent(String lectureId, String registrationNumber) async {
    // Endpoint assumes backend route is POST /attendance/checkin (or similar)
    // NO CHANGES NEEDED HERE - This is for LECTURER actions
    final uri = Uri.parse('$_baseUrl/attendance/checkin'); // Adjust if needed
    final requestBody = jsonEncode({
        'lectureId': lectureId,
        'registrationNumber': registrationNumber,
      });
    if (kDebugMode) print("API Request (Lecturer Check-In): POST $uri with body: $requestBody");
    try {
      final response = await http.post(
        uri,
        headers: await _getHeaders(), // Auth needed (lecturer must be logged in), Content-Type included
        body: requestBody,
      );
      // Use _handleResponse which throws on error or returns decoded JSON
      final Map<String, dynamic> data = _handleResponse(response);
      // Expect the updated attendance record back
      // Ensure AttendanceRecord.fromApiJson exists and handles the structure
      return AttendanceRecord.fromApiJson(data);
    } catch (e) {
        if (kDebugMode) print("Error in checkInStudent: $e");
        // Provide more specific feedback based on potential API error messages
        if (e is ApiException) {
            if (e.statusCode == 404) { // Example: If backend returns 404 for student/lecture not found or not joined
                throw ApiException('Check-in failed: Student ($registrationNumber) or Lecture not found, or student has not joined.', statusCode: e.statusCode);
            } else if (e.statusCode == 409) { // Example: If backend returns 409 for already checked in
                 throw ApiException('Check-in failed: Student $registrationNumber is already checked in.', statusCode: e.statusCode);
            } else if (e.statusCode == 400) { // Example: Bad request (e.g., invalid reg number format)
                 throw ApiException('Check-in failed: Invalid request data. ${e.message}', statusCode: e.statusCode);
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
    final uri = Uri.parse('$_baseUrl/attendance/lecture/$lectureId'); // Adjust if needed
    if (kDebugMode) print("API Request: GET $uri");
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false), // Auth likely needed
        );
      // Use _handleResponse which throws on error or returns decoded JSON
      final List<dynamic> data = _handleResponse(response);
      // Map JSON list to AttendanceRecord list
      // Ensure AttendanceRecord.fromApiJson exists and handles the structure
      return data.map((item) => AttendanceRecord.fromApiJson(item as Map<String, dynamic>)).toList();
    } catch (e) {
        if (kDebugMode) print("Error in getLectureAttendance: $e");
        if (e is ApiException) rethrow; // Rethrow specific API exceptions
        throw ApiException("Failed to fetch lecture attendance: ${e.toString()}"); // Wrap other errors
    }
  }

  // --- Student Attendance Summary ---
  /// Fetches the student's attendance summary (records, percentage, counts).
  /// *** MODIFIED: Accepts optional year and semester for filtering. ***
  /// Backend calculates percentage based on relevant lectures for the student,
  /// filtered by year/semester if provided.
  Future<Map<String, dynamic>> getStudentAttendanceSummary(
    String userId, {
    String? year, // Optional year filter
    String? semester, // Optional semester filter
  }) async {
    // Endpoint assumes backend route is GET /attendance/student/{userId}
    // Add year and semester as query parameters if they are provided
    final queryParams = <String, String>{};
    if (year != null && year.isNotEmpty) {
      queryParams['year'] = year;
    }
    if (semester != null && semester.isNotEmpty) {
      queryParams['semester'] = semester;
    }

    final uri = Uri.parse('$_baseUrl/attendance/student/$userId').replace(
      queryParameters: queryParams.isNotEmpty ? queryParams : null, // Add query params only if they exist
    );

    if (kDebugMode) print("API Request: GET $uri"); // Log the full URI with query params
    try {
      final response = await http.get(
        uri,
        headers: await _getHeaders(includeContentType: false), // Auth needed
        );
      // Use _handleResponse which throws on error or returns decoded JSON
      final Map<String, dynamic> data = _handleResponse(response);

      // --- Data Sanitization & Parsing ---
      // Parse the nested attendance records list safely
      List<AttendanceRecord> records = [];
      if (data['attendanceRecords'] is List) {
         try {
           records = (data['attendanceRecords'] as List)
              .map((item) => AttendanceRecord.fromApiJson(item as Map<String, dynamic>))
              .toList();
         } catch (parseError) {
            if (kDebugMode) print("Error parsing attendanceRecords list: $parseError");
            // Keep records as empty list if parsing fails
         }
      }

      // Ensure other fields exist and have correct types, provide defaults
      final String percentage = data['percentage']?.toString() ?? '0.00';
      final int totalLectures = data['totalLectures'] is int ? data['totalLectures'] : (int.tryParse(data['totalLectures']?.toString() ?? '0') ?? 0);
      final int attendedLectures = data['attendedLectures'] is int ? data['attendedLectures'] : (int.tryParse(data['attendedLectures']?.toString() ?? '0') ?? 0);
      // --- End Data Sanitization ---

      // Return a map with guaranteed structure and types
      return {
        'attendanceRecords': records,
        'percentage': percentage,
        'totalLectures': totalLectures,
        'attendedLectures': attendedLectures,
      };
    } catch (e) {
        if (kDebugMode) print("Error in getStudentAttendanceSummary: $e");
        if (e is ApiException) rethrow; // Rethrow specific API exceptions
        throw ApiException("Failed to fetch student attendance summary: ${e.toString()}"); // Wrap other errors
    }
  }

} // End of ApiService class
