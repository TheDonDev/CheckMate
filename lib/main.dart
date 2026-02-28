// lib/main.dart
import 'package:checkmate/services/auth_service.dart';
import 'package:checkmate/wrapper.dart'; 
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kDebugMode, kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:provider/provider.dart';

// Import Firebase service packages (needed for live connection)
// import 'package:firebase_auth/firebase_auth.dart';
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:cloud_functions/cloud_functions.dart';
// import 'package:firebase_storage/firebase_storage.dart';

import 'firebase_options.dart';



Future<void> main() async {
  // Flutter bindings are initialized before any Flutter/Firebase code
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize the Google Mobile Ads SDK
  if (!kIsWeb) {
    await MobileAds.instance.initialize();
  }

  // Initialized Firebase using the generated options
  // This will connect to LIVE project defined in firebase_options.dart
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    print("Firebase initialized successfully (connecting to live project).");
  } catch (e) {
    print("Error initializing Firebase: $e");
    //  an error UI or exiting if Firebase init fails
    return; // Exits if Firebase fails to initialize
  }

  
  if (kDebugMode) {
     print('--- Running in Debug mode: Using Production Firebase ---');
  } else {
    print('--- Running in Profile/Release mode: Using Production Firebase ---');
  }

  // Run the app
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthService>(
      create: (_) => AuthService(), // Create an instance of AuthService
      child: MaterialApp(
        title: 'CheckMate', //  application title
        theme: ThemeData(
          // Define app's theme
          primarySwatch: Colors.blue, // Example primary color
          visualDensity: VisualDensity.adaptivePlatformDensity,
          useMaterial3: true, // Recommended for modern Flutter look
          // Define input decoration theme for consistent text fields
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8.0)),
            ),
            contentPadding: EdgeInsets.symmetric(vertical: 14.0, horizontal: 12.0),
          ),
          // Define button themes for consistency
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8.0),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14.0, horizontal: 20.0),
              textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
            ),
          ),
          textButtonTheme: TextButtonThemeData(
            style: TextButton.styleFrom(
               textStyle: const TextStyle(fontSize: 14),
            ),
          ),
        ),
        // Start with the Wrapper widget
        // The Wrapper listens to auth state and show WelcomeScreen or the appropriate Dashboard
        home: const Wrapper(),
        debugShowCheckedModeBanner: false, // Hide debug banner in debug mode
      ),
    );
  }
}
