
import 'package:checkmate/models/course.dart';
import 'package:checkmate/models/department.dart';
import 'package:checkmate/models/school.dart';
import 'package:checkmate/services/admin_service.dart';
import 'package:flutter/material.dart';

class ManageCoursesScreen extends StatefulWidget {
  const ManageCoursesScreen({super.key});

  @override
  State<ManageCoursesScreen> createState() => _ManageCoursesScreenState();
}

class _ManageCoursesScreenState extends State<ManageCoursesScreen> {
  final AdminService _adminService = AdminService();
  String? _selectedSchoolId;
  String? _selectedDepartmentId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Courses'),
      ),
      body: Column(
        children: [
          StreamBuilder<List<School>>(
            stream: _adminService.getSchools(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const CircularProgressIndicator();
              final schools = snapshot.data!;
              return DropdownButtonFormField<String>(
                value: _selectedSchoolId,
                hint: const Text('Select a School'),
                onChanged: (value) {
                  setState(() {
                    _selectedSchoolId = value;
                    _selectedDepartmentId = null;
                  });
                },
                items: schools.map((school) {
                  return DropdownMenuItem<String>(
                    value: school.id,
                    child: Text(school.name),
                  );
                }).toList(),
              );
            },
          ),
          if (_selectedSchoolId != null)
            StreamBuilder<List<Department>>(
              stream: _adminService.getDepartments(_selectedSchoolId!),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const CircularProgressIndicator();
                final departments = snapshot.data!;
                return DropdownButtonFormField<String>(
                  value: _selectedDepartmentId,
                  hint: const Text('Select a Department'),
                  onChanged: (value) {
                    setState(() {
                      _selectedDepartmentId = value;
                    });
                  },
                  items: departments.map((department) {
                    return DropdownMenuItem<String>(
                      value: department.id,
                      child: Text(department.name),
                    );
                  }).toList(),
                );
              },
            ),
          Expanded(
            child: _selectedDepartmentId == null
                ? const Center(child: Text('Please select a school and department.'))
                : StreamBuilder<List<Course>>(
                    stream: _adminService.getCourses(_selectedDepartmentId!),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final courses = snapshot.data ?? [];
                      return ListView.builder(
                        itemCount: courses.length,
                        itemBuilder: (context, index) {
                          final course = courses[index];
                          return ListTile(
                            title: Text(course.name),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showCourseDialog(course: course),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _adminService.deleteCourse(course.id),
                                ),
                              ],
                            ),
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showCourseDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showCourseDialog({Course? course}) {
    final nameController = TextEditingController(text: course?.name);
    String? dialogSelectedDepartmentId = course?.departmentId ?? _selectedDepartmentId;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(course == null ? 'Add Course' : 'Edit Course'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // This would need to be a more complex stateful dialog to handle school/department selection
              // For simplicity, we assume a department is selected if we are adding a new course.
              if (dialogSelectedDepartmentId != null)
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Course Name'),
                )
              else
                const Text('Please select a department first.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            if (dialogSelectedDepartmentId != null)
              TextButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isNotEmpty) {
                    if (course == null) {
                      _adminService.addCourse(name, dialogSelectedDepartmentId!);
                    } else {
                      _adminService.updateCourse(course.id, name, dialogSelectedDepartmentId!);
                    }
                    Navigator.pop(context);
                  }
                },
                child: const Text('Save'),
              ),
          ],
        );
      },
    );
  }
}
