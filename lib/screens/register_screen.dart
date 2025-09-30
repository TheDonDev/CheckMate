// lib/screens/register_screen.dart
import 'package:checkmate/constants/dropdown_data.dart'; // Import constants
import 'package:checkmate/screens/login_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Import for input formatters

// Custom Input Formatter to force uppercase input
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(), // Convert text to uppercase
      selection: newValue.selection,     // Keep cursor position
    );
  }
}


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
  final TextEditingController _phoneNumberController = TextEditingController(); // Phone Number Controller

  // --- Services ---
  final AuthService _authService = AuthService();

  // --- State Variables ---
  String? _selectedSchool;
  String? _selectedDepartment;
  String? _selectedCourse;
  String? _selectedYearOfStudy;
  String? _selectedSemester;
  bool _isLoading = false;
  bool _isStudent = false; // Determined by email domain
  bool _isAdmin = false; // Determined by admin email

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final _formKey = GlobalKey<FormState>();

  // --- Constants ---
  static const Color brandColor = Color(0xFF0175C2); // Consistent brand color

  @override
  void initState() {
    super.initState();
    // Listen to email changes to determine user type (student or admin)
    _emailController.addListener(_checkEmailStatus);
  }

  @override
  void dispose() {
    _emailController.removeListener(_checkEmailStatus);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _registrationNumberController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }

  // Check email to determine user type and update UI accordingly
  void _checkEmailStatus() {
    final email = _emailController.text.trim().toLowerCase();
    final bool isStudentEmail = email.endsWith('@student.au.ac.ke');
    final bool isAdminEmail = email == 'donaldmwanga33@gmail.com';

    if (mounted && (_isStudent != isStudentEmail || _isAdmin != isAdminEmail)) {
      setState(() {
        _isStudent = isStudentEmail;
        _isAdmin = isAdminEmail;

        // Clear student-specific fields if not a student
        if (!_isStudent) {
          _registrationNumberController.clear();
          _selectedYearOfStudy = null;
          _selectedSemester = null;
        }
        // Trigger re-validation for the whole form
        _formKey.currentState?.validate();
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

  // Registration Action - Handles both students and lecturers
  Future<void> _handleRegister() async {
    // Validate the form first
    if (!_formKey.currentState!.validate()) {
      _showSnackBar('Please fix the errors in the form.', isError: true);
      return; // Don't proceed if form is invalid
    }

    // Check mount status before proceeding with async operation
    if (!mounted) return;
    setState(() { _isLoading = true; });

    // Conditionally get student-specific data
    final registrationNumber = _isStudent ? _registrationNumberController.text.trim() : null;
    final yearOfStudy = _isStudent ? _selectedYearOfStudy : null;
    final semester = _isStudent ? _selectedSemester : null;

    // Get common data
    final name = _nameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final phoneNumber = _phoneNumberController.text.trim(); // Already validated

    try {
      // Call AuthService signUp with all relevant fields
      await _authService.signUp(
        name: name,
        email: email,
        password: password,
        phoneNumber: phoneNumber,
        school: _selectedSchool,
        department: _selectedDepartment,
        course: _selectedCourse,
        // Pass student-specific data only if the user is a student
        registrationNumber: registrationNumber,
        yearOfStudy: yearOfStudy,
        semester: semester,
      );

      // Check mount status again after async operation before showing dialog
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
      // Ensure loading indicator is turned off even if widget is disposed
      if (mounted) {
        setState(() { _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    // Common InputDecoration for TextFormFields and Dropdowns
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
        fillColor: Colors.grey[50],
        contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
        errorStyle: TextStyle(fontSize: 12, color: colorScheme.error),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Account'),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        elevation: 2.0,
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Name Field
                TextFormField(
                  controller: _nameController,
                  decoration: inputDecoration(
                    'Full Name',
                    // Updated hint text to be more inclusive
                    hint: 'E.g., JOHN DOE or PROF. JANE D. SMITH ',
                    prefixIcon: Icon(Icons.person_outline, color: brandColor.withOpacity(0.7)),
                  ),
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                    // Allow uppercase letters, spaces, and periods
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Z .]')),
                  ],
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) {
                    // --- Name Validation Logic  ---
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your full name';
                    }
                    final trimmedValue = value.trim();

                    // 1. Basic Character Check
                    if (!RegExp(r'^[A-Z .]+$').hasMatch(trimmedValue)) {
                       return 'Name can only contain uppercase letters, spaces, and periods.';
                    }

                    // 2. Check for invalid patterns
                    if (trimmedValue.contains('  ')) {
                      return 'Use single spaces only between name parts.';
                    }
                    if (trimmedValue.contains('..')) {
                      return 'Consecutive periods are not allowed.';
                    }
                    if (trimmedValue.startsWith('.') || trimmedValue.endsWith('.') || trimmedValue.startsWith(' ') || trimmedValue.endsWith(' ')) {
                      return 'Name cannot start or end with a space or period.';
                    }

                    // 3. Split into parts
                    final parts = trimmedValue.split(' ').where((part) => part.isNotEmpty).toList();
                    if (parts.isEmpty) {
                        return 'Please enter your full name';
                    }

                    // 4. Validate parts (Designation, Names, Initials)
                    bool hasDesignation = parts[0].endsWith('.') && parts[0].length > 1;
                    int namePartStartIndex = 0;
                    String? partError;

                    // Validate designation if present
                    if (hasDesignation) {
                        String designationText = parts[0].substring(0, parts[0].length - 1);
                        if (!RegExp(r'^[A-Z]+$').hasMatch(designationText)) {
                            return 'Designation part must contain only letters before the period (e.g., DR., PROF.)';
                        }
                        namePartStartIndex = 1;
                    }

                    // Validate the remaining parts
                    int nameOrInitialCount = 0;
                    for (int i = namePartStartIndex; i < parts.length; i++) {
                        String currentPart = parts[i];
                        bool isFullNamePart = RegExp(r'^[A-Z]+$').hasMatch(currentPart);
                        bool isInitialPart = RegExp(r'^[A-Z]\.$').hasMatch(currentPart);

                        if (isFullNamePart || isInitialPart) {
                            nameOrInitialCount++;
                            if (isFullNamePart && currentPart.contains('.')) {
                                partError = 'Periods are only allowed after single initials (e.g., K.) or designations (e.g., DR.).';
                                break;
                            }
                        } else {
                            partError = 'Name parts must be full names (e.g., JOHN) or initials ending with a period (e.g., K.). Invalid part: "$currentPart"';
                            break;
                        }
                    }

                    if (partError != null) {
                        return partError;
                    }

                    // 5. Check minimum number of name/initial parts
                    if (nameOrInitialCount < 2) {
                        return hasDesignation
                            ? 'Enter at least two name parts/initials after the designation (e.g., DR. J. DOE)'
                            : 'Enter at least a First and Last name or initial (e.g., J. DOE or JOHN DOE)';
                    }

                    return null; // Name is valid
                    // --- End Name Validation ---
                  },
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 18),

                // Email Field
                TextFormField(
                  controller: _emailController,
                  decoration: inputDecoration(
                    'Email Address',
                    // Updated hint text to include all allowed domains
                    hint: 'Use @student.au.ac.ke, @au.ac.ke, or @kibu.ac.ke',
                    prefixIcon: Icon(Icons.email_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    final email = value.trim().toLowerCase();
                    // Basic email format check
                    if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$").hasMatch(email)) {
                      return 'Please enter a valid email address';
                    }
                    // *** UPDATED DOMAIN VALIDATION ***
                    // Check if the email ends with one of the allowed university domains or is the admin email
                    final allowedDomains = ['@student.au.ac.ke', '@au.ac.ke', '@kibu.ac.ke'];
                    bool isValidDomain = allowedDomains.any((domain) => email.endsWith(domain)) || email == 'donaldmwanga33@gmail.com';

                    if (!isValidDomain) {
                      return 'Use a valid university email (@student.au.ac.ke, @au.ac.ke, or @kibu.ac.ke)';
                    }
                    return null; // Email is valid
                  },
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 18),

                // Phone Number Field
                TextFormField(
                  controller: _phoneNumberController,
                  decoration: inputDecoration(
                    'Phone Number',
                    hint: '+254712345678 or +254112345678',
                    prefixIcon: Icon(Icons.phone_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[+0-9]')),
                    LengthLimitingTextInputFormatter(13), // +254 plus 9 digits
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your phone number';
                    }
                    final trimmedValue = value.trim();
                    // Regex for Kenyan phone numbers starting with +254 followed by 7 or 1 and 8 digits
                    final RegExp phoneRegExp = RegExp(r'^\+254[17]\d{8}$');
                    if (!phoneRegExp.hasMatch(trimmedValue)) {
                      return 'Format must be +2547xxxxxxxx or +2541xxxxxxxx';
                    }
                    return null; // Valid format
                  },
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 18),

                // --- Conditionally Display Student-Specific Fields ---
                // These fields are only shown if the email domain is @student.au.ac.ke
                if (_isStudent) ...[
                  // Registration Number Field
                  TextFormField(
                    controller: _registrationNumberController,
                    decoration: inputDecoration(
                      'Registration Number',
                      prefixIcon: Icon(Icons.badge_outlined, color: brandColor.withOpacity(0.7)),
                    ),
                    // Validation only applies if the user is a student
                    validator: (value) {
                      if (_isStudent && (value == null || value.trim().isEmpty)) {
                        return 'Please enter your registration number';
                      }
                      // Add more specific registration number format validation if needed
                      return null;
                    },
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9/-]')), // Allow letters, numbers, hyphen, slash
                    ],
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
                    items: yearsList.map((String year) {
                      return DropdownMenuItem<String>(value: year, child: Text(year));
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (mounted) {
                        setState(() { _selectedYearOfStudy = newValue; });
                      }
                    },
                    // Validation only applies if the user is a student
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
                    items: semestersList.map((String semester) {
                      return DropdownMenuItem<String>(value: semester, child: Text(semester));
                    }).toList(),
                    onChanged: (String? newValue) {
                      if (mounted) {
                        setState(() { _selectedSemester = newValue; });
                      }
                    },
                    // Validation only applies if the user is a student
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
                    // Consider adding more complexity requirements (e.g., numbers, symbols)
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
                  // Adjust textInputAction based on whether student fields are visible
                  textInputAction: _isStudent ? TextInputAction.next : TextInputAction.done,
                  // If not a student, hitting done on keyboard can trigger registration
                  onFieldSubmitted: _isStudent ? null : (_) => _handleRegister(),
                ),
                const SizedBox(height: 18),

                // --- School/Dept/Course Dropdowns (Visible unless admin) ---
                if (!_isAdmin) ...[
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
                      if (mounted) {
                        setState(() {
                          _selectedSchool = newValue;
                          _selectedDepartment = null; // Reset dependent dropdowns
                          _selectedCourse = null;
                        });
                        // Trigger re-validation if needed
                        _formKey.currentState?.validate();
                      }
                    },
                    validator: (value) => !_isAdmin && value == null ? 'Please select your school' : null,
                    isExpanded: true,
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
                    disabledHint: _selectedSchool == null ? const Text('Select school first') : null,
                    // Enable/disable and populate based on school selection
                    items: (_selectedSchool != null && departmentsMap.containsKey(_selectedSchool))
                        ? departmentsMap[_selectedSchool]!.map((String department) {
                            return DropdownMenuItem<String>(value: department, child: Text(department, overflow: TextOverflow.ellipsis));
                          }).toList()
                        : [], // Empty list if no school selected or school not in map
                    onChanged: (_selectedSchool == null || !departmentsMap.containsKey(_selectedSchool)) ? null : (String? newValue) {
                      if (mounted) {
                        setState(() {
                          _selectedDepartment = newValue;
                          _selectedCourse = null; // Reset course when department changes
                        });
                        // Trigger re-validation if needed
                        _formKey.currentState?.validate();
                      }
                    },
                    // Validation applies only if a school is selected
                    validator: (value) => !_isAdmin && _selectedSchool != null && value == null ? 'Please select your department' : null,
                    isExpanded: true,
                  ),
                  const SizedBox(height: 18),

                  // Course Dropdown
                  DropdownButtonFormField<String>(
                    decoration: inputDecoration(
                      'Course', // Label remains 'Course' for simplicity, applicable to lecturer's primary course area too
                       hint: _selectedDepartment == null ? 'Select department first' : 'Select your course',
                       prefixIcon: Icon(Icons.book_outlined, color: brandColor.withOpacity(0.7)),
                    ),
                    value: _selectedCourse,
                    disabledHint: _selectedDepartment == null ? const Text('Select department first') : null,
                    // Enable/disable and populate based on school selection (courses are mapped by school)
                    items: (_selectedSchool != null && coursesMap.containsKey(_selectedSchool))
                        ? coursesMap[_selectedSchool]!.map((String course) {
                            return DropdownMenuItem<String>(value: course, child: Text(course, overflow: TextOverflow.ellipsis));
                          }).toList()
                        : [], // Empty list if no school selected or school not in map
                    onChanged: (_selectedSchool == null || _selectedDepartment == null || !coursesMap.containsKey(_selectedSchool)) ? null : (String? newValue) {
                      if (mounted) {
                        setState(() {
                          _selectedCourse = newValue;
                        });
                        // Trigger re-validation if needed
                        _formKey.currentState?.validate();
                      }
                    },
                    // Validation applies only if a department is selected
                    validator: (value) => !_isAdmin && _selectedDepartment != null && value == null ? 'Please select your course' : null,
                    isExpanded: true,
                  ),
                  const SizedBox(height: 30),
                ],

                // Register Button
                _isLoading
                    ? Center(child: CircularProgressIndicator(color: brandColor))
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
                            letterSpacing: 0.5,
                          ),
                        ),
                        onPressed: _handleRegister, // Calls the registration logic
                        child: const Text('Register'),
                      ),
                const SizedBox(height: 15),

                // Login Link
                TextButton(
                  onPressed: _isLoading ? null : () { // Disable button while loading
                    // Navigate to LoginScreen, replacing the current route
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  },
                  style: TextButton.styleFrom(foregroundColor: brandColor),
                  child: const Text("Already have an account? Login here"),
                ),
                const SizedBox(height: 20), // Bottom padding
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Show success dialog after registration
  void _showSuccessDialog() {
    // Check mount status before showing dialog
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false, // User must tap button to close
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.green[600], size: 28),
              const SizedBox(width: 10),
              const Text('Registration Successful'),
            ],
          ),
          content: Text(_isAdmin
              ? 'Admin account created successfully. You can now log in.'
              : 'A verification email has been sent.\nPlease check your inbox (and spam folder) and click the link to verify your account before logging in.'),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(foregroundColor: brandColor),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                // 1. Close the success dialog
                Navigator.of(context).pop(); // Use the dialog's context to pop itself
                // 2. Navigate to LoginScreen, replacing the current route
                //    Use pushReplacement to prevent user from going back to RegisterScreen
                if (mounted) { // Check mount status again before navigation
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginScreen()),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }
}