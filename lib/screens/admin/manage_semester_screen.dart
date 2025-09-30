
import 'package:checkmate/models/semester.dart';
import 'package:checkmate/services/admin_service.dart';
import 'package:flutter/material.dart';

class ManageSemestersScreen extends StatefulWidget {
  const ManageSemestersScreen({super.key});

  @override
  State<ManageSemestersScreen> createState() => _ManageSemestersScreenState();
}

class _ManageSemestersScreenState extends State<ManageSemestersScreen> {
  final AdminService _adminService = AdminService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Semesters'),
      ),
      body: StreamBuilder<List<Semester>>(
        stream: _adminService.getSemesters(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: \${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final semesters = snapshot.data ?? [];
          return ListView.builder(
            itemCount: semesters.length,
            itemBuilder: (context, index) {
              final semester = semesters[index];
              return ListTile(
                title: Text(semester.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showSemesterDialog(semester: semester),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _adminService.deleteSemester(semester.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSemesterDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showSemesterDialog({Semester? semester}) {
    final nameController = TextEditingController(text: semester?.name);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(semester == null ? 'Add Semester' : 'Edit Semester'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Semester Name'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  if (semester == null) {
                    _adminService.addSemester(name);
                  } else {
                    _adminService.updateSemester(semester.id, name);
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
