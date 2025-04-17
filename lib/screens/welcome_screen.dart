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

  // Define the brand color from pubspec.yaml
  static const Color brandColor = Color(0xFF0175C2);

  @override
  void initState() {
    super.initState();

    // Initialize the AnimationController
    _controller = AnimationController(
      duration: const Duration(seconds: 2), // Duration for the fade transition
      vsync: this,
    );

    // Create a Tween for the fade animation (0.0 = transparent, 1.0 = opaque)
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn), // Smoother fade
    );

    // Add a listener to update the index when one fade cycle completes
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Short pause showing the fully faded-in image
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            // Prepare for the next fade: update index *before* reversing
            setState(() {
              _currentIndex = (_currentIndex + 1) % _backgroundImages.length;
              // Reset controller immediately to start the next cycle's fade-in
              _controller.forward(from: 0.0);
            });
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
    final textTheme = Theme.of(context).textTheme; // Get text theme for consistency

    return Scaffold(
      // Prevent content from going under system status bar/notches etc.
      // but allow background to fill the whole screen.
      body: Stack(
        fit: StackFit.expand, // Make stack children fill the screen
        children: [
          // --- Background Image Layer ---
          // Base image (current or fading out)
          Image.asset(
            _backgroundImages[_currentIndex],
            fit: BoxFit.cover,
            key: ValueKey<int>(_currentIndex), // Key helps Flutter identify the image
            gaplessPlayback: true, // Prevents flicker during transition
          ),

          // Fading-in image on top
          FadeTransition(
            opacity: _fadeAnimation,
            child: Image.asset(
              _backgroundImages[nextIndex],
              fit: BoxFit.cover,
              key: ValueKey<int>(nextIndex),
              gaplessPlayback: true,
            ),
          ),

          // --- Darkening Overlay for Text Contrast ---
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.1), // Less dark at the top
                  Colors.black.withOpacity(0.4),
                  Colors.black.withOpacity(0.7), // Darker towards the bottom
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.4, 1.0], // Control gradient points
              ),
            ),
          ),

          // --- Content Layer (Title, Buttons) ---
          SafeArea( // Keep content within safe areas (avoids notches/system bars)
            child: Padding(
              // Increased vertical padding, consistent horizontal
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 50.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, // Pushes content to top and bottom
                crossAxisAlignment: CrossAxisAlignment.center, // Center content horizontally
                children: [
                  // --- Top Section (Logo & Title) ---
                  Column(
                    mainAxisSize: MainAxisSize.min, // Take minimum vertical space
                    children: [
                      const SizedBox(height: 20), // Space from top safe area
                      // Use the actual logo asset specified in pubspec.yaml if 'image.png' is placeholder
                      Image.asset(
                        'assets/images/image.png', // Replace if needed
                        height: 80, // Adjust size as needed
                        // Consider adding semantic label for accessibility
                        // semanticLabel: 'CheckMate App Logo',
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'CheckMate',
                        textAlign: TextAlign.center,
                        style: textTheme.displaySmall?.copyWith( // Use semantic theme style
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          shadows: [
                            Shadow(
                              blurRadius: 8.0,
                              color: Colors.black.withOpacity(0.6),
                              offset: const Offset(1.0, 1.0),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Effortless Attendance Tracking',
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium?.copyWith( // Use semantic theme style
                          color: Colors.white.withOpacity(0.9),
                           shadows: [ // Subtle shadow for better readability
                            Shadow(
                              blurRadius: 4.0,
                              color: Colors.black.withOpacity(0.5),
                              offset: const Offset(0.5, 0.5),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  // --- Bottom Section (Buttons) ---
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Login Button - Primary Action (Uses Brand Color)
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52), // Full width, slightly taller
                          backgroundColor: brandColor, // Use the defined brand color
                          foregroundColor: Colors.white, // White text for contrast
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30), // Smooth curves
                          ),
                          elevation: 5, // Add subtle elevation
                          textStyle: textTheme.titleMedium?.copyWith( // Consistent text style
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const LoginScreen()),
                          );
                        },
                        child: const Text('Login'),
                      ),
                      const SizedBox(height: 16), // Consistent spacing

                      // Register Button - Secondary Action (Outlined)
                      OutlinedButton(
                         style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52), // Match height
                          foregroundColor: Colors.white, // White text for contrast on dark overlay
                          side: const BorderSide(color: Colors.white, width: 1.5), // Clear white border
                           shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30), // Match shape
                          ),
                           textStyle: textTheme.titleMedium?.copyWith( // Consistent text style
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegisterScreen()),
                          );
                        },
                        child: const Text('Register'),
                      ),
                       const SizedBox(height: 10), // Space at the very bottom before edge
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
