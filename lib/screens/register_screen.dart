// lib/screens/register_screen.dart
import 'package:checkmate/constants/dropdown_data.dart'; // Import constants
import 'package:checkmate/screens/login_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _registrationNumberController = TextEditingController(); // Added
  final AuthService _authService = AuthService();
  String? _selectedSchool;
  String? _selectedDepartment;
  String? _selectedCourse;
  bool _isLoading = false;
  bool _showRegistrationNumberField = false; // Added state for conditional field

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final _formKey = GlobalKey<FormState>();

  // Define the brand color (consistent with WelcomeScreen & LoginScreen)
  static const Color brandColor = Color(0xFF0175C2);

  @override
  void initState() {
    super.initState();
    // Add listener to email controller to check domain
    _emailController.addListener(_checkEmailDomain);
  }

  @override
  void dispose() {
    _emailController.removeListener(_checkEmailDomain); // Remove listener
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _registrationNumberController.dispose(); // Dispose controller
    super.dispose();
  }

  // Check email domain to show/hide registration number field
  void _checkEmailDomain() {
    final email = _emailController.text.trim().toLowerCase();
    // Ensure the domain check is accurate for your specific student emails
    final bool isStudentEmail = email.endsWith('@student.au.ac.ke');
    if (_showRegistrationNumberField != isStudentEmail) {
      setState(() {
        _showRegistrationNumberField = isStudentEmail;
        if (!isStudentEmail) {
          _registrationNumberController.clear(); // Clear field if hidden
        }
      });
    }
  }

  // Helper to show snackbar messages
  void _showSnackBar(String message, {bool isError = true}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  // Registration Action - Updated to include registrationNumber
  Future<void> _handleRegister() async {
    if (!_formKey.currentState!.validate()) {
      return; // Don't proceed if form is invalid
    }

    if (!mounted) return;
    setState(() { _isLoading = true; });

    // Get registration number only if the field is visible (i.e., student email)
    final registrationNumber = _showRegistrationNumberField
        ? _registrationNumberController.text.trim()
        : null;

    try {
      // Call AuthService signUp with all fields, including registrationNumber
      await _authService.signUp(
        _nameController.text.trim(),
        _emailController.text.trim(),
        _passwordController.text,
        _selectedSchool,
        _selectedDepartment,
        _selectedCourse,
        registrationNumber, // Pass registration number (can be null)
      );
      if (!mounted) return;
      _showSuccessDialog(); // Show success message
    } on AuthException catch (e) {
      print("Error during registration: $e");
      if (!mounted) return;
      // Use the helper snackbar for errors
      _showSnackBar(e.message, isError: true);
    } catch (e) {
      // Handle unexpected errors
      print("Unexpected error during registration: $e");
      if (!mounted) return;
      _showSnackBar('An unexpected error occurred. Please try again.', isError: true);
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

    // Common InputDecoration for TextFormFields and Dropdowns - Refined Styling
    InputDecoration inputDecoration(String label, {String? hint, Widget? prefixIcon, Widget? suffixIcon}) {
      return InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade400),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: brandColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1.0),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        filled: true,
        fillColor: Colors.grey[50], // Slightly off-white background
        contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: brandColor, // Apply brand color
        foregroundColor: Colors.white, // Ensure text/icons are white
        elevation: 2.0,
        // Back button is automatically implied
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0), // Adjusted padding
        child: Form(
          key: _formKey, // Use _formKey
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch, // Stretch children
              children: [
                // Name Field
                TextFormField(
                  controller: _nameController,
                  decoration: inputDecoration(
                    'Full Name',
                    hint: 'Enter your full name',
                    prefixIcon: Icon(Icons.person_outline, color: brandColor.withOpacity(0.7)),
                  ),
                  validator: (value) => (value == null || value.isEmpty) ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 18), // Consistent spacing
                // Email Field
                TextFormField(
                  controller: _emailController,
                  decoration: inputDecoration(
                    'Email Address',
                    hint: 'Enter university email (@student.au.ac.ke or @au.ac.ke)', // More specific hint
                    prefixIcon: Icon(Icons.email_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter your email';
                    // Basic email format check
                    if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(value)) return 'Please enter a valid email';
                    // Optional: More specific domain validation if needed
                    // if (!value.toLowerCase().endsWith('.au.ac.ke')) return 'Please use your university email';
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // --- Conditionally Display Registration Number Field ---
                if (_showRegistrationNumberField) ...[
                  TextFormField(
                    controller: _registrationNumberController,
                    decoration: inputDecoration(
                      'Registration Number',
                      hint: 'Enter your student registration number',
                      prefixIcon: Icon(Icons.badge_outlined, color: brandColor.withOpacity(0.7)),
                    ),
                    validator: (value) {
                      // Required only if the field is shown
                      if (_showRegistrationNumberField && (value == null || value.isEmpty)) {
                        return 'Please enter your registration number';
                      }
                      // Add specific format validation if needed (e.g., length, pattern)
                      // Example: Check for a specific pattern like ABC/123/XYZ
                      // if (_showRegistrationNumberField && value != null && !RegExp(r'^[A-Z]{3}/\d{3}/[A-Z]{3}$').hasMatch(value.toUpperCase())) {
                      //   return 'Invalid format (e.g., ABC/123/XYZ)';
                      // }
                      return null;
                    },
                    // Optional: Improve keyboard type or capitalization based on expected format
                    textCapitalization: TextCapitalization.characters,
                  ),
                  const SizedBox(height: 18),
                ],
                // --- End Conditional Field ---

                // Password Field
                TextFormField(
                  controller: _passwordController,
                  decoration: inputDecoration(
                    'Password',
                    hint: 'Minimum 8 characters',
                    prefixIcon: Icon(Icons.lock_outline, color: brandColor.withOpacity(0.7)),
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
                    if (value.length < 8) return 'Password must be at least 8 characters';
                    return null;
                  },
                ),
                const SizedBox(height: 18),
                // Confirm Password Field
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: inputDecoration(
                    'Confirm Password',
                    hint: 'Re-enter your password',
                    prefixIcon: Icon(Icons.lock_outline, color: brandColor.withOpacity(0.7)),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscureConfirmPassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                        color: Colors.grey[600],
                      ),
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                  obscureText: _obscureConfirmPassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please confirm your password';
                    if (value != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 18),

                // --- Use Constant Lists/Maps for Dropdowns with consistent styling ---
                DropdownButtonFormField<String>(
                  decoration: inputDecoration(
                    'School',
                    prefixIcon: Icon(Icons.school_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  value: _selectedSchool,
                  items: schoolsList.map((String school) {
                    return DropdownMenuItem<String>(value: school, child: Text(school, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedSchool = newValue;
                      _selectedDepartment = null; // Reset dependent
                      _selectedCourse = null;
                    });
                  },
                  validator: (value) => value == null ? 'School is required' : null,
                  isExpanded: true, // Ensure dropdown takes full width
                ),
                const SizedBox(height: 18),
                // Department Dropdown
                DropdownButtonFormField<String>(
                  decoration: inputDecoration(
                    'Department',
                    hint: _selectedSchool == null ? 'Select school first' : 'Select your department',
                    prefixIcon: Icon(Icons.business_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  value: _selectedDepartment,
                  items: (_selectedSchool != null && departmentsMap.containsKey(_selectedSchool))
                      ? departmentsMap[_selectedSchool]!.map((String department) {
                          return DropdownMenuItem<String>(value: department, child: Text(department, overflow: TextOverflow.ellipsis));
                        }).toList()
                      : [], // Empty list if no school selected or no departments
                  onChanged: (_selectedSchool == null || !departmentsMap.containsKey(_selectedSchool)) ? null : (String? newValue) {
                    setState(() {
                      _selectedDepartment = newValue;
                      _selectedCourse = null; // Reset course
                    });
                  },
                  validator: (value) => _selectedSchool != null && value == null ? 'Department is required' : null,
                  isExpanded: true,
                  disabledHint: const Text('Select school first'), // Show hint when disabled
                ),
                const SizedBox(height: 18),
                // Course Dropdown
                DropdownButtonFormField<String>(
                  decoration: inputDecoration(
                    'Course',
                     hint: _selectedSchool == null ? 'Select school first' : 'Select your course',
                     prefixIcon: Icon(Icons.book_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  value: _selectedCourse,
                  items: (_selectedSchool != null && coursesMap.containsKey(_selectedSchool))
                      ? coursesMap[_selectedSchool]!.map((String course) {
                          return DropdownMenuItem<String>(value: course, child: Text(course, overflow: TextOverflow.ellipsis));
                        }).toList()
                      : [], // Empty list if no school selected or no courses
                  onChanged: (_selectedSchool == null || !coursesMap.containsKey(_selectedSchool)) ? null : (String? newValue) {
                    setState(() {
                      _selectedCourse = newValue;
                    });
                  },
                  validator: (value) => _selectedSchool != null && value == null ? 'Course is required' : null,
                  isExpanded: true,
                  disabledHint: const Text('Select school first'), // Show hint when disabled
                ),
                const SizedBox(height: 30), // Spacing before button

                // Register Button
                _isLoading
                    ? Center(child: CircularProgressIndicator(color: brandColor)) // Use brand color
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size(double.infinity, 52), // Full width
                          backgroundColor: brandColor, // Brand color
                          foregroundColor: Colors.white, // White text
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30), // Rounded corners
                          ),
                          elevation: 3,
                          textStyle: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _handleRegister, // Call handler
                        child: const Text('Register'),
                      ),
                const SizedBox(height: 15), // Spacing after button

                // Login Link
                TextButton(
                  onPressed: _isLoading ? null : () { // Disable while loading
                    // Navigate to LoginScreen, replacing the current route
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  },
                  style: TextButton.styleFrom(foregroundColor: brandColor), // Brand color text
                  child: const Text("Already have an account? Login here"),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Show success dialog after registration
  void _showSuccessDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing easily
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // Rounded dialog
          title: Row( // Add icon to title
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green[600], size: 28),
              const SizedBox(width: 10),
              const Text('Registration Successful'),
            ],
          ),
          content: const Text('A verification email has been sent.\nPlease check your inbox (and spam folder) and click the link to verify your account before logging in.'),
          actions: <Widget>[
            TextButton(
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                // Pop RegisterScreen to go back to LoginScreen
                if (Navigator.canPop(context)) {
                   Navigator.of(context).pop();
                } else {
                   // Fallback if Register was the first screen (unlikely)
                   Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const LoginScreen()));
                }
              },
            ),
          ],
        );
      },
    );
  }
}
