import 'dart:async'; // For Timer if needed, though controller handles repetition
import 'package:checkmate/screens/login_screen.dart';
import 'package:checkmate/screens/register_screen.dart';
import 'package:flutter/material.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

// Use SingleTickerProviderStateMixin for the AnimationController
class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation; // Controls the opacity of the incoming image

  // List of background images
  final List<String> _backgroundImages = [
    'assets/images/WorkStationDay.jpg',
    'assets/images/WorkStationLine.jpg',
    'assets/images/WorkStationNight.jpg',
    'assets/images/WorkStationLine2.jpg',
  ];

  int _currentIndex = 0; // Index of the image currently fully visible or fading out

  @override
  void initState() {
    super.initState();

    // Initialize the AnimationController
    _controller = AnimationController(
      duration: const Duration(seconds: 2), // Duration for the fade transition
      vsync: this,
    );

    // Create a Tween for the fade animation (0.0 = transparent, 1.0 = opaque)
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(_controller);

    // Add a listener to update the index when one fade cycle completes
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Move to the next image index
        setState(() {
          _currentIndex = (_currentIndex + 1) % _backgroundImages.length;
        });
        // Reset the controller to start the fade for the *next* image
        _controller.reset();
        // Start the next fade cycle after a short pause
        Future.delayed(const Duration(seconds: 3), () { // Pause showing the image
           if (mounted) { // Check if widget is still in the tree
             _controller.forward();
           }
        });
      }
    });

    // Start the first fade-in animation after an initial delay
     Future.delayed(const Duration(seconds: 1), () {
        if (mounted) {
          _controller.forward();
        }
     });
  }

  @override
  void dispose() {
    _controller.dispose(); // Dispose the controller when the widget is removed
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Calculate the index of the next image to fade in
    int nextIndex = (_currentIndex + 1) % _backgroundImages.length;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand, // Make stack children fill the screen
        children: [
          // --- Background Image Layer ---
          // Image currently fully visible (or fading out) - Always at the bottom
          Image.asset(
            _backgroundImages[_currentIndex],
            fit: BoxFit.cover, // Cover the entire screen
            key: ValueKey<int>(_currentIndex), // Key helps Flutter identify the image
          ),

          // Image fading in - On top, controlled by AnimatedOpacity
          AnimatedOpacity(
            opacity: _fadeAnimation.value, // Opacity driven by the animation
            duration: _controller.duration!, // Match controller duration
            child: Image.asset(
              _backgroundImages[nextIndex],
              fit: BoxFit.cover,
              key: ValueKey<int>(nextIndex),
            ),
          ),

          // --- Optional: Dark overlay for better text contrast ---
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.5), // Darker at the bottom
                  Colors.black.withOpacity(0.2), // Lighter at the top
                  Colors.black.withOpacity(0.5), // Darker at the bottom again
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),

          // --- Content Layer (Title, Buttons) ---
          SafeArea( // Keep content within safe areas
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30.0, vertical: 40.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, // Space out elements
                children: [
                  // Top Section (e.g., App Title/Logo)
                  Column(
                    children: [
                       const SizedBox(height: 40), // Add some space at the top
                       // You could add your logo here if desired
                       Image.asset('assets/images/image.png', height: 80),
                       const SizedBox(height: 20),
                       Text(
                        'CheckMate',
                        style: TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          shadows: [
                            Shadow(
                              blurRadius: 10.0,
                              color: Colors.black.withOpacity(0.5),
                              offset: const Offset(2.0, 2.0),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Effortless Attendance Tracking',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.white.withOpacity(0.9),
                        ),
                      ),
                    ],
                  ),

                  // Bottom Section (Buttons)
                  Column(
                    mainAxisSize: MainAxisSize.min, // Take minimum space
                    children: [
                      // Login Button
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50), // Full width
                          backgroundColor: Colors.white, // White background
                          foregroundColor: Theme.of(context).primaryColorDark, // Text color
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30), // Rounded
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const LoginScreen()),
                          );
                        },
                        child: const Text('Login', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 20), // Space between buttons

                      // Register Button
                      OutlinedButton(
                         style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 50), // Full width
                          foregroundColor: Colors.white, // Text color
                          side: const BorderSide(color: Colors.white, width: 1.5), // White border
                           shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30), // Rounded
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegisterScreen()),
                          );
                        },
                        child: const Text('Register', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      ),
                       const SizedBox(height: 20), // Add some space at the bottom
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
