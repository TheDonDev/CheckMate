// lib/screens/login_screen.dart
import 'dart:async'; // For Timer (used by background animation)
// For Random (if needed, though not directly used here)

import 'package:checkmate/screens/register_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:checkmate/models/app_user.dart' as app_user;
// Import dashboards directly
import 'package:checkmate/screens/student_dashboard.dart';
import 'package:checkmate/screens/lecturer_dashboard.dart'; // This was missing
import 'package:checkmate/screens/admin_dashboard.dart';
import 'package:provider/provider.dart'; // Import Provider
import 'package:url_launcher/url_launcher.dart'; // Import url_launcher

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

// Add SingleTickerProviderStateMixin for the AnimationController
class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  // --- Controllers for text fields ---
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // --- State variables for Login ---
  bool _isLoading = false;
  bool _obscurePassword = true;
  final _formKey = GlobalKey<FormState>(); // Key for form validation

  // --- Background Animation State ---
  late AnimationController _backgroundController;
  late Animation<double> _backgroundFadeAnimation;
  // *** UPDATED Image List ***
  final List<String> _backgroundImages = [
    'assets/images/Alupe-.jpeg',
    'assets/images/nai3.jpg',
    'assets/images/MV3.jpg',
    'assets/images/WorkStationDay.jpg',
    'assets/images/WorkStationNight.jpg',
    'assets/images/WorkStationLine2.jpg',
  ];
  int _currentBackgroundIndex = 0;
  // --- End Background Animation State ---

  // --- Constants ---
  static const Color brandColor = Color(0xFF0175C2);
  final String _supportEmail = 'donaldmwanga33@gmail.com';
  final String _supportSubject = 'Checkmate App Support Request';
  // --- End Constants ---

  @override
  void initState() {
    super.initState();

    // --- Initialize Background Animation ---
    _backgroundController = AnimationController(
      duration: const Duration(milliseconds: 1500), // Fade duration
      vsync: this,
    );
    _backgroundFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _backgroundController, curve: Curves.easeInOut),
    );
    _backgroundController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        // Pause showing the fully faded-in image
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) {
            setState(() {
              _currentBackgroundIndex = (_currentBackgroundIndex + 1) % _backgroundImages.length;
              _backgroundController.forward(from: 0.0); // Start next fade-in
            });
          }
        });
      }
    });
    // Start the first background fade-in after a short delay
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        _backgroundController.forward();
      }
    });
    // --- End Background Animation Init ---
  }


  @override
  void dispose() {
    // Dispose controllers when the widget is removed from the tree
    _emailController.dispose();
    _passwordController.dispose();
    _backgroundController.dispose(); // Dispose background controller
    super.dispose();
  }

  // Helper function to show a user-friendly error dialog
  void _showErrorDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Row(children: [ Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error), const SizedBox(width: 10), Text(title), ]),
            content: Text(content),
            actions: <Widget>[ TextButton(child: const Text('OK'), onPressed: () => Navigator.of(dialogContext).pop()), ],
          );
        });
  }

  // --- Login Action --- 
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorDialog('Validation Error', 'Please fix the errors in the form.');
      return;
    }
    final authService = Provider.of<AuthService>(context, listen: false);
    if (!mounted) return;
    setState(() { _isLoading = true; });

    try {
      app_user.User? user = await authService.login(
        _emailController.text.trim(),
        _passwordController.text,
      );
      if (!mounted) return;
      if (user != null) {
        switch (user.role) {
          case 'admin':
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => AdminDashboard(currentUser: user)),
            );
            break;
          case 'lecturer':
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => LecturerDashboard(currentUser: user)),
            );
            break;
          case 'student':
          default: // Default to student dashboard
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (context) => StudentDashboard(currentUser: user)),
            );
            break;
        }
        return;
      } else {
         _showErrorDialog('Login Failed', 'Could not retrieve user details after authentication. Please try again.');
      }
    } on AuthException catch (e) {
      if (mounted) { _showErrorDialog('Login Failed', e.message); }
    } catch (e) {
       if (mounted) {
         print("Unexpected login error: $e");
         _showErrorDialog('Login Failed', 'An unexpected error occurred. Please try again.');
       }
    } finally {
      if (mounted) { setState(() { _isLoading = false; }); }
    }
  }

  // --- Resend Verification Email Action --- 
  Future<void> _handleResendVerification() async {
     final authService = Provider.of<AuthService>(context, listen: false);
     if (!mounted) return;
     setState(() { _isLoading = true; });

     try {
       await authService.resendVerificationEmail();
       if (!mounted) return; // Show success dialog or snackbar
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Verification email resent successfully. Please check your inbox (and spam folder).'), backgroundColor: Colors.green));
     } on AuthException catch (e) {
       if (!mounted) return;
       _showErrorDialog('Action Failed', e.message);
     } catch (e) {
       if (!mounted) return;
       print("Unexpected resend error: ");
       _showErrorDialog('Action Failed', 'An unexpected error occurred while resending the email.');
     } finally {
       if (mounted) { setState(() { _isLoading = false; }); }
     }
  }

  // --- Forgot Password Action --- 
  Future<void> _handleForgotPassword() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _showErrorDialog('Invalid Input', 'Please enter your email address in the field above before attempting to reset your password.');
      return;
    }
    if (!mounted) return;
    bool confirmSend = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text('Send a password reset link to ?'),
        actions: [
          TextButton( onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel'), ),
          TextButton( onPressed: () => Navigator.of(context).pop(true), child: const Text('Send'), style: TextButton.styleFrom(foregroundColor: brandColor), ),
        ],
      ),
    ) ?? false;

    if (!confirmSend || !mounted) return;
    setState(() { _isLoading = true; });

    try {
      await authService.sendPasswordResetEmail(email);
      if (!mounted) return; // Show success dialog or snackbar
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Password reset email sent to $email. Please check your inbox.'), backgroundColor: Colors.green));
    } on AuthException catch (e) {
      if (!mounted) return;
      _showErrorDialog('Action Failed', e.message);
    } catch (e) {
      if (!mounted) return;
      print("Unexpected password reset error: ");
      _showErrorDialog('Action Failed', 'An unexpected error occurred.');
    } finally {
      if (mounted) { setState(() { _isLoading = false; }); }
    }
  }

  // --- Contact Support Action --- 
  Future<void> _contactSupport() async {
    final enteredEmail = _emailController.text.trim();
    final String emailBody = '''
Please describe the issue you are experiencing below:

------------------------------------
App Version: [App Version, e.g., 1.0.0] (Optional)
Device: [Device Model, e.g., Samsung S21] (Optional)
Operating System: [OS Version, e.g., Android 13] (Optional)
Email used (if different): ${enteredEmail.isNotEmpty ? enteredEmail : '[Please enter email used for login/register]'}
------------------------------------

''';
    final Uri mailtoUri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: { 'subject': _supportSubject, 'body': emailBody, },
    );
    try {
      if (await canLaunchUrl(mailtoUri)) { await launchUrl(mailtoUri); }
      else { _showErrorDialog('Action Failed', 'Could not open your email app. Please contact $_supportEmail manually.'); }
    } catch (e) {
      print("Error launching mailto link: ");
      _showErrorDialog('Action Failed', 'Could not open your email app. Please contact $_supportEmail manually.');
    }
  }


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    
    // Calculate next background index for the FadeTransition
    int nextBackgroundIndex = (_currentBackgroundIndex + 1) % _backgroundImages.length;

    return Scaffold(
      // Removed AppBar here, will be part of the content stack if needed
      // appBar: AppBar(...)
      body: Stack( // Use Stack to layer background and content
        fit: StackFit.expand,
        children: [
          // --- Background Image Layer ---
          Image.asset(
            _backgroundImages[_currentBackgroundIndex],
            fit: BoxFit.cover,
            key: ValueKey<int>(_currentBackgroundIndex), // Key for transition
            gaplessPlayback: true, // Smoother transition
          ),
          FadeTransition(
            opacity: _backgroundFadeAnimation,
            child: Image.asset(
              _backgroundImages[nextBackgroundIndex],
              fit: BoxFit.cover,
              key: ValueKey<int>(nextBackgroundIndex), // Key for transition
              gaplessPlayback: true,
            ),
          ),

          // --- Darkening Overlay for Text Contrast ---
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.black.withOpacity(0.1), // Less dark at the top
                  Colors.black.withOpacity(0.5), // Adjusted opacity
                  Colors.black.withOpacity(0.75), // Darker towards the bottom
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.5, 1.0], // Adjust gradient points
              ),
            ),
          ),

          // --- Content Layer (Form, Buttons, etc.) ---
          SafeArea( // Keep form content within safe areas
            child: Center( // Center the content vertically
              child: SingleChildScrollView( // Allow scrolling
                child: Padding(
                  padding: const EdgeInsets.all(24.0), // Consistent padding
                  child: Form(
                    key: _formKey,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Logo (Optional: Consider if needed with AppBar gone)
                        Container(
                          margin: const EdgeInsets.only(bottom: 40),
                          child: Image.asset(
                            'assets/images/image.png', // Verify this path
                            height: 100,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                               return const SizedBox(height: 100, child: Center(child: Text('CheckMate Logo', style: TextStyle(fontSize: 16, color: Colors.white70)))); // White text on overlay
                            },
                          ),
                        ),
                         // Added Title Text
                        Text(
                          'Login to CheckMate',
                          textAlign: TextAlign.center,
                          style: textTheme.headlineMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            shadows: [ Shadow( blurRadius: 6.0, color: Colors.black.withOpacity(0.5), offset: const Offset(1.0, 1.0), ), ],
                          ),
                        ),
                        const SizedBox(height: 30), // Space after title

                        // Email Field
                        TextFormField(
                          controller: _emailController,
                          style: const TextStyle(color: Colors.black87), // Ensure text is visible on light background
                          decoration: InputDecoration(
                            labelText: 'Email Address',
                            labelStyle: TextStyle(color: Colors.grey[700]),
                            hintText: 'Enter your university email',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            prefixIcon: Icon(Icons.email_outlined, color: brandColor.withOpacity(0.7)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                            enabledBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade400), ),
                            focusedBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: brandColor, width: 1.5), ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.9), // Slightly transparent white
                          ),
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) return 'Please enter your email';
                            if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9.-]+\.[a-zA-Z]+").hasMatch(value.trim())) return 'Please enter a valid email';
                            return null;
                          },
                          textInputAction: TextInputAction.next,
                        ),
                        const SizedBox(height: 20),
                        // Password Field
                        TextFormField(
                          controller: _passwordController,
                          style: const TextStyle(color: Colors.black87),
                          decoration: InputDecoration(
                            labelText: 'Password',
                            labelStyle: TextStyle(color: Colors.grey[700]),
                            hintText: 'Enter your password',
                            hintStyle: TextStyle(color: Colors.grey[500]),
                            prefixIcon: Icon(Icons.lock_outline, color: brandColor.withOpacity(0.7)),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                             enabledBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade400), ),
                            focusedBorder: OutlineInputBorder( borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: brandColor, width: 1.5), ),
                            filled: true,
                            fillColor: Colors.white.withOpacity(0.9),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                                color: Colors.grey[600],
                              ),
                              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                            ),
                          ),
                          obscureText: _obscurePassword,
                          validator: (value) {
                             if (value == null || value.isEmpty) return 'Please enter your password';
                             return null;
                          },
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _isLoading ? null : _handleLogin(),
                        ),
                        const SizedBox(height: 35),
                        // Login Button
                        _isLoading
                            ? const Center(child: CircularProgressIndicator(color: brandColor))
                            : ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  minimumSize: const Size(double.infinity, 52),
                                  backgroundColor: brandColor,
                                  foregroundColor: Colors.white,
                                  shape: RoundedRectangleBorder( borderRadius: BorderRadius.circular(30), ),
                                  elevation: 5, // Increased elevation
                                  textStyle: textTheme.titleMedium?.copyWith( fontWeight: FontWeight.bold, ),
                                ),
                                onPressed: _handleLogin,
                                child: const Text('Login'),
                              ),
                        const SizedBox(height: 20),
                        // Register, Resend, Forgot Password, Contact Support Buttons
                        Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                TextButton(
                                  onPressed: _isLoading ? null : () {
                                    Navigator.push( context, MaterialPageRoute(builder: (context) => const RegisterScreen()), );
                                  },
                                  style: TextButton.styleFrom(foregroundColor: Colors.white), // White text
                                  child: const Text("Register here"),
                                ),
                                 TextButton(
                                  onPressed: _isLoading ? null : _handleResendVerification,
                                  style: TextButton.styleFrom(foregroundColor: Colors.lightBlue[100]), // Lighter blue/white
                                  child: const Text('Resend Email'),
                                ),
                              ],
                            ),
                            TextButton(
                              onPressed: _isLoading ? null : _handleForgotPassword,
                              style: TextButton.styleFrom(foregroundColor: Colors.white70), // White text
                              child: const Text('Forgot Password?'),
                            ),
                            const SizedBox(height: 10),
                            TextButton.icon(
                              icon: Icon(Icons.support_agent_outlined, size: 18, color: Colors.white70), // White icon
                              label: Text('Contact Support', style: TextStyle(color: Colors.white70)), // White text
                              onPressed: _isLoading ? null : _contactSupport,
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ), // End SafeArea
        ], // End Stack children
      ), // End Stack
    ); // End Scaffold
  }
}
