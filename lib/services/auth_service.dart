// lib/services/auth_service.dart
import 'package:checkmate/models/app_user.dart' as app_user;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show ChangeNotifier, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AuthException implements Exception {
  final String message;
  final String? code;
  AuthException(this.message, {this.code});

  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  static const String _port = '5000';
  static String? accessToken;
  final StreamController<app_user.User?> _userController = StreamController.broadcast();
  app_user.User? _currentUser;
  bool _sessionRestored = false;

  app_user.User? get currentUser => _currentUser;
  Stream<app_user.User?> get user => _userController.stream;

  AuthService() {
    _restoreSession();
  }

  String get _baseUrl {
    if (kIsWeb) return 'http://localhost:$_port';
    if (Platform.isAndroid) return 'http://10.0.2.2:$_port';
    return 'http://localhost:$_port';
  }

  Future<File?> get _sessionFile async {
    if (kIsWeb) return null;
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}/checkmate-session.json');
  }

  Future<void> _restoreSession() async {
    try {
      final file = await _sessionFile;
      if (file != null && await file.exists()) {
        final saved = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        accessToken = saved['token'] as String?;
        if (accessToken != null) {
          final response = await http.get(
            Uri.parse('$_baseUrl/api/auth/me'),
            headers: {'Authorization': 'Bearer $accessToken', 'Accept': 'application/json'},
          );
          if (response.statusCode == 200) {
            _setUser(app_user.User.fromApiJson(jsonDecode(response.body) as Map<String, dynamic>));
          } else {
            await logout();
          }
        }
      }
    } catch (_) {
      accessToken = null;
    } finally {
      _sessionRestored = true;
      if (_currentUser == null) _userController.add(null);
    }
  }

  void _setUser(app_user.User user) {
    _currentUser = user;
    _userController.add(user);
    notifyListeners();
  }

  Future<void> _saveSession(String token) async {
    accessToken = token;
    final file = await _sessionFile;
    if (file != null) {
      await file.parent.create(recursive: true);
      await file.writeAsString(jsonEncode({'token': token}), flush: true);
    }
  }

  Future<Map<String, dynamic>> _post(String endpoint, Map<String, dynamic> body) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/api/auth/$endpoint'),
      headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
      body: jsonEncode(body),
    );
    final decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AuthException(decoded['error']?.toString() ?? 'Authentication request failed.');
    }
    return decoded;
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required String phoneNumber,
    String? school,
    String? department,
    String? course,
    String? registrationNumber,
    String? yearOfStudy,
    String? semester,
  }) async {
    final response = await _post('register', {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
      'phoneNumber': phoneNumber.trim(),
      'school': school,
      'department': department,
      'course': course,
      'registrationNumber': registrationNumber,
      'yearOfStudy': yearOfStudy,
      'semester': semester,
    });
    await _saveSession(response['token'] as String);
    _setUser(app_user.User.fromApiJson(response['user'] as Map<String, dynamic>));
  }

  Future<app_user.User?> login(String email, String password) async {
    try {
      final response = await _post('login', {'email': email.trim().toLowerCase(), 'password': password});
      await _saveSession(response['token'] as String);
      final user = app_user.User.fromApiJson(response['user'] as Map<String, dynamic>);
      _setUser(user);
      return user;
    } on AuthException {
      rethrow;
    } catch (_) {
      throw AuthException('Could not connect to the local CheckMate API.');
    }
  }

  Future<void> resendVerificationEmail() async {
    throw AuthException('Email verification is not configured for local development.');
  }

  Future<void> sendPasswordResetEmail(String email) async {
    throw AuthException('Password reset email is not configured for local development.');
  }

  Future<void> logout() async {
    accessToken = null;
    _currentUser = null;
    final file = await _sessionFile;
    if (file != null && await file.exists()) await file.delete();
    if (!_userController.isClosed) _userController.add(null);
    notifyListeners();
  }

  Future<app_user.User?> refreshCurrentUser() async {
    if (accessToken == null) return null;
    final response = await http.get(
      Uri.parse('$_baseUrl/api/auth/me'),
      headers: {'Authorization': 'Bearer $accessToken', 'Accept': 'application/json'},
    );
    if (response.statusCode != 200) {
      await logout();
      return null;
    }
    final user = app_user.User.fromApiJson(jsonDecode(response.body) as Map<String, dynamic>);
    _setUser(user);
    return user;
  }

  @override
  void dispose() {
    _userController.close();
    super.dispose();
  }
}
