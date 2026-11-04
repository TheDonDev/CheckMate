
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/services/auth_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

class LegacyFirebaseAdminService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // --- User Management ---
  Stream<List<app_user.User>> getUsers() {
    return _db.collection('users').snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => app_user.User.fromFirestore(doc)).toList());
  }

  Future<void> updateUserRole(String id, String role) {
    return _db.collection('users').doc(id).update({'role': role});
  }

  Future<void> deleteUser(String id) {
    return _db.collection('users').doc(id).delete();
  }

  // --- School Management ---

  // Get a stream of all schools
  Stream<QuerySnapshot> getSchools() {
    return _db.collection('schools').snapshots();
  }

  // Add a new school
  Future<void> addSchool(String name) {
    return _db.collection('schools').add({'name': name});
  }

  // Update an existing school
  Future<void> updateSchool(String id, String name) {
    return _db.collection('schools').doc(id).update({'name': name});
  }

  // Delete a school
  Future<void> deleteSchool(String id) {
    return _db.collection('schools').doc(id).delete();
  }

  // --- Department Management ---

  // Get a stream of all departments
  Stream<QuerySnapshot> getAllDepartments() {
    return _db.collection('departments').snapshots();
  }

  // Get a stream of departments for a specific school
  Stream<QuerySnapshot> getDepartments(String schoolId) {
    return _db
        .collection('departments')
        .where('schoolId', isEqualTo: schoolId)
        .snapshots();
  }

  // Add a new department
  Future<void> addDepartment(String name, String schoolId) {
    return _db.collection('departments').add({'name': name, 'schoolId': schoolId});
  }

  // Update an existing department
  Future<void> updateDepartment(
      String schoolId, String departmentId, String name) {
    // Correctly reference the document in the top-level 'departments' collection
    return _db.collection('departments').doc(departmentId).update({'name': name});
  }

  // Delete a department
  Future<void> deleteDepartment(String id) {
    return _db.collection('departments').doc(id).delete();
  }

  // --- Course Management ---

  // Get a stream of courses for a specific department
  Stream<QuerySnapshot> getCourses(String departmentId) {
    return _db
        .collection('courses')
        .where('departmentId', isEqualTo: departmentId)
        .snapshots();
  }

  // Add a new course
  Future<void> addCourse(String name, String departmentId) {
    return _db.collection('courses').add({'name': name, 'departmentId': departmentId});
  }

  // Update an existing course
  Future<void> updateCourse(String courseId, String name) {
    // Correctly reference the document in the top-level 'courses' collection
    return _db.collection('courses').doc(courseId).update({'name': name.toUpperCase()});
  }

  // Delete a course
  Future<void> deleteCourse(String id) {
    return _db.collection('courses').doc(id).delete();
  }

  // --- Venue Management ---

  // Get a stream of all venues
  Stream<QuerySnapshot> getVenues() {
    return _db.collection('venues').snapshots();
  }

  // Add a new venue
  Future<void> addVenue(String name) {
    return _db.collection('venues').add({'name': name});
  }

  // Update an existing venue
  Future<void> updateVenue(String id, String name) {
    return _db.collection('venues').doc(id).update({'name': name});
  }

  // Delete a venue
  Future<void> deleteVenue(String id) {
    return _db.collection('venues').doc(id).delete();
  }

  // --- Year of Study Management ---

  // Get a stream of all years of study
  Stream<QuerySnapshot> getYearsOfStudy() {
    return _db.collection('years_of_study').snapshots();
  }

  // Add a new year of study
  Future<void> addYearOfStudy(String name) {
    return _db.collection('years_of_study').add({'name': name});
  }

  // Update an existing year of study
  Future<void> updateYearOfStudy(String id, String name) {
    return _db.collection('years_of_study').doc(id).update({'name': name});
  }

  // Delete a year of study
  Future<void> deleteYearOfStudy(String id) {
    return _db.collection('years_of_study').doc(id).delete();
  }

  // --- Semester Management ---

  // Get a stream of all semesters
  Stream<QuerySnapshot> getSemesters() {
    return _db.collection('semesters').snapshots();
  }

  // Add a new semester
  Future<void> addSemester(String name) {
    return _db.collection('semesters').add({'name': name});
  }

  // Update an existing semester
  Future<void> updateSemester(String id, String name) {
    return _db.collection('semesters').doc(id).update({'name': name});
  }

  // Delete a semester
  Future<void> deleteSemester(String id) {
    return _db.collection('semesters').doc(id).delete();
  }

  // --- Generic Document Name Fetcher ---
  Future<String> getDocumentName(String collection, String? docId) async {
    if (docId == null || docId.isEmpty) {
      return 'N/A';
    }
    try {
      final doc = await _db.collection(collection).doc(docId).get();
      return doc.exists ? (doc.data()?['name'] ?? 'Unknown') : docId;
    } catch (e) {
      return 'Error';
    }
  }
}

class LocalDocumentSnapshot {
  final Map<String, dynamic> _values;
  final String id;

  LocalDocumentSnapshot(Map<String, dynamic> values)
      : _values = values,
        id = values['id']?.toString() ?? '';

  Map<String, dynamic> data() => _values;
  dynamic operator [](String key) => _values[key];
}

