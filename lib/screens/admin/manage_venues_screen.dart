
import 'package:checkmate/models/venue.dart';
import 'package:checkmate/services/admin_service.dart';
import 'package:flutter/material.dart';

class ManageVenuesScreen extends StatefulWidget {
  const ManageVenuesScreen({super.key});

  @override
  State<ManageVenuesScreen> createState() => _ManageVenuesScreenState();
}

class _ManageVenuesScreenState extends State<ManageVenuesScreen> {
  final AdminService _adminService = AdminService();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manage Venues'),
      ),
      body: StreamBuilder<List<Venue>>(
        stream: _adminService.getVenues(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final venues = snapshot.data ?? [];
          return ListView.builder(
            itemCount: venues.length,
            itemBuilder: (context, index) {
              final venue = venues[index];
              return ListTile(
                title: Text(venue.name),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => _showVenueDialog(venue: venue),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete),
                      onPressed: () => _adminService.deleteVenue(venue.id),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showVenueDialog(),
        child: const Icon(Icons.add),
      ),
    );
  }

  void _showVenueDialog({Venue? venue}) {
    final nameController = TextEditingController(text: venue?.name);
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(venue == null ? 'Add Venue' : 'Edit Venue'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Venue Name'),
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
                  if (venue == null) {
                    _adminService.addVenue(name);
                  } else {
                    _adminService.updateVenue(venue.id, name);
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
