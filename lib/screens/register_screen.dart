// lib/screens/register_screen.dart
import 'package:checkmate/constants/dropdown_data.dart'; // Import constants
import 'package:checkmate/screens/login_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for input formatters

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  // --- Controllers ---
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();
  final TextEditingController _registrationNumberController = TextEditingController();
  final TextEditingController _phoneNumberController = TextEditingController(); // Added Phone Number Controller

  // --- Services ---
  final AuthService _authService = AuthService();

  // --- State Variables ---
  String? _selectedSchool;
  String? _selectedDepartment;
  String? _selectedCourse;
  String? _selectedYearOfStudy; // Added Year of Study state
  String? _selectedSemester;   // Added Semester state
  bool _isLoading = false;
  bool _isStudent = false; // Renamed from _showRegistrationNumberField for clarity

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final _formKey = GlobalKey<FormState>();

  // --- Constants ---
  static const Color brandColor = Color(0xFF0175C2); // Consistent brand color

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
    _registrationNumberController.dispose();
    _phoneNumberController.dispose(); // Dispose phone controller
    super.dispose();
  }

  // Check email domain to show/hide student-specific fields
  void _checkEmailDomain() {
    final email = _emailController.text.trim().toLowerCase();
    // Use the specified student domain
    final bool isStudentEmail = email.endsWith('@student.au.ac.ke');
    if (_isStudent != isStudentEmail) {
      setState(() {
        _isStudent = isStudentEmail;
        // Clear student-specific fields if email is no longer a student email
        if (!isStudentEmail) {
          _registrationNumberController.clear();
          _selectedYearOfStudy = null; // Clear year selection
          _selectedSemester = null;   // Clear semester selection
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

  // Registration Action - Updated to include all new fields
  Future<void> _handleRegister() async {
    // Validate the form first
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please fix the errors in the form.', isError: true);
      return; // Don't proceed if form is invalid
    }

    // Check network connection
    // final connectivityResult = await Connectivity().checkConnectivity();
    // if (connectivityResult == ConnectivityResult.none) {
    //   _showSnackBar('No internet connection.', isError: true);
    //   return;
    // }


    if (!mounted) return;
    setState(() { _isLoading = true; });

    // Get student-specific data only if the fields are visible (i.e., student email)
    final registrationNumber = _isStudent ? _registrationNumberController.text.trim() : null;
    final yearOfStudy = _isStudent ? _selectedYearOfStudy : null;
    final semester = _isStudent ? _selectedSemester : null;

    try {
      // Call AuthService signUp with all fields using NAMED parameters for clarity
      // Ensure your AuthService.signUp method signature matches these named parameters
      await _authService.signUp(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        phoneNumber: _phoneNumberController.text.trim(), // Pass phone number
        school: _selectedSchool, // Already validated by form
        department: _selectedDepartment, // Already validated by form
        course: _selectedCourse, // Already validated by form
        registrationNumber: registrationNumber, // Pass registration number (can be null)
        yearOfStudy: yearOfStudy,               // Pass year of study (can be null)
        semester: semester,                     // Pass semester (can be null)
      );
      if (!mounted) return;
      _showSuccessDialog(); // Show success message
    } on AuthException catch (e) {
      print("AuthException during registration: ${e.message}");
      if (!mounted) return;
      _showSnackBar(e.message, isError: true); // Show specific auth error
    } catch (e) {
      // Handle unexpected errors
      print("Unexpected error during registration: $e");
      if (!mounted) return;
      _showSnackBar('An unexpected error occurred. Please try again later.', isError: true);
    } finally {
      // Ensure loading indicator is turned off even if widget is disposed during async operation
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
        errorStyle: TextStyle(fontSize: 12, color: colorScheme.error), // Consistent error style
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: brandColor, // Apply brand color
        foregroundColor: Colors.white, // Ensure text/icons are white
        elevation: 2.0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0), // Adjusted padding
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
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your name';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 18), // Consistent spacing

                // Email Field
                TextFormField(
                  controller: _emailController,
                  decoration: inputDecoration(
                    'Email Address',
                    hint: 'Enter university email (@student.au.ac.ke or @au.ac.ke)', // Specific hint
                    prefixIcon: Icon(Icons.email_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    final email = value.trim().toLowerCase();
                    // Basic email format check
                    if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(email)) {
                      return 'Please enter a valid email address';
                    }
                    // Check if it ends with the university domain suffix
                    if (!email.endsWith('au.ac.ke')) {
                      return 'Please use your university email (@student.au.ac.ke or @au.ac.ke)';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 18),

                // Phone Number Field (Visible for everyone)
                TextFormField(
                  controller: _phoneNumberController,
                  decoration: inputDecoration(
                    'Phone Number',
                    hint: 'e.g., 0712345678',
                    prefixIcon: Icon(Icons.phone_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly, // Allow only digits
                    LengthLimitingTextInputFormatter(10), // Limit to 10 digits
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your phone number';
                    }
                    if (value.length != 10) {
                      return 'Phone number must be 10 digits';
                    }
                    // Add more specific format validation if needed (e.g., starts with 07 or 01)
                    if (!value.startsWith('0')) {
                       return 'Phone number must start with 0';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 18),

                // --- Conditionally Display Student-Specific Fields ---
                if (_isStudent) ...[
                  // Registration Number Field
                  TextFormField(
                    controller: _registrationNumberController,
                    decoration: inputDecoration(
                      'Registration Number',
                      hint: 'Enter your student registration number',
                      prefixIcon: Icon(Icons.badge_outlined, color: brandColor.withOpacity(0.7)),
                    ),
                    validator: (value) {
                      // Required only if the field is shown (i.e., isStudent is true)
                      if (_isStudent && (value == null || value.trim().isEmpty)) {
                        return 'Please enter your registration number';
                      }
                      // Add specific format validation if needed
                      return null;
                    },
                    textCapitalization: TextCapitalization.characters,
                    textInputAction: TextInputAction.next,
                  ),
                  const SizedBox(height: 18),

                  // Year of Study Dropdown
                  DropdownButtonFormField<String>(
                    decoration: inputDecoration(
                      'Year of Study',
                      prefixIcon: Icon(Icons.calendar_today_outlined, color: brandColor.withOpacity(0.7)),
                    ),
                    value: _selectedYearOfStudy,
                    items: yearsList.map((String year) { // Use yearsList from constants
                      return DropdownMenuItem<String>(value: year, child: Text(year));
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedYearOfStudy = newValue;
                      });
                    },
                    validator: (value) => _isStudent && value == null ? 'Please select year of study' : null,
                    isExpanded: true,
                  ),
                  const SizedBox(height: 18),

                  // Semester Dropdown
                  DropdownButtonFormField<String>(
                    decoration: inputDecoration(
                      'Current Semester',
                      prefixIcon: Icon(Icons.schedule_outlined, color: brandColor.withOpacity(0.7)),
                    ),
                    value: _selectedSemester,
                    items: semestersList.map((String semester) { // Use semestersList from constants
                      return DropdownMenuItem<String>(value: semester, child: Text(semester));
                    }).toList(),
                    onChanged: (String? newValue) {
                      setState(() {
                        _selectedSemester = newValue;
                      });
                    },
                    validator: (value) => _isStudent && value == null ? 'Please select current semester' : null,
                    isExpanded: true,
                  ),
                  const SizedBox(height: 18),
                ],
                // --- End Conditional Fields ---

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
                    if (value == null || value.isEmpty) {
                      return 'Please enter your password';
                    }
                    if (value.length < 8) {
                      return 'Password must be at least 8 characters';
                    }
                    // Add more password complexity rules if needed (e.g., require numbers, symbols)
                    return null;
                  },
                  textInputAction: TextInputAction.next,
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
                    if (value == null || value.isEmpty) {
                      return 'Please confirm your password';
                    }
                    if (value != _passwordController.text) {
                      return 'Passwords do not match';
                    }
                    return null;
                  },
                  textInputAction: TextInputAction.next, // Change to done if it's the last text field before dropdowns
                ),
                const SizedBox(height: 18),

                // --- School/Dept/Course Dropdowns (Visible for everyone) ---
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
                  validator: (value) => value == null ? 'Please select your school' : null,
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
                  // Disable dropdown if school is not selected
                  disabledHint: _selectedSchool == null ? const Text('Select school first') : null,
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
                  validator: (value) => _selectedSchool != null && value == null ? 'Please select your department' : null,
                  isExpanded: true,
                ),
                const SizedBox(height: 18),

                // Course Dropdown
                DropdownButtonFormField<String>(
                  decoration: inputDecoration(
                    'Course',
                     hint: _selectedDepartment == null ? 'Select department first' : 'Select your course',
                     prefixIcon: Icon(Icons.book_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  value: _selectedCourse,
                  // Disable dropdown if department is not selected
                  disabledHint: _selectedDepartment == null ? const Text('Select department first') : null,
                  items: (_selectedSchool != null && _selectedDepartment != null && coursesMap.containsKey(_selectedSchool)) // Ensure school is selected too
                      ? coursesMap[_selectedSchool]!.map((String course) { // Using coursesMap linked to SCHOOL as per dropdown_data.dart
                          return DropdownMenuItem<String>(value: course, child: Text(course, overflow: TextOverflow.ellipsis));
                        }).toList()
                      : [], // Empty list if prerequisites not met
                  onChanged: (_selectedSchool == null || _selectedDepartment == null || !coursesMap.containsKey(_selectedSchool)) ? null : (String? newValue) {
                    setState(() {
                      _selectedCourse = newValue;
                    });
                  },
                  validator: (value) => _selectedDepartment != null && value == null ? 'Please select your course' : null,
                  isExpanded: true,
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
                            letterSpacing: 0.5,
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
                const SizedBox(height: 20), // Add some bottom padding
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
              style: TextButton.styleFrom(foregroundColor: brandColor), // Use brand color for button text
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.of(context).pop(); // Close the dialog
                // Navigate back to Login Screen after successful registration
                 if (Navigator.canPop(context)) {
                   // If RegisterScreen was pushed onto the stack, pop it.
                   Navigator.of(context).pop();
                 } else {
                   // Otherwise, replace the current screen with LoginScreen.
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
