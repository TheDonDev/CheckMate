// lib/services/auth_service.dart
import 'package:checkmate/models/app_user.dart' as app_user; // Use prefix for clarity
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb_auth; // Use prefix for clarity
import 'package:flutter/foundation.dart'; // Import ChangeNotifier

// Custom Exception for Auth errors
class AuthException implements Exception {
  final String message;
  // Add a code for specific error types (like email not verified)
  final String? code;
  AuthException(this.message, {this.code});

  @override
  String toString() => message;
}

class AuthService extends ChangeNotifier {
  final fb_auth.FirebaseAuth _firebaseAuth = fb_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final String _usersCollection = 'users'; // Use a constant for collection name

  // --- Add the special user email constant ---
  static const String _specialBypassEmail = "muhambe@au.ac.ke";

  app_user.User? _currentUser; // Cache the current user model
  app_user.User? get currentUser => _currentUser;

  // Convert Firebase User to custom User model, fetching data from Firestore
  Future<app_user.User?> _userFromFirebaseUser(fb_auth.User? firebaseUser) async {
    if (firebaseUser == null) {
      if (_currentUser != null) { // Only notify if state changes from non-null to null
        _currentUser = null; // Clear cache on null user
        notifyListeners(); // Notify listeners about the change
      }
      return null;
    }
    try {
      // Fetch the user document from Firestore using the UID
      DocumentSnapshot userDoc = await _firestore.collection(_usersCollection).doc(firebaseUser.uid).get();

      if (userDoc.exists) {
        // Create our custom User object from the Firestore data
        // Data read from Firestore will reflect the case it was saved in (e.g., uppercase fields)
        final user = app_user.User.fromFirestore(userDoc);

        // Update cache and notify listeners only if the user data has changed
        if (_currentUser != user) {
           _currentUser = user; // Update cache
           notifyListeners(); // Notify listeners about the change
        }
        return user;
      } else {
        // Inconsistency: Auth user exists, but Firestore data is missing.
        print("Warning: User document not found in Firestore for UID: ${firebaseUser.uid}. Logging out.");
        await _firebaseAuth.signOut(); // Sign out from Firebase Auth
        return null; // Return null as the user data is incomplete
      }
    } catch (e) {
      print("Error fetching user data from Firestore for UID ${firebaseUser.uid}: $e");
      if (_currentUser != null) {
         _currentUser = null;
         notifyListeners();
      }
      return null;
    }
  }

  // Stream of custom User objects reflecting authentication state
  Stream<app_user.User?> get user {
    return _firebaseAuth.authStateChanges().asyncMap((fbUser) async {
      final appUser = await _userFromFirebaseUser(fbUser);
      // Trigger sync on auth state change if user exists
      if (fbUser != null) {
        // Don't automatically sync for the bypass user unless they ARE verified in Auth
        // This prevents accidentally setting isVerified to true in Firestore if they haven't actually verified
        // The backend lecture creation bypass handles the Firestore isVerified=false case for them.
        if (fbUser.email?.toLowerCase() != _specialBypassEmail || fbUser.emailVerified) {
           syncFirestoreVerificationStatus(authUser: fbUser);
        }
      }
      return appUser;
    });
  }

