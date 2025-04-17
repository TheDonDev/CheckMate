// lib/services/auth_service.dart
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth;
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

  app_user.User? _currentUser; // Cache the current user
  app_user.User? get currentUser => _currentUser;

  // Convert Firebase User to custom User model, fetching role from Firestore
  Future<app_user.User?> _userFromFirebaseUser(fb_auth.User? firebaseUser) async {
    if (firebaseUser == null) {
      _currentUser = null; // Clear cache on null user
      return null;
    }
    try {
      DocumentSnapshot userDoc = await _firestore.collection('users').doc(firebaseUser.uid).get();
      if (userDoc.exists) {
        final user = app_user.User.fromFirestore(userDoc);
        _currentUser = user; // Update cache
        return user;
      } else {
        print("Warning: User document not found in Firestore for UID: ${firebaseUser.uid}");
        // If Firestore data is critical for app function, maybe log out here?
        // await logout(); // Example: Force logout if data is missing
        _currentUser = null; // Clear cache if data missing
        return null; // Or throw an exception indicating data inconsistency
      }
    } catch (e) {
      print("Error fetching user data from Firestore: $e");
      _currentUser = null; // Clear cache on error
      return null; // Or rethrow a specific error
    }
  }

  // Stream of custom User objects
  Stream<app_user.User?> get user {
    return _firebaseAuth.authStateChanges().asyncMap((fbUser) async {
      final appUser = await _userFromFirebaseUser(fbUser);
      // No need to notifyListeners here, StreamBuilder handles updates
      return appUser;
    });
    // Alternative: Use map and switchMap if _userFromFirebaseUser returned a Stream
  }

  // Sign Up
  Future<void> signUp(
    String name,
    String email,
    String password,
    String? school, // Nullable as per User model
    String? department, // Nullable
    String? course, // Nullable
  ) async {
    try {
      // Create user with email/password
      fb_auth.UserCredential userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      fb_auth.User? firebaseUser = userCredential.user;

      if (firebaseUser != null) {
        // Send verification email
        await firebaseUser.sendEmailVerification();

        // *** IMPORTANT: Role assignment logic needs careful consideration ***
        // This basic example assumes 'lecturer' keyword in email.
        // A more robust system (e.g., admin panel, specific domain) is recommended for production.
        String role = email.toLowerCase().contains('lecturer') ? 'lecturer' : 'student';

        // Create user document in Firestore
        await _firestore.collection('users').doc(firebaseUser.uid).set({
          'uid': firebaseUser.uid,
          'name': name,
          'email': email,
          'role': role,
          'school': school, // Store potentially null value
          'department': department, // Store potentially null value
          'course': course, // Store potentially null value
          'createdAt': FieldValue.serverTimestamp(), // Use server timestamp
          // Add 'updatedAt': FieldValue.serverTimestamp() if needed
          // Add 'emailVerified': false // Explicitly set if needed, though Firebase handles it
        });
        // Note: _userFromFirebaseUser will fetch this data upon next auth state change
        // No need to manually set _currentUser here.
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      // Handle specific Firebase Auth errors during signup
      print("FirebaseAuthException during signup: ${e.code} - ${e.message}");
      String message = 'An error occurred during registration.';
      if (e.code == 'weak-password') { message = 'The password provided is too weak (min 6 characters).'; }
      else if (e.code == 'email-already-in-use') { message = 'An account already exists for that email.'; }
      else if (e.code == 'invalid-email') { message = 'The email address is not valid.'; }
      throw AuthException(message);
    } catch (e) {
      // Handle other unexpected errors
      print("Error during sign up: $e");
      throw AuthException('An unexpected error occurred. Please try again.');
    }
  }


  // --- NEW login Method ---
  /// Signs in with email/password, checks email verification (optional),
  /// and returns the custom app_user.User object.
  Future<app_user.User?> login(String email, String password, {bool skipEmailVerification = false}) async {
    try {
      // 1. Sign in using Firebase Auth
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final fbUser = userCredential.user;

      // 2. Check if sign-in was successful and user object exists
      if (fbUser == null) {
        // This case should ideally not happen if signInWithEmailAndPassword succeeds,
        // but handle it defensively.
        throw AuthException('Login failed, please try again.');
      }

      // 3. Check for email verification (if not skipped)
      // Reload user data to get the latest emailVerified status
      await fbUser.reload();
      final freshFbUser = _firebaseAuth.currentUser; // Get the reloaded user instance

      if (!skipEmailVerification && freshFbUser != null && !freshFbUser.emailVerified) {
        print("Login attempt failed: Email not verified for ${freshFbUser.email}");
        // Optionally resend verification email automatically here
        // await freshFbUser.sendEmailVerification();
        throw AuthException('Please verify your email before logging in. Check your inbox (and spam folder). You can resend the email from the login screen.');
      }

      // 4. Fetch the corresponding custom user data from Firestore using the refreshed user
      final appUser = await _userFromFirebaseUser(freshFbUser);

      // 5. Check if custom user data was found
      if (appUser == null) {
        // This indicates an inconsistency (Auth user exists, Firestore data doesn't)
        print("Login failed: User data not found in database for UID ${freshFbUser?.uid}.");
        // Log the user out to prevent inconsistent state
        await logout(); // This will trigger authStateChanges and notify listeners
        throw AuthException('Login failed: User data incomplete. Please contact support or try registering again.');
      }

      // 6. Return the custom user object
      print("Login successful for ${appUser.email}, Role: ${appUser.role}");
      // Notify listeners about the successful login and potential user data update
      // The stream already notifies, but an explicit notify might be useful
      // if other parts of the app listen directly to AuthService state.
      notifyListeners();
      return appUser;

    } on fb_auth.FirebaseAuthException catch (e) {
      // Handle specific Firebase Auth errors during sign-in
      print("FirebaseAuthException during login: ${e.code} - ${e.message}");
      String message = 'An error occurred during login.';
      // Combine checks for common invalid credential errors
      if (['user-not-found', 'wrong-password', 'invalid-credential', 'invalid-email'].contains(e.code)) {
         message = 'Invalid email or password.';
      // } else if (e.code == 'invalid-email') { // Covered above
      //    message = 'The email address format is not valid.';
      } else if (e.code == 'user-disabled') {
         message = 'This user account has been disabled.';
      } else if (e.code == 'too-many-requests') {
         message = 'Too many login attempts. Please try again later.';
      }
      throw AuthException(message); // Throw custom exception
    } catch (e) {
      // Handle other unexpected errors
      print("Error during login: $e");
      // Clear cache just in case
      _currentUser = null;
      notifyListeners();
      throw AuthException('An unexpected error occurred. Please try again.');
    }
  }

  // --- Deprecated signIn Method (Optional: Keep for compatibility or remove) ---
  // Keep the old signIn if other parts of the app might still use it,
  // otherwise, remove it to avoid confusion. It doesn't handle email verification
  // or return the user object like the new `login` method.
  /*
  Future<void> signIn(String email, String password) async {
    try {
      await _firebaseAuth.signInWithEmailAndPassword(email: email, password: password);
      // Does not check verification or fetch user data automatically
      // Relies on the authStateChanges stream
    } on fb_auth.FirebaseAuthException catch (e) {
      // ... old error handling ...
      throw AuthException('...');
    } catch (e) {
      throw AuthException('...');
    }
  }
  */

  // --- NEW resendVerificationEmail Method ---
  Future<void> resendVerificationEmail() async {
    // Try to get current user, might be null if called before login attempt
    final fbUser = _firebaseAuth.currentUser;

    if (fbUser == null) {
      // Ideally, prompt user to enter their email if not logged in
      throw AuthException('Cannot resend email. Please enter your email and try logging in first.');
    }

    // Reload to ensure status is up-to-date
    await fbUser.reload();
    final freshFbUser = _firebaseAuth.currentUser;

    if (freshFbUser == null) { // Check again after reload
       throw AuthException('Could not find user session. Please log in again.');
    }

    if (freshFbUser.emailVerified) {
      throw AuthException('Your email is already verified.');
    }

    try {
      await freshFbUser.sendEmailVerification();
      print("Verification email resent to ${freshFbUser.email}");
    } on fb_auth.FirebaseAuthException catch (e) {
       print("Error resending verification email: ${e.code} - ${e.message}");
       // Handle specific errors like 'too-many-requests'
       if (e.code == 'too-many-requests') {
         throw AuthException('Too many requests. Please wait a while before trying again.');
       }
       throw AuthException('Failed to resend verification email. Please try again later.');
    } catch (e) {
       print("Error resending verification email: $e");
       throw AuthException('An unexpected error occurred while resending email.');
    }
  }


  // Sign Out
  Future<void> logout() async {
    try {
      await _firebaseAuth.signOut();
      _currentUser = null; // Clear cache
      notifyListeners(); // Notify listeners about logout
      print("User logged out successfully.");
    } catch (e) {
      print("Error during sign out: $e");
      // Don't throw AuthException here usually, just log
      // throw AuthException('Error signing out.');
    }
  }

  // Get current Firebase User (can be useful for direct Firebase interactions)
  fb_auth.User? get currentFirebaseUser => _firebaseAuth.currentUser;

  // Refresh custom user data manually (if needed, e.g., after profile update)
  Future<app_user.User?> refreshCurrentUser() async {
     print("Manual user refresh triggered.");
     final fbUser = _firebaseAuth.currentUser;
     if (fbUser != null) {
       await fbUser.reload(); // Reload Firebase user data
     }
     final appUser = await _userFromFirebaseUser(_firebaseAuth.currentUser); // Fetch Firestore data again
     notifyListeners(); // Notify listeners of potential change
     return appUser;
  }
}
