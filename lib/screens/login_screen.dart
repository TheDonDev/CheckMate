// lib/screens/login_screen.dart
import 'package:checkmate/screens/register_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:checkmate/models/app_user.dart' as app_user;
// Import dashboards directly (Wrapper handles the main navigation, but direct import is fine here)
import 'package:checkmate/screens/student_dashboard.dart';
import 'package:checkmate/screens/lecturer_dashboard.dart';
import 'package:checkmate/widgets/custom_button.dart'; // Assuming this exists and works
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
        backgroundColor: isError ? Colors.redAccent : Colors.green,
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
        automaticallyImplyLeading: false, // Don't show back button if pushed via Wrapper
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Center( // Center the column vertically
            child: SingleChildScrollView( // Allow scrolling on smaller screens
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Logo
                  Container(
                    margin: const EdgeInsets.only(bottom: 30),
                    // Make sure the path is correct and the asset is listed in pubspec.yaml
                    child: Image.asset(
                      'assets/images/image.png', // Verify this path
                      height: 150,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
                         // Show placeholder or text if image fails to load
                         return const SizedBox(height: 150, child: Center(child: Text('CheckMate Logo', style: TextStyle(fontSize: 18, color: Colors.grey))));
                      },
                    ),
                  ),
                  // Email Field
                  TextFormField(
                    controller: _emailController,
                    decoration: const InputDecoration(
                      labelText: 'Email',
                      prefixIcon: Icon(Icons.email_outlined), // Add icon
                      // border: OutlineInputBorder(), // Provided by theme
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
                      prefixIcon: const Icon(Icons.lock_outline), // Add icon
                      // border: const OutlineInputBorder(), // Provided by theme
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility), // Toggle icon correctly
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
                  const SizedBox(height: 30), // Increased spacing
                  // Login Button
                  _isLoading
                      ? const CircularProgressIndicator()
                      : CustomButton( // Assuming CustomButton exists
                          onPressed: _handleLogin, // Call the handler method
                          text: 'Login',
                          // Optional: Style the button if CustomButton doesn't handle it
                          // style: ElevatedButton.styleFrom(minimumSize: Size(double.infinity, 50)),
                        ),
                  const SizedBox(height: 20),
                  // Register Button
                  TextButton(
                    onPressed: _isLoading ? null : () { // Disable while loading
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const RegisterScreen()),
                      );
                    },
                    child: const Text("Don't have an account? Register here"),
                  ),
                  const SizedBox(height: 10),
                  // Resend Verification Button
                  TextButton(
                    onPressed: _isLoading ? null : _handleResendVerification, // Disable while loading
                    child: const Text('Resend Verification Email'),
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
