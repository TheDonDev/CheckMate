// lib/wrapper.dart
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/screens/lecturer_dashboard.dart';
import 'package:checkmate/screens/student_dashboard.dart';
import 'package:checkmate/screens/welcome_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;

class Wrapper extends StatelessWidget {
  const Wrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return StreamBuilder<app_user.User?>(
      stream: authService.user,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }

        if (snapshot.hasError) {
          print("Error in authentication stream: ${snapshot.error}");
          return const Scaffold(body: Center(child: Padding(padding: EdgeInsets.all(16.0), child: Text('Authentication Error. Please restart the app.', textAlign: TextAlign.center))));
        }

        final appUser = snapshot.data;

        if (appUser != null) {
          // User is logged in
          final fbUser = fb_auth.FirebaseAuth.instance.currentUser;
          if (fbUser != null && !fbUser.emailVerified) {
            print("Warning: User email not verified: ${fbUser.email}");
            // Consider redirecting to an EmailVerificationScreen here
          }

          // Navigate based on role
          switch (appUser.role) {
            case 'lecturer':
              return LecturerDashboard(currentUser: appUser);
            case 'student':
              return StudentDashboard(currentUser: appUser);
            default:
              print("Error: Unknown or missing user role: '${appUser.role}'. Logging out.");
              Future.microtask(() => authService.logout());
              // Fallback to WelcomeScreen if role is invalid after logout attempt
              return const WelcomeScreen();
          }
        } else {
          // User is logged out - Show WelcomeScreen instead of LoginScreen
          return const WelcomeScreen();
        }
      },
    );
  }
}
