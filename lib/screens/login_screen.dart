// lib/screens/login_screen.dart
import 'package:checkmate/screens/register_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:checkmate/models/app_user.dart' as app_user;
// Import dashboards directly (Wrapper handles the main navigation, but direct import is fine here)
import 'package:checkmate/screens/student_dashboard.dart';
import 'package:checkmate/screens/lecturer_dashboard.dart';
// Assuming CustomButton exists and can be styled or replaced with ElevatedButton
// import 'package:checkmate/widgets/custom_button.dart';
import 'package:provider/provider.dart'; // Import Provider

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Access AuthService via Provider - no need to instantiate here
  // final AuthService _authService = AuthService();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  final _formKey = GlobalKey<FormState>();

  // Define the brand color (consistent with WelcomeScreen)
  static const Color brandColor = Color(0xFF0175C2);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Helper to show snackbar messages
  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green, // Use theme error color
        behavior: SnackBarBehavior.floating, // Optional: makes it float above bottom nav bar if any
      ),
    );
  }


  // Login Action
  Future<void> _handleLogin() async {
    // Validate the form
    if (!_formKey.currentState!.validate()) {
      return; // Don't proceed if form is invalid
    }

    // Access AuthService from Provider
    final authService = Provider.of<AuthService>(context, listen: false);

    if (!mounted) return; // Check mount status before async gap
    setState(() { _isLoading = true; });

    try {
      // Call the NEW login method in AuthService
      // *** IMPORTANT: Consider removing skipEmailVerification: true for production ***
      app_user.User? user = await authService.login(
        _emailController.text.trim(), // Trim whitespace
        _passwordController.text,
        skipEmailVerification: true, // Set to false or remove for production
      );

      // Check if login was successful and user data was retrieved
      // Check mount status AGAIN after async gap
      if (!mounted) return;

      if (user != null) {
        // Navigate to the appropriate dashboard based on role
        // Using pushReplacement prevents going back to the login screen
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => user.role == 'lecturer'
                ? LecturerDashboard(currentUser: user)
                : StudentDashboard(currentUser: user),
          ),
        );
        // No need to set isLoading = false here as the screen is replaced
        return; // Exit function after successful navigation
      } else {
         // Handle case where login succeeded but user data fetch failed (user == null)
         // This case is less likely with the improved login logic in AuthService HEAD
         _showSnackBar('Login failed: Could not retrieve user details.');
      }

    } on AuthException catch (e) {
      // Handle specific authentication errors thrown by AuthService
      if (mounted) {
        _showSnackBar(e.message); // Show user-friendly error message
      }
    } catch (e) {
       // Handle unexpected errors
       if (mounted) {
         print("Unexpected login error: $e");
         _showSnackBar('An unexpected error occurred. Please try again.');
       }
    } finally {
      // Ensure loading indicator is turned off if the widget is still mounted
      // and navigation didn't happen
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  // Resend Verification Email Action
  Future<void> _handleResendVerification() async {
     final authService = Provider.of<AuthService>(context, listen: false);
     // Optional: Check if email field is filled to resend to that specific email?
     // Currently resends to the *currently signed-in* user if any (which is unlikely on login screen)
     // Better UX might be to prompt for email if not logged in.
     // For simplicity now, we assume it tries based on potential cached user or fails gracefully.

     if (!mounted) return;
     setState(() { _isLoading = true; }); // Show loading briefly
     try {
       // Consider prompting for email if _emailController is not empty?
       // Or modify authService.resendVerificationEmail to accept an email?
       await authService.resendVerificationEmail();
       if (!mounted) return;
       _showSnackBar('Verification email resent successfully. Please check your inbox (and spam folder).', isError: false);
     } on AuthException catch (e) {
       if (!mounted) return;
       _showSnackBar(e.message);
     } catch (e) {
       if (!mounted) return;
       print("Unexpected resend error: $e");
       _showSnackBar('An unexpected error occurred.');
     } finally {
       if (mounted) {
         setState(() { _isLoading = false; });
       }
     }
  }


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      // Use AppBar theme defined in main.dart if available
      // Otherwise, style explicitly
      appBar: AppBar(
        title: const Text('Login to CheckMate'),
        backgroundColor: brandColor, // Apply brand color
        foregroundColor: Colors.white, // Ensure text/icons are white
        automaticallyImplyLeading: false, // Don't show back button if pushed via WelcomeScreen
        elevation: 2.0, // Subtle elevation
      ),
      body: Center( // Center the content vertically
        child: SingleChildScrollView( // Allow scrolling on smaller screens
          child: Padding(
            padding: const EdgeInsets.all(24.0), // Consistent padding
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch, // Make children stretch horizontally
                children: [
                  // Logo
                  Container(
                    margin: const EdgeInsets.only(bottom: 40), // Increased spacing below logo
                    child: Image.asset(
                      'assets/images/image.png', // Verify this path
                      height: 100, // Adjusted size
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                         // Show placeholder or text if image fails to load
                         return const SizedBox(height: 100, child: Center(child: Text('CheckMate Logo', style: TextStyle(fontSize: 16, color: Colors.grey))));
                      },
                    ),
                  ),
                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: 'Email Address',
                      hintText: 'Enter your university email',
                      prefixIcon: Icon(Icons.email_outlined, color: brandColor.withOpacity(0.7)), // Themed icon color
                      border: OutlineInputBorder( // Consistent border style
                        borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true, // Add subtle background fill
                      fillColor: Colors.grey[100],
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.isEmpty) return 'Please enter your email';
                      // Basic email format check
                      if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(value)) return 'Please enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 20),
                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter your password',
                      prefixIcon: Icon(Icons.lock_outline, color: brandColor.withOpacity(0.7)), // Themed icon color
                      border: OutlineInputBorder( // Consistent border style
                         borderRadius: BorderRadius.circular(12),
                      ),
                      filled: true,
                      fillColor: Colors.grey[100],
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                          color: Colors.grey[600], // Subtle color for visibility icon
                        ),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    validator: (value) {
                       if (value == null || value.isEmpty) return 'Please enter your password';
                       // Add length check if desired (e.g., value.length < 6)
                       return null;
                    },
                  ),
                  const SizedBox(height: 35), // Increased spacing before button
                  // Login Button
                  _isLoading
                      ? const Center(child: CircularProgressIndicator()) // Center the indicator
                      : ElevatedButton( // Using ElevatedButton directly for clear styling
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52), // Full width, standard height
                            backgroundColor: brandColor, // Use the defined brand color
                            foregroundColor: Colors.white, // White text for contrast
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30), // Match WelcomeScreen
                            ),
                            elevation: 3, // Subtle elevation
                            textStyle: textTheme.titleMedium?.copyWith( // Consistent text style
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: _handleLogin, // Call the handler method
                          child: const Text('Login'),
                        ),
                  const SizedBox(height: 20), // Spacing after primary button
                  // Register & Resend Buttons (Grouped)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _isLoading ? null : () { // Disable while loading
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const RegisterScreen()),
                          );
                        },
                        style: TextButton.styleFrom(foregroundColor: brandColor), // Use brand color for text
                        child: const Text("Register here"),
                      ),
                       TextButton(
                        onPressed: _isLoading ? null : _handleResendVerification, // Disable while loading
                        style: TextButton.styleFrom(foregroundColor: colorScheme.secondary), // Use theme secondary color or brandColor
                        child: const Text('Resend Email'),
                      ),
                    ],
                  ),
                  // Optional: Add a "Forgot Password?" button if needed
                  TextButton(
                  onPressed: _isLoading ? null : () { /* TODO: Implement Forgot Password */ },
                  child: const Text('Forgot Password?'),
                ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
