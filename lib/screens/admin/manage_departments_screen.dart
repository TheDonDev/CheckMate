import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

class ManageDepartmentsScreen extends StatefulWidget {
  const ManageDepartmentsScreen({super.key});

  @override
  _ManageDepartmentsScreenState createState() => _ManageDepartmentsScreenState();
}

class _ManageDepartmentsScreenState extends State<ManageDepartmentsScreen> {
  final AdminService _adminService = AdminService();
  final TextEditingController _departmentNameController = TextEditingController();
  String? _selectedSchoolId;

  void _addDepartment() {
    if (_departmentNameController.text.isNotEmpty && _selectedSchoolId != null) {
      _adminService.addDepartment(_departmentNameController.text.toUpperCase(), _selectedSchoolId!).then((_) {
        _departmentNameController.clear();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Department added successfully')),
        );
      }).catchError((error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add department: $error')),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Departments'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: StreamBuilder<QuerySnapshot>(
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
                    });
                  },
                  items: schools.map((school) {
                    return DropdownMenuItem<String>(
                      value: school.id,
                      child: Text(school['name']),
                    );
                  }).toList(),
                );
              },
            ),
          ),
          if (_selectedSchoolId != null)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _departmentNameController,
                      decoration: const InputDecoration(
                        labelText: 'Department Name',
                      ),
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [UpperCaseTextFormatter()],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _addDepartment,
                  ),
                ],
              ),
            ),
          if (_selectedSchoolId != null)
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: _adminService.getDepartments(_selectedSchoolId!),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return const Text('Something went wrong');
                  }

                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }

                  return ListView(
                    children: snapshot.data!.docs.map((DocumentSnapshot document) {
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
                              onPressed: () => _confirmDeleteDialog(document.id),
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

  Future<void> _confirmDeleteDialog(String departmentId) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false, // user must tap button!
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Confirm Delete'),
          content: const SingleChildScrollView(
            child: ListBody(
              children: <Widget>[
                Text('Are you sure you want to delete this department?'),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            TextButton(
              child: const Text('Delete'),
              onPressed: () {
                _deleteDepartment(departmentId);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showEditDialog(DocumentSnapshot document) {
    final TextEditingController editController =
        TextEditingController(text: document['name']);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Department'),
          content: TextField(
            controller: editController,
            decoration: const InputDecoration(labelText: 'Department Name'),
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
                  _updateDepartment(document.id, editController.text.toUpperCase());
                  Navigator.of(context).pop();
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _updateDepartment(String departmentId, String departmentName) {
    if (_selectedSchoolId != null) {
      _adminService.updateDepartment(
          _selectedSchoolId!, departmentId, departmentName);
    }
  }

  void _deleteDepartment(String departmentId) {
    _adminService.deleteDepartment(departmentId);
  }
}