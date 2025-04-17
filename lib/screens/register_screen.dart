// lib/screens/register_screen.dart
import 'package:checkmate/constants/dropdown_data.dart'; // Import constants
import 'package:checkmate/screens/login_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:checkmate/widgets/custom_button.dart';
import 'package:flutter/material.dart';
// Remove Provider import if not used directly here

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
  final AuthService _authService = AuthService(); // Keep AuthService for registration
  String? _selectedSchool;
  String? _selectedDepartment;
  String? _selectedCourse;
  bool _isLoading = false; // Made non-final to allow changes

  // --- Remove local dropdown data lists/maps ---
  // final List<String> _schools = [ ... ];
  // final Map<String, List<String>> _departments = { ... };
  // final Map<String, List<String>> _courses = { ... };

  bool _obscurePassword = true; // Made non-final
  bool _obscureConfirmPassword = true; // Made non-final
  final _formKey = GlobalKey<FormState>(); // Renamed from formKey for consistency

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
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

  @override
  Widget build(BuildContext context) {
    // Calculate dynamic lists here if needed, though not strictly necessary
    // as onChanged handles the logic for dependent dropdowns
    // List<String> currentDepartments = (_selectedSchool != null && departmentsMap.containsKey(_selectedSchool))
    //     ? departmentsMap[_selectedSchool]!
    //     : [];
    // List<String> currentCourses = (_selectedSchool != null && coursesMap.containsKey(_selectedSchool))
    //     ? coursesMap[_selectedSchool]!
    //     : [];


    return Scaffold(
      appBar: AppBar(
        title: const Text('Register'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey, // Use _formKey
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder()),
                  validator: (value) => (value == null || value.isEmpty) ? 'Please enter your name' : null,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(labelText: 'Email', border: OutlineInputBorder()),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter your email';
                    // Basic email format check
                    if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(value)) return 'Please enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _passwordController,
                  decoration: InputDecoration(
                    labelText: 'Password', border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      // Use _obscurePassword state variable
                      icon: Icon(_obscurePassword ? Icons.visibility_off : Icons.visibility),
                      // Update _obscurePassword state variable
                      onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                    ),
                  ),
                  obscureText: _obscurePassword, // Use _obscurePassword state variable
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please enter your password';
                    if (value.length < 8) return 'Password must be at least 8 characters';
                    // Add other password complexity rules if desired (e.g., uppercase, number, special char)
                    // if (!value.contains(RegExp(r'[A-Z]'))) return 'Password must contain an uppercase letter';
                    // if (!value.contains(RegExp(r'[0-9]'))) return 'Password must contain a number';
                    // if (!value.contains(RegExp(r'[!@#\$%^&*(),.?":{}|<>]'))) return 'Password must contain a special character';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _confirmPasswordController,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password', border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      // Use _obscureConfirmPassword state variable
                      icon: Icon(_obscureConfirmPassword ? Icons.visibility_off : Icons.visibility),
                      // Update _obscureConfirmPassword state variable
                      onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
                    ),
                  ),
                  obscureText: _obscureConfirmPassword, // Use _obscureConfirmPassword state variable
                  validator: (value) {
                    if (value == null || value.isEmpty) return 'Please confirm your password';
                    if (value != _passwordController.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 20),

                // --- Use Constant Lists/Maps for Dropdowns ---
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'School', border: OutlineInputBorder()),
                  value: _selectedSchool,
                  // Use constant list from dropdown_data.dart
                  items: schoolsList.map((String school) {
                    return DropdownMenuItem<String>(value: school, child: Text(school, overflow: TextOverflow.ellipsis));
                  }).toList(),
                  onChanged: (String? newValue) {
                    setState(() {
                      _selectedSchool = newValue;
                      _selectedDepartment = null; // Reset dependent
                      _selectedCourse = null;
                      // No need to recalculate currentDepartments/currentCourses here
                      // as the dependent dropdowns will use the updated _selectedSchool
                      // and the constant maps directly in their items builder.
                    });
                  },
                  validator: (value) => value == null ? 'School is required' : null,
                  isExpanded: true, // Ensure dropdown takes full width
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(labelText: 'Department', border: const OutlineInputBorder(), hintText: _selectedSchool == null ? 'Select school first' : null),
                  value: _selectedDepartment,
                  // Use constant map directly based on current _selectedSchool
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
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  decoration: InputDecoration(labelText: 'Course', border: const OutlineInputBorder(), hintText: _selectedSchool == null ? 'Select school first' : null),
                  value: _selectedCourse,
                  // Use constant map directly based on current _selectedSchool
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
                ),
                const SizedBox(height: 20),
                _isLoading
                    ? const CircularProgressIndicator()
                    : CustomButton(
                        onPressed: () async {
                          if (_formKey.currentState!.validate()) {
                            if (!mounted) return;
                            setState(() { _isLoading = true; });
                            try {
                              // AuthService handles user creation and setting Firestore data
                              await _authService.signUp(
                                _nameController.text.trim(),
                                _emailController.text.trim(),
                                _passwordController.text,
                                _selectedSchool,
                                _selectedDepartment,
                                _selectedCourse,
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
                        },
                        text: 'Register',
                      ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: _isLoading ? null : () { // Disable while loading
                    // Navigate to LoginScreen, replacing the current route if desired
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  },
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
  void _showSuccessDialog() { // Renamed for clarity
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing easily
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Registration Successful'),
          content: const Text('A verification email has been sent. Please verify your email to log in.'),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                // Optionally navigate back further or directly to login
                if (Navigator.canPop(context)) {
                   // Pop RegisterScreen to go back to where it was pushed from (likely Login or Welcome)
                   Navigator.of(context).pop();
                } else {
                   // If RegisterScreen was the first screen, pushReplacement to Login
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
