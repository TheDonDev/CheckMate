// lib/wrapper.dart
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/screens/admin_dashboard.dart';
import 'package:checkmate/screens/lecturer_dashboard.dart'; // This was missing
import 'package:checkmate/screens/student_dashboard.dart';
import 'package:checkmate/screens/welcome_screen.dart';
// Import the EmailVerificationScreen if you create one
// import 'package:checkmate/screens/verify_email_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class Wrapper extends StatelessWidget {
  const Wrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // Get AuthService instance using Provider
    // listen: false is appropriate here as we only need to call methods,
    // and the StreamBuilder handles reacting to auth state changes.
    final authService = Provider.of<AuthService>(context, listen: false);

    return StreamBuilder<app_user.User?>(
      // Listen to the custom user stream from AuthService
      stream: authService.user,
      builder: (context, snapshot) {
        // --- Handle Connection States ---
        // Show loading indicator while waiting for the initial auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // --- Handle Stream Errors ---
        // Show an error message if the stream itself encounters an issue
        if (snapshot.hasError) {
          print("Error in authentication stream: ${snapshot.error}");
          return const Scaffold(
            body: Center(
              child: Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Authentication Error. Please restart the app.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          );
        }

        // --- Process Authentication Data ---
        final appUser = snapshot.data; // Get the custom app_user.User object

        // --- User is Logged In ---
        if (appUser != null) {
          // --- Navigate Based on User Role ---
          // Use the role from the custom appUser object (fetched from Firestore)
          switch (appUser.role) {
            case 'admin':
              print("Wrapper: Navigating to AdminDashboard for ${appUser.email}");
              return AdminDashboard(currentUser: appUser);
            case 'lecturer':
              print("Wrapper: Navigating to LecturerDashboard for ${appUser.email}");
              return LecturerDashboard(currentUser: appUser);
            case 'student':
              print("Wrapper: Navigating to StudentDashboard for ${appUser.email}");
              return StudentDashboard(currentUser: appUser);
            default:
              // Handle unexpected/missing roles
              print("Error: Unknown or missing user role: '${appUser.role}' for UID ${appUser.id}. Logging out.");
              // Use Future.microtask to schedule logout after the build phase
              Future.microtask(() => authService.logout());
              // Fallback to WelcomeScreen after attempting logout
              return const WelcomeScreen();
          }
        }
        // --- User is Logged Out ---
        else {
          print("Wrapper: No authenticated user found. Navigating to WelcomeScreen.");
          // Show WelcomeScreen (which contains Login/Register options)
          return const WelcomeScreen();
        }
      },
    );
  }
}
