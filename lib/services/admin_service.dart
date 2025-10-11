
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminService {
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
