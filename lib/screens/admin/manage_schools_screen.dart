
import 'package:checkmate/models/school.dart';
import 'package:checkmate/services/admin_service.dart';
import 'package:flutter/material.dart';

class ManageSchoolsScreen extends StatefulWidget {
  const ManageSchoolsScreen({super.key});

  @override
  State<ManageSchoolsScreen> createState() => _ManageSchoolsScreenState();
}

class _ManageSchoolsScreenState extends State<ManageSchoolsScreen> {
  final AdminService _adminService = AdminService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Schools'),
      ),
      body: StreamBuilder<List<School>>(
        stream: _adminService.getSchools(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final schools = snapshot.data ?? [];
          return ListView.builder(
            itemCount: schools.length,
            itemBuilder: (context, index) {
              final school = schools[index];
              return ListTile(
                title: Text(school.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showSchoolDialog(school: school),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _adminService.deleteSchool(school.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showSchoolDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showSchoolDialog({School? school}) {
    final nameController = TextEditingController(text: school?.name);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(school == null ? 'Add School' : 'Edit School'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'School Name'),
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
                  if (school == null) {
                    _adminService.addSchool(name);
                  } else {
                    _adminService.updateSchool(school.id, name);
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