class LocalQuerySnapshot {
  final List<LocalDocumentSnapshot> docs;
  LocalQuerySnapshot(List<Map<String, dynamic>> rows)
      : docs = rows.map(LocalDocumentSnapshot.new).toList();
}

class AdminService {
  String get _baseUrl {
    if (kIsWeb) return 'http://localhost:5000';
    if (Platform.isAndroid) return 'http://10.0.2.2:5000';
    return 'http://localhost:5000';
  }

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (AuthService.accessToken != null)
          'Authorization': 'Bearer ${AuthService.accessToken}',
      };

  Future<dynamic> _request(String method, String path, {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$_baseUrl$path');
    final request = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('API request failed (${response.statusCode}): ${response.body}');
    }
    return response.body.isEmpty ? null : jsonDecode(response.body);
  }

  Stream<LocalQuerySnapshot> _watch(String collection, {String? parentKey, String? parentId}) async* {
    while (true) {
      final query = parentId == null ? '' : '?${Uri.encodeQueryComponent(parentKey!)}=${Uri.encodeQueryComponent(parentId)}';
      final rows = await _request('GET', '/api/catalog/$collection$query') as List<dynamic>;
      yield LocalQuerySnapshot(rows.cast<Map<String, dynamic>>());
      await Future<void>.delayed(const Duration(seconds: 15));
    }
  }

  Stream<LocalQuerySnapshot> getUsers() async* {
    while (true) {
      final rows = await _request('GET', '/api/firebase/users') as List<dynamic>;
      yield LocalQuerySnapshot(rows.cast<Map<String, dynamic>>());
      await Future<void>.delayed(const Duration(seconds: 15));
    }
  }

  Future<void> updateUserRole(String id, String role) async => _request('PATCH', '/api/firebase/users/$id/role', body: {'role': role});
  Future<void> deleteUser(String id) async => _request('DELETE', '/api/firebase/users/$id');

  Stream<LocalQuerySnapshot> getSchools() => _watch('schools');
  Future<void> addSchool(String name) async => _request('POST', '/api/catalog/schools', body: {'name': name});
  Future<void> updateSchool(String id, String name) async => _request('PUT', '/api/catalog/schools/$id', body: {'name': name});
  Future<void> deleteSchool(String id) async => _request('DELETE', '/api/catalog/schools/$id');

  Stream<LocalQuerySnapshot> getAllDepartments() => _watch('departments');
  Stream<LocalQuerySnapshot> getDepartments(String schoolId) => _watch('departments', parentKey: 'schoolId', parentId: schoolId);
  Future<void> addDepartment(String name, String schoolId) async => _request('POST', '/api/catalog/departments', body: {'name': name, 'schoolId': schoolId});
  Future<void> updateDepartment(String schoolId, String departmentId, String name) async => _request('PUT', '/api/catalog/departments/$departmentId', body: {'name': name});
  Future<void> deleteDepartment(String id) async => _request('DELETE', '/api/catalog/departments/$id');

  Stream<LocalQuerySnapshot> getCourses(String departmentId) => _watch('courses', parentKey: 'departmentId', parentId: departmentId);
  Future<void> addCourse(String name, String departmentId) async => _request('POST', '/api/catalog/courses', body: {'name': name, 'departmentId': departmentId});
  Future<void> updateCourse(String id, String name) async => _request('PUT', '/api/catalog/courses/$id', body: {'name': name.toUpperCase()});
  Future<void> deleteCourse(String id) async => _request('DELETE', '/api/catalog/courses/$id');

  Stream<LocalQuerySnapshot> getVenues() => _watch('venues');
  Future<void> addVenue(String name) async => _request('POST', '/api/catalog/venues', body: {'name': name});
  Future<void> updateVenue(String id, String name) async => _request('PUT', '/api/catalog/venues/$id', body: {'name': name});
  Future<void> deleteVenue(String id) async => _request('DELETE', '/api/catalog/venues/$id');

  Stream<LocalQuerySnapshot> getYearsOfStudy() => _watch('years_of_study');
  Future<void> addYearOfStudy(String name) async => _request('POST', '/api/catalog/years_of_study', body: {'name': name});
  Future<void> updateYearOfStudy(String id, String name) async => _request('PUT', '/api/catalog/years_of_study/$id', body: {'name': name});
  Future<void> deleteYearOfStudy(String id) async => _request('DELETE', '/api/catalog/years_of_study/$id');

  Stream<LocalQuerySnapshot> getSemesters() => _watch('semesters');
  Future<void> addSemester(String name) async => _request('POST', '/api/catalog/semesters', body: {'name': name});
  Future<void> updateSemester(String id, String name) async => _request('PUT', '/api/catalog/semesters/$id', body: {'name': name});
  Future<void> deleteSemester(String id) async => _request('DELETE', '/api/catalog/semesters/$id');

  Future<String> getDocumentName(String collection, String? docId) async {
    if (docId == null || docId.isEmpty) return 'N/A';
    try {
      final value = await _request('GET', '/api/catalog/$collection/$docId') as Map<String, dynamic>;
      return value['name']?.toString() ?? docId;
    } catch (_) {
      return docId;
    }
  }
}