  // --- Sync Auth verification status to Firestore ---
  Future<void> syncFirestoreVerificationStatus({fb_auth.User? authUser}) async {
    final fb_auth.User? firebaseUser = authUser ?? _firebaseAuth.currentUser;
    if (firebaseUser == null) return;

    // --- Revised Logic: Always try to reload, then check verification ---
    // The stream logic above already prevents calling this unnecessarily for the bypass user
    // if they aren't verified in Auth. If this function *is* called, proceed as normal.

    try {
      await firebaseUser.reload(); // Get latest status from Firebase
    } catch (e) {
       print("syncFirestoreVerificationStatus: Error reloading Firebase user: $e");
       if (e is fb_auth.FirebaseAuthException && (e.code == 'user-token-expired' || e.code == 'user-disabled' || e.code == 'user-not-found')) {
          await logout(); // Force logout if user state is invalid
       }
       return;
    }
    final fb_auth.User? refreshedFirebaseUser = _firebaseAuth.currentUser; // Get refreshed instance

    // --- Only update Firestore if the user IS verified in Firebase Auth ---
    if (refreshedFirebaseUser != null && refreshedFirebaseUser.emailVerified) {
      final userDocRef = _firestore.collection(_usersCollection).doc(refreshedFirebaseUser.uid);
      try {
        final userDocSnapshot = await userDocRef.get();
        if (userDocSnapshot.exists) {
          final bool firestoreIsVerified = userDocSnapshot.data()?['isVerified'] as bool? ?? false;
          if (!firestoreIsVerified) {
            print('syncFirestoreVerificationStatus: Updating Firestore isVerified for ${refreshedFirebaseUser.uid}...');
            await userDocRef.update({'isVerified': true});
            print('syncFirestoreVerificationStatus: Firestore isVerified field updated successfully.');
            // Refresh local cache immediately after successful Firestore update
            // Use await here to ensure refresh completes before potential subsequent reads
            await refreshCurrentUser();
          }
        } else {
          print('syncFirestoreVerificationStatus: Warning - Firestore document not found for user ${refreshedFirebaseUser.uid}.');
        }
      } catch (e) {
        print('syncFirestoreVerificationStatus: Error accessing/updating Firestore: $e');
      }
    }
    // --- If user is NOT verified in Firebase Auth, we do NOT update Firestore isVerified to false here ---
    // This allows the bypass user to potentially have isVerified=true in Firestore (set manually or previously)
    // while still having emailVerified=false in Auth, and the login bypass will still work.
  }


