
import 'package:checkmate/models/year_of_study.dart';
import 'package:checkmate/services/admin_service.dart';
import 'package:flutter/material.dart';

class ManageYearsOfStudyScreen extends StatefulWidget {
  const ManageYearsOfStudyScreen({super.key});

  @override
  State<ManageYearsOfStudyScreen> createState() => _ManageYearsOfStudyScreenState();
}

class _ManageYearsOfStudyScreenState extends State<ManageYearsOfStudyScreen> {
  final AdminService _adminService = AdminService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Years of Study'),
      ),
      body: StreamBuilder<List<YearOfStudy>>(
        stream: _adminService.getYearsOfStudy(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: \${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final yearsOfStudy = snapshot.data ?? [];
          return ListView.builder(
            itemCount: yearsOfStudy.length,
            itemBuilder: (context, index) {
              final yearOfStudy = yearsOfStudy[index];
              return ListTile(
                title: Text(yearOfStudy.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showYearOfStudyDialog(yearOfStudy: yearOfStudy),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _adminService.deleteYearOfStudy(yearOfStudy.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showYearOfStudyDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showYearOfStudyDialog({YearOfStudy? yearOfStudy}) {
    final nameController = TextEditingController(text: yearOfStudy?.name);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(yearOfStudy == null ? 'Add Year of Study' : 'Edit Year of Study'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Year of Study Name'),
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
                  if (yearOfStudy == null) {
                    _adminService.addYearOfStudy(name);
                  } else {
                    _adminService.updateYearOfStudy(yearOfStudy.id, name);
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
