
import 'package:checkmate/models/year_of_study.dart';
import 'package:checkmate/services/admin_service.dart';
import 'package:flutter/material.dart';

class ManageYearsScreen extends StatefulWidget {
  const ManageYearsScreen({super.key});

  @override
  State<ManageYearsScreen> createState() => _ManageYearsScreenState();
}

class _ManageYearsScreenState extends State<ManageYearsScreen> {
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
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final years = snapshot.data ?? [];
          return ListView.builder(
            itemCount: years.length,
            itemBuilder: (context, index) {
              final year = years[index];
              return ListTile(
                title: Text(year.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showYearDialog(year: year),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _adminService.deleteYearOfStudy(year.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showYearDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showYearDialog({YearOfStudy? year}) {
    final nameController = TextEditingController(text: year?.name);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(year == null ? 'Add Year' : 'Edit Year'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Year Name'),
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
                  if (year == null) {
                    _adminService.addYearOfStudy(name);
                  } else {
                    _adminService.updateYearOfStudy(year.id, name);
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
