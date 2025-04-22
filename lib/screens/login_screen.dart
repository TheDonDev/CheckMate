// lib/screens/login_screen.dart
import 'package:checkmate/screens/register_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:checkmate/models/app_user.dart' as app_user;
// Import dashboards directly
import 'package:checkmate/screens/student_dashboard.dart';
import 'package:checkmate/screens/lecturer_dashboard.dart';
import 'package:provider/provider.dart'; // Import Provider
import 'package:url_launcher/url_launcher.dart'; // Import url_launcher

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

  // --- Support Contact Details ---
  // TODO: Replace with actual support email address
  final String _supportEmail = 'donaldmwanga33@gmail.com';
  final String _supportSubject = 'Checkmate App Support Request';
  // --- End Support Contact Details ---

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
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please fix the errors in the form.', isError: true);
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
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => user.role == 'lecturer'
                ? LecturerDashboard(currentUser: user)
                : StudentDashboard(currentUser: user),
          ),
        );
        return;
      } else {
         _showSnackBar('Login failed: Could not retrieve user details.');
      }
    } on AuthException catch (e) {
      if (mounted) { _showSnackBar(e.message, isError: true); }
    } catch (e) {
       if (mounted) {
         print("Unexpected login error: $e");
         _showSnackBar('An unexpected error occurred. Please try again.', isError: true);
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
       if (!mounted) return;
       _showSnackBar('Verification email resent successfully. Please check your inbox (and spam folder).', isError: false);
     } on AuthException catch (e) {
       if (!mounted) return;
       _showSnackBar(e.message, isError: true);
     } catch (e) {
       if (!mounted) return;
       print("Unexpected resend error: $e");
       _showSnackBar('An unexpected error occurred while resending email.', isError: true);
     } finally {
       if (mounted) { setState(() { _isLoading = false; }); }
     }
  }

  // --- Forgot Password Action ---
  Future<void> _handleForgotPassword() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final email = _emailController.text.trim();

    if (email.isEmpty || !email.contains('@')) {
      _showSnackBar('Please enter your email address first to reset password.', isError: true);
      return;
    }
    if (!mounted) return;
    bool confirmSend = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset Password'),
        content: Text('Send a password reset link to $email?'),
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
      if (mounted) { setState(() { _isLoading = false; }); }
    }
  }

  // --- *** NEW: Contact Support Action *** ---
  Future<void> _contactSupport() async {
    // Try to pre-fill the user's entered email if available
    final enteredEmail = _emailController.text.trim();
    final String emailBody = '''
Please describe the issue you are experiencing below:

------------------------------------
App Version: [App Version, e.g., 1.0.0] (Optional)
Device: [Device Model, e.g., Samsung S21] (Optional)
Operating System: [OS Version, e.g., Android 13] (Optional)
Email used (if different): ${enteredEmail.isNotEmpty ? enteredEmail : '[Please enter email used for login/register]'}
------------------------------------

'''; // Use triple quotes for multi-line string

    // Encode subject and body for the mailto link
    final Uri mailtoUri = Uri(
      scheme: 'mailto',
      path: _supportEmail,
      queryParameters: {
        'subject': _supportSubject,
        'body': emailBody,
      },
    );

    try {
      // Check if the URL can be launched
      if (await canLaunchUrl(mailtoUri)) {
        await launchUrl(mailtoUri);
      } else {
        // If mailto fails, show the email address so the user can copy it
        _showSnackBar('Could not open email app. Please contact $_supportEmail', isError: true);
      }
    } catch (e) {
      print("Error launching mailto link: $e");
      _showSnackBar('Could not open email app. Please contact $_supportEmail', isError: true);
    }
  }
  // --- *** END: Contact Support Action *** ---


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
                            style: TextButton.styleFrom(foregroundColor: brandColor),
                            child: const Text("Register here"),
                          ),
                           TextButton(
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
                      const SizedBox(height: 10), // Adds some space before support
                      // --- *** NEW: Contact Support Button *** ---
                      TextButton.icon(
                        icon: Icon(Icons.support_agent_outlined, size: 18, color: Colors.grey[700]),
                        label: Text('Contact Support', style: TextStyle(color: Colors.grey[700])),
                        onPressed: _isLoading ? null : _contactSupport,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          // Optional: To add a subtle border or background on hover/press
                        ),
                      ),
                      // --- *** END: Contact Support Button *** ---
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
