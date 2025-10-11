
// lib/screens/admin_dashboard.dart
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/screens/admin/manage_courses_screen.dart';
import 'package:checkmate/screens/admin/manage_departments_screen.dart';
import 'package:checkmate/screens/admin/manage_schools_screen.dart';
import 'package:checkmate/screens/admin/manage_semesters_screen.dart';
import 'package:checkmate/screens/admin/manage_users_screen.dart';
import 'package:checkmate/screens/admin/manage_venues_screen.dart';
import 'package:checkmate/screens/admin/manage_years_screen.dart';
import 'package:checkmate/screens/login_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AdminDashboard extends StatelessWidget {
  final app_user.User currentUser;

  const AdminDashboard({super.key, required this.currentUser});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin Dashboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await authService.logout();
              Navigator.pushAndRemoveUntil(
                context,
                MaterialPageRoute(builder: (context) => const LoginScreen()),
                (route) => false,
              );
            },
          ),
        ],
      ),
      body: GridView.count(
        crossAxisCount: 2,
        padding: const EdgeInsets.all(16.0),
        children: <Widget>[
          _buildDashboardCard(context, 'Manage Schools', Icons.school, () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageSchoolsScreen()));
          }),
          _buildDashboardCard(context, 'Manage Departments', Icons.business, () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageDepartmentsScreen()));
          }),
          _buildDashboardCard(context, 'Manage Courses', Icons.book, () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageCoursesScreen()));
          }),
          _buildDashboardCard(context, 'Manage Venues', Icons.place, () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageVenuesScreen()));
          }),
          _buildDashboardCard(context, 'Manage Users', Icons.people, () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageUsersScreen()));
          }),
          _buildDashboardCard(context, 'Manage Years of Study', Icons.calendar_today, () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageYearsScreen()));
          }),
          _buildDashboardCard(context, 'Manage Semesters', Icons.calendar_view_day, () {
            Navigator.push(context, MaterialPageRoute(builder: (context) => const ManageSemestersScreen()));
          }),
        ],
      ),
    );
  }

  Widget _buildDashboardCard(BuildContext context, String title, IconData icon, VoidCallback onTap) {
    return Card(
      margin: const EdgeInsets.all(8.0),
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 40.0, color: Theme.of(context).primaryColor),
            const SizedBox(height: 10.0),
            Text(title, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
