// lib/screens/login_screen.dart
import 'package:checkmate/screens/register_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:checkmate/models/app_user.dart' as app_user;
// Import dashboards directly (Wrapper handles the main navigation, but direct import is fine here)
import 'package:checkmate/screens/student_dashboard.dart';
import 'package:checkmate/screens/lecturer_dashboard.dart';
import 'package:provider/provider.dart'; // Import Provider

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controllers for text fields
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  // State variables
  bool _isLoading = false;
  bool _obscurePassword = true;
  final _formKey = GlobalKey<FormState>(); // Key for form validation

  // Define the brand color (consistent styling)
  static const Color brandColor = Color(0xFF0175C2);

  @override
  void dispose() {
    // Dispose controllers when the widget is removed from the tree
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // Helper function to show snackbar messages
  void _showSnackBar(String message, {bool isError = true}) {
    // Check if the widget is still mounted before showing snackbar
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green, // Use theme colors
        behavior: SnackBarBehavior.floating, // Make it float
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), // Rounded corners
        margin: const EdgeInsets.all(10), // Add margin
      ),
    );
  }


  // --- Login Action ---
  Future<void> _handleLogin() async {
    // 1. Validate the form fields
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please fix the errors in the form.', isError: true);
      return; // Don't proceed if form is invalid
    }

    // Access AuthService using Provider
    final authService = Provider.of<AuthService>(context, listen: false);

    // Check mount status before async operation
    if (!mounted) return;
    setState(() { _isLoading = true; }); // Show loading indicator

    try {
      // 2. Call the login method in AuthService
      // --- CORRECTION: Removed the 'skipEmailVerification' parameter ---
      app_user.User? user = await authService.login(
        _emailController.text.trim(), // Trim whitespace from email
        _passwordController.text,     // Password (no trim needed)
        // No skipEmailVerification parameter needed here anymore
      );
      // --- END CORRECTION ---

      // 3. Check mount status AGAIN after the async login call completes
      if (!mounted) return;

      // 4. Handle successful login
      if (user != null) {
        // Navigate to the appropriate dashboard based on the user's role
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => user.role == 'lecturer'
                ? LecturerDashboard(currentUser: user)
                : StudentDashboard(currentUser: user),
          ),
        );
        return; // Exit function after successful navigation
      } else {
         // Less likely case, but handle if user data fetch fails silently
         _showSnackBar('Login failed: Could not retrieve user details.');
      }

    } on AuthException catch (e) {
      // 5. Handle specific authentication errors
      if (mounted) {
        // Show user-friendly error message from AuthService
        // If email not verified, the message will prompt user to check email/resend
        _showSnackBar(e.message, isError: true);
      }
    } catch (e) {
       // 6. Handle unexpected errors
       if (mounted) {
         print("Unexpected login error: $e");
         _showSnackBar('An unexpected error occurred. Please try again.', isError: true);
       }
    } finally {
      // 7. Ensure loading indicator is turned off if the widget is still mounted
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  // --- Resend Verification Email Action ---
  Future<void> _handleResendVerification() async {
     final authService = Provider.of<AuthService>(context, listen: false);

     // The service method now uses the currently authenticated user (if any)

     if (!mounted) return;
     setState(() { _isLoading = true; }); // Show loading briefly

     try {
       // Call without email parameter
       await authService.resendVerificationEmail();

       if (!mounted) return;
       // Show generic success message, AuthService handles specific cases like already verified
       _showSnackBar('Verification email resent successfully. Please check your inbox (and spam folder).', isError: false);
     } on AuthException catch (e) {
       // Handle errors from AuthService (e.g., "already verified", "no user session", "too many requests")
       if (!mounted) return;
       _showSnackBar(e.message, isError: true);
     } catch (e) {
       // Handle unexpected errors
       if (!mounted) return;
       print("Unexpected resend error: $e");
       _showSnackBar('An unexpected error occurred while resending email.', isError: true);
     } finally {
       if (mounted) {
         setState(() { _isLoading = false; });
       }
     }
  }

  // --- Forgot Password Action ---
  Future<void> _handleForgotPassword() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final email = _emailController.text.trim();

    // Validate if email field has something that looks like an email
    if (email.isEmpty || !email.contains('@')) {
      _showSnackBar('Please enter your email address first to reset password.', isError: true);
      return;
    }

    if (!mounted) return;
    // Optional: Show a confirmation dialog before sending
    bool confirmSend = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text('Send a password reset link to $email?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false), // Cancel
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true), // Confirm
            child: const Text('Send'),
            style: TextButton.styleFrom(foregroundColor: brandColor),
          ),
        ],
      ),
    ) ?? false; // Default to false if dialog dismissed

    if (!confirmSend || !mounted) return; // Exit if user cancelled or widget unmounted

    setState(() { _isLoading = true; }); // Show loading

    try {
      await authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      _showSnackBar('Password reset email sent to $email. Please check your inbox.', isError: false);
    } on AuthException catch (e) {
      if (!mounted) return;
      _showSnackBar(e.message, isError: true);
    } catch (e) {
      if (!mounted) return;
      print("Unexpected password reset error: $e");
      _showSnackBar('An unexpected error occurred.', isError: true);
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
      appBar: AppBar(
        title: const Text('Login to CheckMate'),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false, // Don't show back button
        elevation: 2.0,
      ),
      body: Center( // Center the content vertically
        child: SingleChildScrollView( // Allow scrolling
          child: Padding(
            padding: const EdgeInsets.all(24.0), // Consistent padding
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Logo
                  Container(
                    margin: const EdgeInsets.only(bottom: 40),
                    child: Image.asset(
                      'assets/images/image.png', // Verify this path
                      height: 100,
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) {
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
                      prefixIcon: Icon(Icons.email_outlined, color: brandColor.withOpacity(0.7)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
                    ),
                    keyboardType: TextInputType.emailAddress,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) return 'Please enter your email';
                      if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(value.trim())) return 'Please enter a valid email';
                      return null;
                    },
                    textInputAction: TextInputAction.next, // Move to password field
                  ),
                  const SizedBox(height: 20),
                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      hintText: 'Enter your password',
                      prefixIcon: Icon(Icons.lock_outline, color: brandColor.withOpacity(0.7)),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey[100],
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
                    textInputAction: TextInputAction.done, // Submit form from password field
                    onFieldSubmitted: (_) => _isLoading ? null : _handleLogin(), // Allow login on keyboard done action
                  ),
                  const SizedBox(height: 35),
                  // Login Button
                  _isLoading
                      ? const Center(child: CircularProgressIndicator(color: brandColor)) // Use brand color
                      : ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 52),
                            backgroundColor: brandColor,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 3,
                            textStyle: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          onPressed: _handleLogin, // Call the handler method
                          child: const Text('Login'),
                        ),
                  const SizedBox(height: 20),
                  // Register, Resend, Forgot Password Buttons
                  Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: _isLoading ? null : () {
                              // Navigate to RegisterScreen
                              Navigator.push(
                                context,
                                MaterialPageRoute(builder: (context) => const RegisterScreen()),
                              );
                            },
                            style: TextButton.styleFrom(foregroundColor: brandColor),
                            child: const Text("Register here"),
                          ),
                           TextButton(
                            // Use the corrected handler
                            onPressed: _isLoading ? null : _handleResendVerification,
                            style: TextButton.styleFrom(foregroundColor: colorScheme.secondary), // Or brandColor
                            child: const Text('Resend Email'),
                          ),
                        ],
                      ),
                      // Forgot Password Button
                      TextButton(
                        onPressed: _isLoading ? null : _handleForgotPassword,
                        style: TextButton.styleFrom(foregroundColor: Colors.grey[600]), // Subtle color
                        child: const Text('Forgot Password?'),
                      ),
                    ],
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
