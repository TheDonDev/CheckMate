
import 'package:checkmate/models/department.dart';
import 'package:checkmate/models/school.dart';
import 'package:checkmate/services/admin_service.dart';
import 'package:flutter/material.dart';

class ManageDepartmentsScreen extends StatefulWidget {
  const ManageDepartmentsScreen({super.key});

  @override
  State<ManageDepartmentsScreen> createState() => _ManageDepartmentsScreenState();
}

class _ManageDepartmentsScreenState extends State<ManageDepartmentsScreen> {
  final AdminService _adminService = AdminService();
  String? _selectedSchoolId;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Departments'),
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
          Expanded(
            child: _selectedSchoolId == null
                ? const Center(child: Text('Please select a school to see the departments.'))
                : StreamBuilder<List<Department>>(
                    stream: _adminService.getDepartments(_selectedSchoolId!),
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(child: Text('Error: ${snapshot.error}'));
                      }
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final departments = snapshot.data ?? [];
                      return ListView.builder(
                        itemCount: departments.length,
                        itemBuilder: (context, index) {
                          final department = departments[index];
                          return ListTile(
                            title: Text(department.name),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit),
                                  onPressed: () => _showDepartmentDialog(department: department),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete),
                                  onPressed: () => _adminService.deleteDepartment(department.id),
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
        onPressed: () => _showDepartmentDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showDepartmentDialog({Department? department}) {
    final nameController = TextEditingController(text: department?.name);
    String? dialogSelectedSchoolId = department?.schoolId ?? _selectedSchoolId;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(department == null ? 'Add Department' : 'Edit Department'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              StreamBuilder<List<School>>(
                stream: _adminService.getSchools(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const SizedBox.shrink();
                  final schools = snapshot.data!;
                  return DropdownButtonFormField<String>(
                    value: dialogSelectedSchoolId,
                    hint: const Text('Select a School'),
                    onChanged: (value) {
                      dialogSelectedSchoolId = value;
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
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Department Name'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty && dialogSelectedSchoolId != null) {
                  if (department == null) {
                    _adminService.addDepartment(name, dialogSelectedSchoolId!);
                  } else {
                    _adminService.updateDepartment(department.id, name, dialogSelectedSchoolId!);
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
