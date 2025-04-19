// lib/services/auth_service.dart
import 'package:checkmate/models/app_user.dart' as app_user; // Use prefix for clarity
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth; // Use prefix for clarity
import 'package:flutter/foundation.dart'; // Import ChangeNotifier

// Custom Exception for Auth errors
class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  final fb_auth.FirebaseAuth _firebaseAuth = fb_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  app_user.User? _currentUser; // Cache the current user model
  app_user.User? get currentUser => _currentUser;

  // Convert Firebase User to custom User model, fetching data from Firestore
  Future<app_user.User?> _userFromFirebaseUser(fb_auth.User? firebaseUser) async {
    if (firebaseUser == null) {
      if (_currentUser != null) { // Only notify if state changes
        _currentUser = null; // Clear cache on null user
        notifyListeners(); // Notify listeners about the change
      }
      return null;
    }
    try {
      // Fetch the user document from Firestore using the UID
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(firebaseUser.uid).get();

      if (userDoc.exists) {
        // Create our custom User object from the Firestore data
        final user = app_user.User.fromFirestore(userDoc);

        // Update cache and notify listeners only if the user data has changed
        // This prevents unnecessary rebuilds if the data is the same
        if (_currentUser != user) {
           _currentUser = user; // Update cache
           notifyListeners(); // Notify listeners about the change
        }
        return user;
      } else {
        // This indicates an inconsistency: Auth user exists, but Firestore data is missing.
        print("Warning: User document not found in Firestore for UID: ${firebaseUser.uid}. Logging out.");
        // Force logout to prevent inconsistent state
        await _firebaseAuth.signOut(); // Sign out from Firebase Auth
        // No need to manually clear _currentUser here, the authStateChanges stream will handle it.
        return null; // Return null as the user data is incomplete
      }
    } catch (e) {
      print("Error fetching user data from Firestore for UID ${firebaseUser.uid}: $e");
      // Clear cache on error and notify listeners if state changes
      if (_currentUser != null) {
         _currentUser = null;
         notifyListeners();
      }
      // Depending on the error, you might want to rethrow or handle differently
      return null;
    }
  }

  // Stream of custom User objects reflecting authentication state
  Stream<app_user.User?> get user {
    return _firebaseAuth.authStateChanges().asyncMap((fbUser) async {
      // When Firebase auth state changes, fetch/update our custom user data.
      // This automatically updates the cache and notifies listeners via _userFromFirebaseUser.
      final appUser = await _userFromFirebaseUser(fbUser);
      return appUser;
    });
  }

  // --- Updated Sign Up Method with All Fields ---
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required String phoneNumber, // Added (required)
    required String? school,
    required String? department,
    required String? course,
    required String? registrationNumber, // Optional based on role
    required String? yearOfStudy,        // Added (optional based on role)
    required String? semester,           // Added (optional based on role)
  }) async {
    // Basic validation (UI should handle most, but good to have a safety net)
    if (name.isEmpty || email.isEmpty || password.isEmpty || phoneNumber.isEmpty || school == null || department == null || course == null) {
       throw AuthException('Please fill in all required fields.');
    }

    try {
      // 1. Create user with Firebase Authentication
      fb_auth.UserCredential userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password, // Password strength validation should be in UI
      );
      fb_auth.User? firebaseUser = userCredential.user;

      if (firebaseUser != null) {
        // 2. Send verification email
        // Check if already verified (unlikely on create, but good practice)
        if (!firebaseUser.emailVerified) {
           await firebaseUser.sendEmailVerification();
           print("Verification email sent to ${email.trim()}");
        }

        // 3. Determine role based on email domain
        final bool isStudent = email.trim().toLowerCase().endsWith('@student.au.ac.ke');
        final String role = isStudent ? 'student' : 'lecturer';

        // 4. Student-specific validation (ensure required fields are present if role is student)
        if (isStudent && (registrationNumber == null || registrationNumber.trim().isEmpty || yearOfStudy == null || semester == null)) {
            // This is a safeguard; primary validation is in the UI form
            throw AuthException('Student registration requires Registration Number, Year of Study, and Semester.');
        }

        // 5. Prepare user data for Firestore
        Map<String, dynamic> userData = {
          'uid': firebaseUser.uid, // Store UID explicitly for easier querying if needed
          'name': name.trim(),
          'email': email.trim(),
          'phoneNumber': phoneNumber.trim(), // Store phone number
          'role': role,
          'school': school, // Store selected school
          'department': department, // Store selected department
          'course': course, // Store selected course
          'createdAt': FieldValue.serverTimestamp(), // Use server timestamp
          'isVerified': firebaseUser.emailVerified, // Store initial verification status
          // Store student-specific fields conditionally
          'registrationNumber': isStudent ? registrationNumber?.trim() : null,
          'yearOfStudy': isStudent ? yearOfStudy : null,
          'semester': isStudent ? semester : null,
          // Add 'updatedAt': FieldValue.serverTimestamp() if needed for tracking updates
        };

        // Remove null values before setting to Firestore (optional, keeps docs cleaner)
        userData.removeWhere((key, value) => value == null);

        // 6. Create user document in Firestore using UID as document ID
        await _firestore.collection('users').doc(firebaseUser.uid).set(userData);
        print("User document created in Firestore for UID: ${firebaseUser.uid}");

        // Note: _userFromFirebaseUser will fetch this data upon the next auth state change.
        // The `user` stream will automatically emit the new user state.
      } else {
         // Handle case where user creation returned null (unlikely but possible)
         throw AuthException('User registration failed unexpectedly. Please try again.');
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      // Handle specific Firebase Auth errors during signup
      print("FirebaseAuthException during signup: ${e.code} - ${e.message}");
      String message = 'An error occurred during registration.';
      if (e.code == 'weak-password') { message = 'The password provided is too weak (minimum 6 characters).'; }
      else if (e.code == 'email-already-in-use') { message = 'An account already exists for that email.'; }
      else if (e.code == 'invalid-email') { message = 'The email address is not valid.'; }
      // Add more specific error codes if needed
      throw AuthException(message);
    } catch (e) {
      // Handle other errors (e.g., Firestore errors, validation errors from this method)
      print("Unexpected error during sign up: $e");
      // If it's already an AuthException, rethrow it, otherwise wrap it
      if (e is AuthException) {
        rethrow;
      }
      throw AuthException('An unexpected error occurred. Please check your connection and try again.');
    }
  }


  // --- Login Method ---
  /// Signs in with email/password, checks email verification,
  /// and returns the custom app_user.User object upon success.
  Future<app_user.User?> login(String email, String password, {bool skipEmailVerification = false}) async {
    try {
      // 1. Sign in using Firebase Auth
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final fbUser = userCredential.user;

      // 2. Check if sign-in was successful and user object exists
      if (fbUser == null) {
        throw AuthException('Login failed, please try again.');
      }

      // 3. Check for email verification (if not skipped)
      // Reload user data to get the latest emailVerified status from Firebase
      await fbUser.reload();
      // Get the potentially updated user instance after reload
      final freshFbUser = _firebaseAuth.currentUser;

      // Ensure user still exists after reload and check verification status
      if (!skipEmailVerification && freshFbUser != null && !freshFbUser.emailVerified) {
        print("Login attempt failed: Email not verified for ${freshFbUser.email}");
        // Sign out the user locally as they shouldn't proceed
        await _firebaseAuth.signOut();
        // Throw specific error to inform the user
        throw AuthException('Please verify your email before logging in. Check your inbox (and spam folder).');
        // Consider adding a button in UI to trigger resendVerificationEmail
      }

      // 4. Fetch the corresponding custom user data from Firestore using the refreshed user
      // This call will also update _currentUser and notify listeners if successful
      final appUser = await _userFromFirebaseUser(freshFbUser);

      // 5. Check if custom user data was found in Firestore
      if (appUser == null) {
        // This indicates an inconsistency (Auth user exists, Firestore data doesn't)
        print("Login failed: User data not found in database for UID ${freshFbUser?.uid}. Logging out.");
        // Log the user out from Firebase Auth to prevent inconsistent state
        await _firebaseAuth.signOut();
        throw AuthException('Login failed: User data incomplete. Please contact support.');
      }

      // 6. Login successful, return the custom user object
      print("Login successful for ${appUser.email}, Role: ${appUser.role}");
      // No need for extra notifyListeners() here, _userFromFirebaseUser handles it.
      return appUser;

    } on fb_auth.FirebaseAuthException catch (e) {
      // Handle specific Firebase Auth errors during sign-in
      print("FirebaseAuthException during login: ${e.code} - ${e.message}");
      String message = 'An error occurred during login.';
      // Combine checks for common invalid credential errors
      if (['user-not-found', 'wrong-password', 'invalid-credential', 'invalid-email'].contains(e.code)) {
         message = 'Invalid email or password.';
      } else if (e.code == 'user-disabled') {
         message = 'This user account has been disabled.';
      } else if (e.code == 'too-many-requests') {
         message = 'Too many login attempts. Please try again later.';
      }
      throw AuthException(message); // Throws custom exception
    } catch (e) {
      // Handle other unexpected errors (e.g., network issues, Firestore errors in _userFromFirebaseUser)
      print("Error during login: $e");
      // Clear cache just in case and notify if state changes
      if (_currentUser != null) {
         _currentUser = null;
         notifyListeners();
      }
      if (e is AuthException) { // Rethrow if it's already our custom type
         rethrow;
      }
      throw AuthException('An unexpected error occurred. Please try again.');
    }
  }


  // --- Resend Verification Email Method ---
  Future<void> resendVerificationEmail() async {
    final fbUser = _firebaseAuth.currentUser;

    if (fbUser == null) {
      // This shouldn't happen if called from a context where user tried to log in
      throw AuthException('Cannot resend email. No user session found.');
    }

    try {
      // Reload to ensure status is up-to-date before checking/resending
      await fbUser.reload();
      final freshFbUser = _firebaseAuth.currentUser; // Get reloaded instance

      if (freshFbUser == null) { // Check again after reload
         throw AuthException('Could not find user session after refresh. Please log in again.');
      }

      if (freshFbUser.emailVerified) {
        // Don't throw, just inform the user.
        print('Email ${freshFbUser.email} is already verified.');
        // Optionally, you could return a specific status or message
        return; // Or throw AuthException('Your email is already verified.');
      }

      await freshFbUser.sendEmailVerification();
      print("Verification email resent to ${freshFbUser.email}");
      // Inform UI via snackbar or message that email was sent

    } on fb_auth.FirebaseAuthException catch (e) {
       print("Error resending verification email: ${e.code} - ${e.message}");
       if (e.code == 'too-many-requests') {
         throw AuthException('Too many requests. Please wait a while before trying again.');
       }
       throw AuthException('Failed to resend verification email. Please try again later.');
    } catch (e) {
       print("Unexpected error resending verification email: $e");
       throw AuthException('An unexpected error occurred while resending email.');
    }
  }

  // --- Password Reset Method ---
  Future<void> sendPasswordResetEmail(String email) async {
    if (email.trim().isEmpty) {
       throw AuthException('Please enter your email address.');
    }
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
      print("Password reset email sent to ${email.trim()}");
      // Inform UI via snackbar or message
    } on fb_auth.FirebaseAuthException catch (e) {
      print("FirebaseAuthException during password reset: ${e.code} - ${e.message}");
      String message = 'Could not send password reset email.';
      // Use more specific messages based on error codes
      if (e.code == 'user-not-found' || e.code == 'invalid-email') {
        message = 'No user found for that email address.';
      } else if (e.code == 'missing-email') {
         message = 'Please enter your email address.'; // Should be caught by initial check
      }
      throw AuthException(message);
    } catch (e) {
      print("Unexpected error sending password reset: $e");
      throw AuthException('An unexpected error occurred. Please try again.');
    }
  }


  // --- Sign Out Method ---
  Future<void> logout() async {
    try {
      await _firebaseAuth.signOut();
      // The `user` stream listener (`_userFromFirebaseUser(null)`) will automatically
      // clear the cache (`_currentUser = null`) and notify listeners.
      print("User logged out successfully.");
    } catch (e) {
      print("Error during sign out: $e");
      // Typically, don't throw an exception here, just log the error.
      // If sign-out fails, the user might still be technically logged in on Firebase side,
      // but the local state might become inconsistent. A restart might be needed.
    }
  }

  // Get current Firebase User (can be useful for direct Firebase interactions)
  fb_auth.User? get currentFirebaseUser => _firebaseAuth.currentUser;

  // Refresh custom user data manually (e.g., after profile update elsewhere)
  Future<app_user.User?> refreshCurrentUser() async {
     print("Manual user refresh triggered.");
     final fbUser = _firebaseAuth.currentUser;
     if (fbUser != null) {
       try {
          // Reload Firebase user data first (updates token, emailVerified status etc.)
          await fbUser.reload();
       } catch (e) {
          print("Error reloading Firebase user: $e");
          // Handle specific errors like expired token, which might require logout
          if (e is fb_auth.FirebaseAuthException && (e.code == 'user-token-expired' || e.code == 'user-disabled' || e.code == 'user-not-found')) {
             await logout(); // Force logout if user state is invalid
             throw AuthException('Session invalid or user disabled. Please log in again.');
          }
          // For other reload errors, you might log it but still attempt to fetch Firestore data
       }
     }
     // Fetch Firestore data again using the potentially reloaded user
     // This call updates cache and notifies listeners via _userFromFirebaseUser
     final appUser = await _userFromFirebaseUser(_firebaseAuth.currentUser);
     return appUser;
  }
}
