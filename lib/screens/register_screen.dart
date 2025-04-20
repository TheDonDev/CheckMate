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
  bool _isStudent = false;

  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final _formKey = GlobalKey<FormState>();

  // --- Constants ---
  static const Color brandColor = Color(0xFF0175C2); // Consistent brand color

  @override
  void initState() {
    super.initState();
    _emailController.addListener(_checkEmailDomain);
  }

  @override
  void dispose() {
    _emailController.removeListener(_checkEmailDomain);
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _registrationNumberController.dispose();
    _phoneNumberController.dispose();
    super.dispose();
  }

  // Check email domain to show/hide student-specific fields
  void _checkEmailDomain() {
    final email = _emailController.text.trim().toLowerCase();
    final bool isStudentEmail = email.endsWith('@student.au.ac.ke');
    // Use mounted check before calling setState
    if (mounted && _isStudent != isStudentEmail) {
      setState(() {
        _isStudent = isStudentEmail;
        if (!isStudentEmail) {
          _registrationNumberController.clear();
          _selectedYearOfStudy = null;
          _selectedSemester = null;
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

    // Check mount status before proceeding
    if (!mounted) return;
    setState(() { _isLoading = true; });

    final registrationNumber = _isStudent ? _registrationNumberController.text.trim() : null;
    final yearOfStudy = _isStudent ? _selectedYearOfStudy : null;
    final semester = _isStudent ? _selectedSemester : null;

    // Get the validated phone number (already validated by the form)
    final phoneNumber = _phoneNumberController.text.trim();

    try {
      // Call AuthService signUp with all fields
      await _authService.signUp(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        password: _passwordController.text,
        phoneNumber: phoneNumber, // Pass the validated +254... number
        school: _selectedSchool,
        department: _selectedDepartment,
        course: _selectedCourse,
        registrationNumber: registrationNumber,
        yearOfStudy: yearOfStudy,
        semester: semester,
      );
      // Check mount status again after async operation
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
                    hint: 'E.g., JOHN DOE or DR. JANE DOE',
                    prefixIcon: Icon(Icons.person_outline, color: brandColor.withOpacity(0.7)),
                  ),
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Z .]')),
                  ],
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) {
                    // --- Name Validation Logic ---
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your full name';
                    }
                    final trimmedValue = _nameController.text.trim();
                    if (!RegExp(r'^[A-Z .]+$').hasMatch(trimmedValue)) {
                       return 'Name can only contain uppercase letters, spaces, and periods for designation (e.g., DR.)';
                    }
                    if (trimmedValue.contains('  ')) {
                      return 'Use single spaces only between name parts';
                    }
                    final parts = trimmedValue.split(' ').where((part) => part.isNotEmpty).toList();
                    if (parts.isEmpty) {
                        return 'Please enter your full name';
                    }
                    bool hasDesignation = parts[0].endsWith('.');
                    bool periodError = false;
                    String? partError = null;
                    for (int i = 0; i < parts.length; i++) {
                        String currentPart = parts[i];
                        bool isDesignationPart = (i == 0 && hasDesignation);
                        if (currentPart.contains('.')) {
                            if (!isDesignationPart || !currentPart.endsWith('.') || currentPart.length == 1) {
                                periodError = true; break;
                            }
                            String designationText = currentPart.substring(0, currentPart.length - 1);
                            if (!RegExp(r'^[A-Z]+$').hasMatch(designationText)) {
                                partError = 'Designation part must contain only letters before the period (e.g., DR.)'; break;
                            }
                        } else if (!isDesignationPart) {
                             if (!RegExp(r'^[A-Z]+$').hasMatch(currentPart)) {
                                 partError = 'Name parts (First, Second, Last) must contain only uppercase letters (A-Z)'; break;
                             }
                        }
                    }
                    if (periodError) { return 'Period (.) only allowed at the end of a designation (e.g., DR.)'; }
                    if (partError != null) { return partError; }
                    if (hasDesignation) {
                        if (parts.length < 3) { return 'Enter Designation, First Name, and Second Name (e.g., DR. JOHN DOE)'; }
                    } else {
                        if (parts.length < 2) { return 'Enter at least First and Second name (e.g., JOHN DOE)'; }
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
                    hint: 'Enter university email (@student.au.ac.ke or @au.ac.ke)',
                    prefixIcon: Icon(Icons.email_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your email';
                    }
                    final email = value.trim().toLowerCase();
                    if (!RegExp(r"^[a-zA-Z0-9.a-zA-Z0-9.!#$%&'*+-/=?^_`{|}~]+@[a-zA-Z0-9]+\.[a-zA-Z]+").hasMatch(email)) {
                      return 'Please enter a valid email address';
                    }
                    if (!email.endsWith('au.ac.ke')) {
                      return 'Please use your university email (@student.au.ac.ke or @au.ac.ke)';
                    }
                    return null;
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
                    LengthLimitingTextInputFormatter(13),
                  ],
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter your phone number';
                    }
                    final trimmedValue = value.trim();
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
                if (_isStudent) ...[
                  // Registration Number Field
                  TextFormField(
                    controller: _registrationNumberController,
                    decoration: inputDecoration(
                      'Registration Number',
                      prefixIcon: Icon(Icons.badge_outlined, color: brandColor.withOpacity(0.7)),
                    ),
                    validator: (value) {
                      if (_isStudent && (value == null || value.trim().isEmpty)) {
                        return 'Please enter your registration number';
                      }
                      return null;
                    },
                    textCapitalization: TextCapitalization.characters,
                    inputFormatters: [
                      UpperCaseTextFormatter(),
                      FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9/-]')),
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
                      // Use mounted check before calling setState
                      if (mounted) {
                        setState(() { _selectedYearOfStudy = newValue; });
                      }
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
                    items: semestersList.map((String semester) {
                      return DropdownMenuItem<String>(value: semester, child: Text(semester));
                    }).toList(),
                    onChanged: (String? newValue) {
                      // Use mounted check before calling setState
                      if (mounted) {
                        setState(() { _selectedSemester = newValue; });
                      }
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
                  textInputAction: _isStudent ? TextInputAction.next : TextInputAction.done,
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
                    // Use mounted check before calling setState
                    if (mounted) {
                      setState(() {
                        _selectedSchool = newValue;
                        _selectedDepartment = null; // Reset dependent
                        _selectedCourse = null;
                        // Note: _updateDependentDropdowns is implicitly handled by build
                      });
                    }
                  },
                  validator: (value) => value == null ? 'Please select your school' : null,
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
                  // Rebuild items based on current _selectedSchool
                  items: (_selectedSchool != null && departmentsMap.containsKey(_selectedSchool))
                      ? departmentsMap[_selectedSchool]!.map((String department) {
                          return DropdownMenuItem<String>(value: department, child: Text(department, overflow: TextOverflow.ellipsis));
                        }).toList()
                      : [],
                  onChanged: (_selectedSchool == null || !departmentsMap.containsKey(_selectedSchool)) ? null : (String? newValue) {
                    // Use mounted check before calling setState
                    if (mounted) {
                      setState(() {
                        _selectedDepartment = newValue;
                        _selectedCourse = null; // Reset course
                      });
                    }
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
                  disabledHint: _selectedDepartment == null ? const Text('Select department first') : null,
                  // Rebuild items based on current _selectedSchool
                  items: (_selectedSchool != null && coursesMap.containsKey(_selectedSchool)) // Use coursesMap linked to SCHOOL
                      ? coursesMap[_selectedSchool]!.map((String course) {
                          return DropdownMenuItem<String>(value: course, child: Text(course, overflow: TextOverflow.ellipsis));
                        }).toList()
                      : [],
                  onChanged: (_selectedSchool == null || _selectedDepartment == null || !coursesMap.containsKey(_selectedSchool)) ? null : (String? newValue) {
                    // Use mounted check before calling setState
                    if (mounted) {
                      setState(() {
                        _selectedCourse = newValue;
                      });
                    }
                  },
                  validator: (value) => _selectedDepartment != null && value == null ? 'Please select your course' : null,
                  isExpanded: true,
                ),
                const SizedBox(height: 30),

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
                        onPressed: _handleRegister,
                        child: const Text('Register'),
                      ),
                const SizedBox(height: 15),

                // Login Link
                TextButton(
                  onPressed: _isLoading ? null : () { // Disable while loading
                    // Navigate to LoginScreen, replacing the current route
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (context) => const LoginScreen()),
                    );
                  },
                  style: TextButton.styleFrom(foregroundColor: brandColor),
                  child: const Text("Already have an account? Login here"),
                ),
                const SizedBox(height: 20),
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
      barrierDismissible: false, // Prevent dismissing easily
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
          content: const Text('A verification email has been sent.\nPlease check your inbox (and spam folder) and click the link to verify your account before logging in.'),
          actions: <Widget>[
            TextButton(
              style: TextButton.styleFrom(foregroundColor: brandColor),
              child: const Text('OK', style: TextStyle(fontWeight: FontWeight.bold)),
              // --- CORRECTED NAVIGATION LOGIC ---
              onPressed: () {
                // 1. Close the success dialog
                Navigator.of(context).pop();
                // 2. Always navigate to LoginScreen, replacing the current route
                //    Use pushReplacement to prevent user from going back to RegisterScreen
                Navigator.pushReplacement(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              },
              // --- END CORRECTION ---
            ),
          ],
        );
      },
    );
  }
}
