
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/models/course.dart';
import 'package:checkmate/models/department.dart';
import 'package:checkmate/models/school.dart';
import 'package:checkmate/models/semester.dart';
import 'package:checkmate/models/venue.dart';
import 'package:checkmate/models/year_of_study.dart';
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
  Stream<List<School>> getSchools() {
    return _db.collection('schools').snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => School.fromFirestore(doc)).toList());
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
  Stream<List<Department>> getAllDepartments() {
    return _db.collection('departments').snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => Department.fromFirestore(doc)).toList());
  }

  // Get a stream of departments for a specific school
  Stream<List<Department>> getDepartments(String schoolId) {
    return _db
        .collection('departments')
        .where('schoolId', isEqualTo: schoolId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Department.fromFirestore(doc)).toList());
  }

  // Add a new department
  Future<void> addDepartment(String name, String schoolId) {
    return _db.collection('departments').add({'name': name, 'schoolId': schoolId});
  }

  // Update an existing department
  Future<void> updateDepartment(String id, String name, String schoolId) {
    return _db.collection('departments').doc(id).update({'name': name, 'schoolId': schoolId});
  }

  // Delete a department
  Future<void> deleteDepartment(String id) {
    return _db.collection('departments').doc(id).delete();
  }

  // --- Course Management ---

  // Get a stream of courses for a specific department
  Stream<List<Course>> getCourses(String departmentId) {
    return _db
        .collection('courses')
        .where('departmentId', isEqualTo: departmentId)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => Course.fromFirestore(doc)).toList());
  }

  // Add a new course
  Future<void> addCourse(String name, String departmentId) {
    return _db.collection('courses').add({'name': name, 'departmentId': departmentId});
  }

  // Update an existing course
  Future<void> updateCourse(String id, String name, String departmentId) {
    return _db.collection('courses').doc(id).update({'name': name, 'departmentId': departmentId});
  }

  // Delete a course
  Future<void> deleteCourse(String id) {
    return _db.collection('courses').doc(id).delete();
  }

  // --- Venue Management ---

  // Get a stream of all venues
  Stream<List<Venue>> getVenues() {
    return _db.collection('venues').snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => Venue.fromFirestore(doc)).toList());
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
  Stream<List<YearOfStudy>> getYearsOfStudy() {
    return _db.collection('yearsOfStudy').snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => YearOfStudy.fromFirestore(doc)).toList());
  }

  // Add a new year of study
  Future<void> addYearOfStudy(String name) {
    return _db.collection('yearsOfStudy').add({'name': name});
  }

  // Update an existing year of study
  Future<void> updateYearOfStudy(String id, String name) {
    return _db.collection('yearsOfStudy').doc(id).update({'name': name});
  }

  // Delete a year of study
  Future<void> deleteYearOfStudy(String id) {
    return _db.collection('yearsOfStudy').doc(id).delete();
  }

  // --- Semester Management ---

  // Get a stream of all semesters
  Stream<List<Semester>> getSemesters() {
    return _db.collection('semesters').snapshots().map((snapshot) =>
        snapshot.docs.map((doc) => Semester.fromFirestore(doc)).toList());
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
}
