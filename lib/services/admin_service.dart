// lib/services/admin_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

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
