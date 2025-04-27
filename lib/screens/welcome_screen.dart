import 'dart:async'; // For Timer
import 'dart:math'; // For Random
import 'package:checkmate/screens/login_screen.dart';
import 'package:checkmate/screens/register_screen.dart';
import 'package:flutter/material.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

// Use TickerProviderStateMixin for multiple controllers if needed,
// but SingleTickerProviderStateMixin is fine for just the background fade.
class _WelcomeScreenState extends State<WelcomeScreen> with SingleTickerProviderStateMixin {
  // --- Background Animation ---
  late AnimationController _backgroundController;
  late Animation<double> _backgroundFadeAnimation;
  final List<String> _backgroundImages = [
    'assets/images/WorkStationDay.jpg',
    'assets/images/WorkStationNight.jpg',
    'assets/images/Alupe-.jpeg',
    'assets/images/MV3.jpg',
    'assets/images/nai3.jpg',
  ];
  int _currentBackgroundIndex = 0;

  // --- Quote Animation ---
  final List<String> _quotes = [
    "The journey of a thousand miles begins with a single step.",
    "Success is not final, failure is not fatal: It is the courage to continue that counts.",
    "Believe you can and you're halfway there.",
    "The only way to do great work is to love what you do.",
    "Strive not to be a success, but rather to be of value.",
    "The mind is everything. What you think you become.",
    "Your time is limited, don't waste it living someone else's life.",
    "Education is the passport to the future, for tomorrow belongs to those who prepare for it today.",
    "The expert in anything was once a beginner.",
    "It always seems impossible until it's done.",
  ];
  int _currentQuoteIndex = 0;
  Timer? _quoteTimer; // Timer to change quotes

  // --- Constants ---
  static const Color brandColor = Color(0xFF0175C2);

  @override
  void initState() {
    super.initState();

    // --- Initialize Background Animation ---
    _backgroundController = AnimationController(
      // Slightly faster fade for background
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );
    _backgroundFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _backgroundController, curve: Curves.easeInOut), // Smoother curve
    );
    _backgroundController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Slightly longer pause showing the fully faded-in image
        Future.delayed(const Duration(seconds: 4), () { // Total cycle ~5.5s
          if (mounted) {
            setState(() {
              _currentBackgroundIndex = (_currentBackgroundIndex + 1) % _backgroundImages.length;
              _backgroundController.forward(from: 0.0); // Start next fade-in
            });
          }
        });
      }
    });
    // Start the first background fade-in
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _backgroundController.forward();
      }
    });

    // --- Initialize Quote Animation ---
    // Select initial random quote
    _currentQuoteIndex = Random().nextInt(_quotes.length);

    // Start timer to change quotes periodically
    _quoteTimer = Timer.periodic(const Duration(seconds: 7), (timer) { // Change quote every 7 seconds
      if (mounted) {
        setState(() {
          // Select a new random index, ensuring it's different from the current one if possible
          int nextIndex;
          if (_quotes.length > 1) {
            do {
              nextIndex = Random().nextInt(_quotes.length);
            } while (nextIndex == _currentQuoteIndex);
            _currentQuoteIndex = nextIndex;
          } else {
             _currentQuoteIndex = 0; // Handle case with only one quote
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _backgroundController.dispose();
    _quoteTimer?.cancel(); // Cancel the quote timer
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    int nextBackgroundIndex = (_currentBackgroundIndex + 1) % _backgroundImages.length;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // --- Background Image Layer ---
          Image.asset(
            _backgroundImages[_currentBackgroundIndex],
            fit: BoxFit.cover,
            key: ValueKey<int>(_currentBackgroundIndex),
            gaplessPlayback: true,
          ),
          FadeTransition(
            opacity: _backgroundFadeAnimation,
            child: Image.asset(
              _backgroundImages[nextBackgroundIndex],
              fit: BoxFit.cover,
              key: ValueKey<int>(nextBackgroundIndex),
              gaplessPlayback: true,
            ),
          ),

          // --- Darkening Overlay ---
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.1),
                  Colors.black.withOpacity(0.4),
                  Colors.black.withOpacity(0.7),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.4, 1.0],
              ),
            ),
          ),

          // --- Content Layer ---
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 50.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // --- Top Section (Logo, Title, Subtitle, Quote) ---
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const SizedBox(height: 20),
                      Image.asset(
                        'assets/images/image.png',
                        height: 80,
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'CheckMate',
                        textAlign: TextAlign.center,
                        style: textTheme.displaySmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          shadows: [ Shadow( blurRadius: 8.0, color: Colors.black.withOpacity(0.6), offset: const Offset(1.0, 1.0), ), ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Effortless Attendance Tracking',
                        textAlign: TextAlign.center,
                        style: textTheme.titleMedium?.copyWith(
                          color: Colors.white.withOpacity(0.9),
                           shadows: [ Shadow( blurRadius: 4.0, color: Colors.black.withOpacity(0.5), offset: const Offset(0.5, 0.5), ), ],
                        ),
                      ),
                      const SizedBox(height: 30), // Space before quote

                      // --- Animated Quote ---
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 1200), // Duration of the fade
                        transitionBuilder: (Widget child, Animation<double> animation) {
                          // Use FadeTransition for smooth fade in/out
                          return FadeTransition(opacity: animation, child: child);
                        },
                        child: Padding(
                          // Ensure padding is applied to the Text, not the Switcher
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: Text(
                            _quotes[_currentQuoteIndex],
                            // Key is crucial for AnimatedSwitcher to detect change
                            key: ValueKey<int>(_currentQuoteIndex),
                            textAlign: TextAlign.center,
                            style: textTheme.titleMedium?.copyWith(
                              color: Colors.white.withOpacity(0.95),
                              fontStyle: FontStyle.italic,
                              shadows: [ Shadow( blurRadius: 5.0, color: Colors.black.withOpacity(0.7), offset: const Offset(0.5, 0.5), ), ],
                            ),
                          ),
                        ),
                      ),
                      // --- End Animated Quote ---
                    ],
                  ),

                  // --- Bottom Section  ---
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          backgroundColor: brandColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(30), ),
                          elevation: 5,
                          textStyle: textTheme.titleMedium?.copyWith( fontWeight: FontWeight.bold, ),
                        ),
                        onPressed: () {
                          Navigator.push( context, MaterialPageRoute(builder: (context) => const LoginScreen()), );
                        },
                        child: const Text('Login'),
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                         style: OutlinedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52),
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white, width: 1.5),
                           shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(30), ),
                           textStyle: textTheme.titleMedium?.copyWith( fontWeight: FontWeight.bold, ),
                        ),
                        onPressed: () {
                          Navigator.push( context, MaterialPageRoute(builder: (context) => const RegisterScreen()), );
                        },
                        child: const Text('Register'),
                      ),
                       const SizedBox(height: 10),
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
