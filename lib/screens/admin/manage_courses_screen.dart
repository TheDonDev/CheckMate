import 'package:flutter/material.dart';
import 'package:checkmate/services/admin_service.dart';
import 'package:flutter/services.dart';

// --- UpperCaseTextFormatter ---
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

class ManageCoursesScreen extends StatefulWidget {
  const ManageCoursesScreen({super.key});

  @override
  _ManageCoursesScreenState createState() => _ManageCoursesScreenState();
}

class _ManageCoursesScreenState extends State<ManageCoursesScreen> {
  final AdminService _adminService = AdminService();
  final TextEditingController _courseNameController = TextEditingController();
  String? _selectedSchoolId;
  String? _selectedDepartmentId;

  void _addCourse() {
    if (_courseNameController.text.isNotEmpty && _selectedDepartmentId != null) {
      _adminService.addCourse(_courseNameController.text.trim().toUpperCase(), _selectedDepartmentId!).then((_) {
        _courseNameController.clear();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Course added successfully')),
        );
      }).catchError((error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add course: $error')),
        );
      });
    }
  }

  void _showEditDialog(LocalDocumentSnapshot document) {
    final TextEditingController editController =
        TextEditingController(text: document['name']);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Course'),
          content: TextField(
            controller: editController,
            decoration: const InputDecoration(labelText: 'Course Name'),
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [UpperCaseTextFormatter()],
          ),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Save'),
              onPressed: () {
                if (editController.text.isNotEmpty) {
                  _adminService
                      .updateCourse(document.id, editController.text.trim().toUpperCase())
                      .then((_) {
                    Navigator.of(context).pop();
                  });
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _confirmDeleteDialog(String id) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: const Text('Are you sure you want to delete this course?'),
          actions: [
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () {
                if (_selectedDepartmentId != null) {
                  _adminService.deleteCourse(id)
                      .then((_) {
                    Navigator.of(context).pop();
                  });
                }
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Courses'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: StreamBuilder<LocalQuerySnapshot>(
              stream: _adminService.getSchools(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const CircularProgressIndicator();
                }
                var schools = snapshot.data!.docs;
                return DropdownButtonFormField<String>(
                  hint: const Text('Select School'),
                  value: _selectedSchoolId,
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedSchoolId = newValue;
                      _selectedDepartmentId = null;
                    });
                  },
                  items: schools.map((school) {
                    return DropdownMenuItem<String>(
                      value: school.id,
                      child: Text(school['name'], overflow: TextOverflow.ellipsis),
                    );
                  }).toList(),
                  isExpanded: true,
                );
              },
            ),
          ),
          if (_selectedSchoolId != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: StreamBuilder<LocalQuerySnapshot>(
                stream: _adminService.getDepartments(_selectedSchoolId!),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const CircularProgressIndicator();
                  }
                  var departments = snapshot.data!.docs;
                  return DropdownButtonFormField<String>(
                    hint: const Text('Select Department'),
                    value: _selectedDepartmentId,
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedDepartmentId = newValue;
                      });
                    },
                    items: departments.map((department) {
                      return DropdownMenuItem<String>(
                        value: department.id,
                        child: Text(department['name'], overflow: TextOverflow.ellipsis),
                      );
                    }).toList(),
                    isExpanded: true,
                  );
                },
              ),
            ),
          if (_selectedDepartmentId != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _courseNameController,
                      decoration: const InputDecoration(
                        labelText: 'Course Name',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [UpperCaseTextFormatter()],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addCourse,
                  ),
                ],
              ),
            ),
          if (_selectedDepartmentId != null)
            Expanded(
              child: StreamBuilder<LocalQuerySnapshot>(
                stream: _adminService.getCourses(_selectedDepartmentId!),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('Something went wrong');
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }

                  return ListView(
                    children: snapshot.data!.docs.map((LocalDocumentSnapshot document) {
                      Map<String, dynamic> data = document.data()! as Map<String, dynamic>;
                      return ListTile(
                        title: Text(data['name']),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.edit),
                              onPressed: () => _showEditDialog(document),
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete),
                              onPressed: () =>
                                  _confirmDeleteDialog(document.id),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}