  // --- Sign Up Method ---
  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required String phoneNumber, // Expecting +254 format
    required String? school,
    required String? department,
    required String? course,
    String? registrationNumber,
    String? yearOfStudy,
    String? semester,
  }) async {
    // Trim inputs early, apply case changes just before saving
    final trimmedName = name.trim();
    final trimmedEmail = email.trim().toLowerCase(); // Keep email lowercase
    final trimmedPhoneNumber = phoneNumber.trim();
    final trimmedRegNumber = registrationNumber?.trim();
    // Trim optional year/semester fields before uppercasing
    final trimmedYearOfStudy = yearOfStudy?.trim();
    final trimmedSemester = semester?.trim();

    // Validate required fields (use trimmed versions where applicable)
    if (trimmedName.isEmpty || trimmedEmail.isEmpty || password.isEmpty || trimmedPhoneNumber.isEmpty ||
        school == null || school.trim().isEmpty ||
        department == null || department.trim().isEmpty ||
        course == null || course.trim().isEmpty) {
       throw AuthException('Please fill in all required fields (Name, Email, Phone, School, Department, Course).');
    }

    try {
      fb_auth.UserCredential userCredential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: trimmedEmail, // Use trimmed/lowercase email for Auth
        password: password,
      );
      fb_auth.User? firebaseUser = userCredential.user;

      if (firebaseUser != null) {
        // Send verification email (best effort), *unless* it's the special user
        if (!firebaseUser.emailVerified && trimmedEmail != _specialBypassEmail) {
           try {
              await firebaseUser.sendEmailVerification();
              print("Verification email sent to $trimmedEmail");
           } catch (e) {
              print("Error sending verification email: $e"); // Log error but continue
           }
        } else if (trimmedEmail == _specialBypassEmail) {
            print("Skipping verification email for special user: $trimmedEmail");
        }

        final bool isStudent = trimmedEmail.endsWith('@student.au.ac.ke');
        final String role = isStudent ? 'student' : 'lecturer'; // Role likely lowercase

        // Validate student-specific fields (use trimmed versions)
        if (isStudent && (trimmedRegNumber == null || trimmedRegNumber.isEmpty || trimmedYearOfStudy == null || trimmedYearOfStudy.isEmpty || trimmedSemester == null || trimmedSemester.isEmpty)) {
            throw AuthException('Student registration requires Registration Number, Year of Study, and Semester.');
        }

        // Set isVerified true ONLY for the special user during signup
        final bool initialVerificationStatus = (trimmedEmail == _specialBypassEmail);

        // --- MODIFICATION: Apply .toUpperCase() to specific fields before saving ---
        Map<String, dynamic> userData = {
          'uid': firebaseUser.uid,
          'name': trimmedName.toUpperCase(), // Save name in uppercase
          'email': trimmedEmail, // Save email in lowercase
          'phoneNumber': trimmedPhoneNumber, // Save phone number as trimmed
          'role': role, // Save role as determined (likely lowercase)
          'school': school.trim().toUpperCase(), // Save school trimmed & uppercase
          'department': department.trim().toUpperCase(), // Save department trimmed & uppercase
          'course': course.trim().toUpperCase(), // Save course trimmed & uppercase
          'createdAt': FieldValue.serverTimestamp(),
          'isVerified': initialVerificationStatus,
          // Save registration number in uppercase only if student and provided
          'registrationNumber': isStudent ? trimmedRegNumber?.toUpperCase() : null,
          // *** Save year/semester trimmed & uppercase only if student and provided ***
          'yearOfStudy': isStudent ? trimmedYearOfStudy?.toUpperCase() : null,
          'semester': isStudent ? trimmedSemester?.toUpperCase() : null,
        };
        // Remove any keys where the value is null (like registrationNumber for non-students)
        userData.removeWhere((key, value) => value == null);
        // --- END MODIFICATION ---

        await _firestore.collection(_usersCollection).doc(firebaseUser.uid).set(userData);
        print("User document created in Firestore for UID: ${firebaseUser.uid} with isVerified: $initialVerificationStatus and specified fields in uppercase.");

        // --- Refresh local user cache after successful signup and Firestore write ---
        // This ensures the _currentUser reflects the newly created user data immediately
        await _userFromFirebaseUser(firebaseUser); // Fetch and cache the new user data

      } else {
         throw AuthException('User registration failed unexpectedly. Please try again.');
      }
    } on fb_auth.FirebaseAuthException catch (e) {
      print("FirebaseAuthException during signup: ${e.code} - ${e.message}");
      throw AuthException(_handleFirebaseAuthError(e));
    } catch (e) {
      print("Unexpected error during sign up: $e");
      if (e is AuthException) rethrow;
      throw AuthException('An unexpected error occurred. Please check your connection and try again.');
    }
  }


  // --- Login Method (MODIFIED for email verification handling AND special user bypass) ---
  Future<app_user.User?> login(String email, String password) async { 
    final trimmedEmail = email.trim().toLowerCase(); //  lowercase for comparison

    try {
      // 1. Sign in using Firebase Auth
      final userCredential = await _firebaseAuth.signInWithEmailAndPassword(
        email: trimmedEmail, //  trimmed/lowercase email
        password: password,
      );
      final fbUser = userCredential.user;

      if (fbUser == null) {
        throw AuthException('Login failed, please try again.');
      }

      // 2. Reload user data to get the latest emailVerified status
      await fbUser.reload();
      final freshFbUser = _firebaseAuth.currentUser; // Get reloaded instance

      if (freshFbUser == null) {
         throw AuthException('Login failed: User session is invalid. Please try again.');
      }

      // --- MODIFICATION START: Bypass verification check for the special user ---
      final bool isSpecialUser = freshFbUser.email?.toLowerCase() == _specialBypassEmail;

      // 3. Check verification status ONLY if it's NOT the special user
      if (!isSpecialUser && !freshFbUser.emailVerified) {
        print("Login attempt halted: Email not verified for ${freshFbUser.email}");
        // Throw specific exception instead of signing out
        throw AuthException(
          'Please verify your email before logging in. Check your inbox (and spam folder). You can use the "Resend Email" button.',
          code: 'email-not-verified' // Add a code for specific handling in UI
        );
      } else if (isSpecialUser) {
          print("Login verification check bypassed for special user: ${freshFbUser.email}");
      }
      // --- MODIFICATION END ---


      // 4. Sync Firestore verification status (important after verification check)
      // Run asynchronously. This will update Firestore if the user *is* verified in Auth.
      // It won't run if the stream listener already decided not to call it for the bypass user.
      // Or if called, it will correctly update Firestore if the bypass user *did* verify.
      // Use await here to ensure sync completes before fetching user data,
      // especially if sync might update the isVerified status we rely on.
      await syncFirestoreVerificationStatus(authUser: freshFbUser);


      // 5. Fetch custom user data from Firestore
      // This will now read the potentially uppercase fields saved during signup
      final appUser = await _userFromFirebaseUser(freshFbUser);

      if (appUser == null) {
        // Inconsistency: Auth user exists, Firestore data doesn't OR failed to fetch
        // _userFromFirebaseUser already handles the specific case of missing doc vs fetch error
        // If it returns null after a successful login, something is wrong.
        print("Login failed: Could not retrieve user data from database for UID ${freshFbUser.uid} after login. Logging out.");
        await _firebaseAuth.signOut(); // Sign out to prevent bad state
        throw AuthException('Login failed: User data incomplete or inaccessible. Please contact support.');
      }

      // 6. Login successful
      // Include whether the bypass was used in the log message
      // Note: appUser.isVerified now reflects the value from Firestore (which syncFirestoreVerificationStatus might have just updated)
      final verificationStatus = isSpecialUser ? "Verified (Bypass)" : (appUser.isVerified ? "Verified" : "Not Verified");
      print("Login successful for ${appUser.email}, Role: ${appUser.role}, Status: $verificationStatus");
      return appUser;

    } on fb_auth.FirebaseAuthException catch (e) {
      print("FirebaseAuthException during login: ${e.code} - ${e.message}");
      throw AuthException(_handleFirebaseAuthError(e));
    } catch (e) {
      print("Error during login: $e");
      if (_currentUser != null) {
         _currentUser = null;
         notifyListeners();
      }
      if (e is AuthException) rethrow;
      throw AuthException('An unexpected error occurred. Please try again.');
    }
  }


  // --- Resend Verification Email Method ---
  Future<void> resendVerificationEmail() async {
    final fbUser = _firebaseAuth.currentUser;

    if (fbUser == null) {
      throw AuthException('Cannot resend email. Please try logging in first.');
    }

    // --- Don't allow resend for the special bypass user ---
    if (fbUser.email?.toLowerCase() == _specialBypassEmail) {
        print("Resend verification email skipped for special user: ${fbUser.email}");
        throw AuthException('Email verification is not required for this account.');
    }
    

    try {
      // Reload first to ensure we have the latest verification status
      await fbUser.reload();
      final freshFbUser = _firebaseAuth.currentUser; // Get the reloaded instance

      if (freshFbUser == null) {
         // Should not happen if fbUser was not null, but check defensively
         throw AuthException('Could not find user session after refresh. Please log in again.');
      }

      if (freshFbUser.emailVerified) {
        print('Email ${freshFbUser.email} is already verified.');
        // Sync Firestore just in case it wasn't updated before
        await syncFirestoreVerificationStatus(authUser: freshFbUser);
        throw AuthException('Your email address is already verified.');
      }

      await freshFbUser.sendEmailVerification();
      print("Verification email resent to ${freshFbUser.email}");

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
    final trimmedEmail = email.trim(); // Trim before check and use
    if (trimmedEmail.isEmpty) {
       throw AuthException('Please enter your email address.');
    }
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: trimmedEmail);
      print("Password reset email sent to $trimmedEmail");
    } on fb_auth.FirebaseAuthException catch (e) {
      print("FirebaseAuthException during password reset: ${e.code} - ${e.message}");
      throw AuthException(_handleFirebaseAuthError(e));
    } catch (e) {
      print("Unexpected error sending password reset: $e");
      throw AuthException('An unexpected error occurred. Please try again.');
    }
  }


  // --- Sign Out Method ---
  Future<void> logout() async {
    try {
      await _firebaseAuth.signOut();
      print("User logged out successfully.");
      // Clear local cache immediately on explicit logout
      if (_currentUser != null) {
        _currentUser = null;
        notifyListeners();
      }
    } catch (e) {
      print("Error during sign out: $e");
      // Optionally rethrow or handle specific sign-out errors if needed
    }
  }

  // Get current Firebase User
  fb_auth.User? get currentFirebaseUser => _firebaseAuth.currentUser;

  // Refresh custom user data manually
  Future<app_user.User?> refreshCurrentUser() async {
     print("Manual user refresh triggered.");
     final fbUser = _firebaseAuth.currentUser;
     app_user.User? appUser; // Declare appUser outside try-catch

     if (fbUser != null) {
       try {
          await fbUser.reload(); // Reload Firebase user data
          // Fetch Firestore data again using the potentially reloaded user
          // Do this *after* reload but *before* sync, as sync might depend on fresh data
          appUser = await _userFromFirebaseUser(_firebaseAuth.currentUser);

          // Sync status after refresh as well
          // Use the most recent firebase user instance
          final currentFbUser = _firebaseAuth.currentUser;
          if (currentFbUser != null) {
              // Same logic as in the stream listener
              if (currentFbUser.email?.toLowerCase() != _specialBypassEmail || currentFbUser.emailVerified) {
                 // Run sync, but don't necessarily wait for it unless critical path depends on it
                 // Using await here ensures the sync completes before returning the potentially updated user
                 await syncFirestoreVerificationStatus(authUser: currentFbUser);
                 // Re-fetch user data *after* sync if sync might change isVerified status
                 // This ensures the returned user reflects the absolute latest state
                 appUser = await _userFromFirebaseUser(currentFbUser);
              }
          }

       } catch (e) {
          print("Error during manual user refresh process: $e");
          if (e is fb_auth.FirebaseAuthException && (e.code == 'user-token-expired' || e.code == 'user-disabled' || e.code == 'user-not-found')) {
             await logout(); // Force logout if session is invalid
             throw AuthException('Session invalid or user disabled. Please log in again.');
          } else if (e is AuthException) {
             rethrow; // Rethrow custom auth exceptions from nested calls
          }
          // Log other errors but might still return potentially stale appUser if fetch succeeded before error
          // Or return null if fetch also failed or happened after error
          // Consider throwing a generic refresh error here if needed:
          // throw AuthException('Failed to fully refresh user data.');
       }
     } else {
        // If there's no Firebase user, ensure local state is also null
        if (_currentUser != null) {
           _currentUser = null;
           notifyListeners();
        }
        appUser = null;
     }

     return appUser; // Return the fetched (and potentially updated) app user
  }

  // --- Helper to map Firebase Auth errors ---
  String _handleFirebaseAuthError(fb_auth.FirebaseAuthException e) {
     switch (e.code) {
       case 'weak-password': return 'The password provided is too weak.';
       case 'email-already-in-use': return 'An account already exists for that email.';
       case 'invalid-email': return 'The email address is not valid.';
       case 'user-not-found': return 'No user found for that email address.';
       case 'wrong-password': return 'Invalid password provided for that user.';
       case 'invalid-credential': return 'Invalid email or password.'; // More generic for login
       case 'user-disabled': return 'This user account has been disabled.';
       case 'too-many-requests': return 'Too many requests. Please try again later.';
       case 'missing-email': return 'Please enter your email address.';
       // Consider adding network errors if applicable, though often caught higher up
       // case 'network-request-failed': return 'Network error. Please check your connection.';
       default: return 'An unknown authentication error occurred (${e.code})';
     }
  }

} // End of AuthService class
