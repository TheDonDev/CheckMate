// lib/widgets/create_lecture_dialog.dart
import 'package:checkmate/constants/dropdown_data.dart';
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/services/api_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CreateLectureDialog extends StatefulWidget {
  final app_user.User currentUser;

  // Define the brand color (consistent styling)
  static const Color brandColor = Color(0xFF0175C2);

  const CreateLectureDialog({super.key, required this.currentUser});

  @override
  State<CreateLectureDialog> createState() => _CreateLectureDialogState();
}

class _CreateLectureDialogState extends State<CreateLectureDialog> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();

  // Text editing controllers
  final _lecturerPhoneController = TextEditingController();
  final _unitNameController = TextEditingController();
  final _unitCodeController = TextEditingController();

  // State variables for dropdowns and pickers
  String? _selectedSchool;
  String? _selectedDepartment;
  String? _selectedCourse;
  String? _selectedYear;
  String? _selectedSemester;
  String? _selectedVenue;
  DateTime? _selectedDate;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;

  bool _isLoading = false;

  // Local lists for dependent dropdowns
  List<String> _currentDepartments = [];
  List<String> _currentCourses = [];

  @override
  void initState() {
    super.initState();
    // Pre-fill lecturer's school if available from user data (optional, depends on your User model)
    // _selectedSchool = widget.currentUser.school; // Example if school is part of User model
    _updateDependentDropdowns(); // Initialize based on potentially pre-selected school
  }


  @override
  void dispose() {
    // Dispose controllers to free up resources
    _lecturerPhoneController.dispose();
    _unitNameController.dispose();
    _unitCodeController.dispose();
    super.dispose();
  }

  // Helper for consistent InputDecoration styling
  InputDecoration _inputDecoration(String label, {String? hint, Widget? prefixIcon, bool isRequired = true}) {
    return InputDecoration(
      labelText: '$label${isRequired ? " *" : ""}', // Add asterisk for required fields
      hintText: hint,
      prefixIcon: prefixIcon != null
          ? IconTheme( // Apply theme color to prefix icon
              data: IconThemeData(color: CreateLectureDialog.brandColor.withOpacity(0.7)),
              child: prefixIcon,
            )
          : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder( // Highlight border with brand color when focused
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CreateLectureDialog.brandColor, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.grey[100], // Subtle background fill
      contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
    );
  }

  // Helper to update dependent dropdown lists (Department, Course) based on selected school
  void _updateDependentDropdowns() {
    // Get departments for the selected school from the constant map
    _currentDepartments = (_selectedSchool != null && departmentsMap.containsKey(_selectedSchool))
        ? departmentsMap[_selectedSchool]!
        : [];
    // Get courses for the selected school from the constant map
    _currentCourses = (_selectedSchool != null && coursesMap.containsKey(_selectedSchool))
        ? coursesMap[_selectedSchool]!
        : [];

    // Reset selected department/course if they are no longer valid for the new school
    if (_selectedDepartment != null && !_currentDepartments.contains(_selectedDepartment)) {
      _selectedDepartment = null;
    }
    if (_selectedCourse != null && !_currentCourses.contains(_selectedCourse)) {
      _selectedCourse = null;
    }
  }

  // Method to show the date picker
   Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)), // Allow yesterday for flexibility
      lastDate: DateTime.now().add(const Duration(days: 365)), // Allow up to one year ahead
      helpText: 'Select Lecture Date',
      builder: (context, child) {
        // Apply custom theme to the date picker
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: CreateLectureDialog.brandColor, // Brand color for selection
                  onPrimary: Colors.white, // Text on selection
                  surface: Colors.white, // Background
                  onSurface: Colors.black87, // Text color
                ), dialogTheme: DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    );
    // Update state if a date was picked
    if (picked != null && picked != _selectedDate) {
      setState(() { _selectedDate = picked; });
    }
  }

  // Method to show the time picker
  Future<void> _pickTime(bool isStartTime) async {
    // Set initial time for the picker
    final TimeOfDay initialTime = isStartTime
        ? (_selectedStartTime ?? TimeOfDay.now())
        : (_selectedEndTime ?? TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))));

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: isStartTime ? 'Select Start Time' : 'Select End Time',
       builder: (context, child) {
        // Apply custom theme to the time picker
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: CreateLectureDialog.brandColor, // Brand color for selection
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black87,
                ),
             timePickerTheme: TimePickerThemeData( // Optional: Further theme customization
               // dialHandColor: CreateLectureDialog.brandColor,
             ), dialogTheme: DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    );
    // Update state if a time was picked
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _selectedStartTime = picked;
          // Optional: Auto-clear end time if it's now before the start time
          if (_selectedEndTime != null) {
             final startDateTime = DateTime(1, 1, 1, _selectedStartTime!.hour, _selectedStartTime!.minute);
             final endDateTime = DateTime(1, 1, 1, _selectedEndTime!.hour, _selectedEndTime!.minute);
             if(endDateTime.isBefore(startDateTime)) { _selectedEndTime = null; }
          }
        } else {
          _selectedEndTime = picked;
        }
      });
    }
  }

  // Method to handle form submission
  Future<void> _submitForm() async {
    // Validate the form fields
    if (_formKey.currentState!.validate()) {
      // Perform additional validation for date/time pickers
      if (_selectedDate == null || _selectedStartTime == null || _selectedEndTime == null) {
         _showValidationError('Please select lecture date, start time, and end time.'); return;
      }
      // Combine date and time
      final DateTime startDateTime = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedStartTime!.hour, _selectedStartTime!.minute);
      final DateTime endDateTime = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedEndTime!.hour, _selectedEndTime!.minute);
      // Validate end time is after start time
      if (!endDateTime.isAfter(startDateTime)) {
         _showValidationError('End time must be after start time.'); return;
      }

      // Set loading state
      setState(() => _isLoading = true);

      // --- Verification Check ---
      // NOTE: As requested, we are *not* adding a frontend verification check here.
      // The check to allow 'muhambe@au.ac.ke' or enforce verification for others
      // MUST be implemented in your Node.js backend API endpoint for security.
      // If a frontend check were needed (less secure), it would look like:
      // if (widget.currentUser.email != 'muhambe@au.ac.ke' && !widget.currentUser.isVerified) {
      //    _showValidationError('Your account must be verified to create lectures.');
      //    setState(() => _isLoading = false);
      //    return;
      // }
      // --- End Verification Check Note ---


      // Validate that all required fields are filled
      if (_selectedSchool == null || _selectedDepartment == null || _selectedCourse == null || _selectedYear == null || _selectedSemester == null || _selectedVenue == null) {
        _showValidationError('Please fill in all required fields.');
        return;
      }

      // Create Lecture object
      final newLecture = Lecture(
        id: '', // ID will be generated by Firestore
        lecturerId: widget.currentUser.id,
        lecturerName: widget.currentUser.name,
        lecturerPhone: _lecturerPhoneController.text.trim(),
        school: _selectedSchool!,
        department: _selectedDepartment!,
        course: _selectedCourse!,
        yearOfStudy: _selectedYear!,
        semester: _selectedSemester!,
        unitName: _unitNameController.text.trim(),
        unitCode: _unitCodeController.text.trim(),
        lectureDate: _selectedDate!,
        startTime: Timestamp.fromDate(startDateTime), // Convert to Firestore Timestamp
        endTime: Timestamp.fromDate(endDateTime),   // Convert to Firestore Timestamp
        venue: _selectedVenue!,
        createdAt: DateTime.now(), // Record creation time
      );

      try {
        // Call the API service to create the lecture in the backend
        await _apiService.createLecture(newLecture);
        if (!mounted) return; // Check mount status after async gap
        Navigator.of(context).pop(true); // Pop dialog with 'true' on success
      } catch (e) {
         if (!mounted) return; // Check mount status after async gap
         _showValidationError('Failed to create lecture: ${e.toString()}');
      } finally {
        // Reset loading state if widget is still mounted
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
       // Show validation error if form is invalid
       _showValidationError('Please fill in all required fields correctly.');
    }
  }

  // Helper to show validation error snackbar
  void _showValidationError(String message) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(message),
         backgroundColor: Theme.of(context).colorScheme.error, // Use theme error color
         behavior: SnackBarBehavior.floating, // Consistent behavior
       ),
     );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // Rounded corners
      title: const Text('Create New Lecture'),
      scrollable: true, // Allow content to scroll if it overflows
      content: SingleChildScrollView( // Ensure content scrolls if needed
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min, // Take minimum space needed
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Display lecturer name (read-only)
                InputDecorator(
                  decoration: _inputDecoration('Lecturer', isRequired: false).copyWith(
                    fillColor: Colors.grey[200], // Disabled look
                    prefixIcon: Icon(Icons.person_outline, color: CreateLectureDialog.brandColor.withOpacity(0.7)),
                  ),
                  child: Text(widget.currentUser.name, style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 15),

                // Lecturer Phone
                TextFormField(
                  controller: _lecturerPhoneController,
                  decoration: _inputDecoration('Your Phone Number', prefixIcon: const Icon(Icons.phone_outlined)),
                  keyboardType: TextInputType.phone,
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Phone number is required' : null,
                ),
                const SizedBox(height: 12),

                // --- Dropdowns using _inputDecoration ---
                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('School', prefixIcon: const Icon(Icons.school_outlined)),
                  value: _selectedSchool,
                  items: schoolsList.map((String school) => DropdownMenuItem<String>(value: school, child: Text(school, overflow: TextOverflow.ellipsis))).toList(),
                  onChanged: (String? newValue) {
                    // Update state and dependent dropdowns when school changes
                    setState(() {
                      _selectedSchool = newValue; _selectedDepartment = null; _selectedCourse = null;
                      _updateDependentDropdowns();
                    });
                  },
                  validator: (value) => value == null ? 'School is required' : null,
                  isExpanded: true,
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Department', hint: _selectedSchool == null ? 'Select school first' : null, prefixIcon: const Icon(Icons.business_outlined)),
                  value: _selectedDepartment,
                  items: _currentDepartments.map((String department) => DropdownMenuItem<String>(value: department, child: Text(department, overflow: TextOverflow.ellipsis))).toList(),
                  // Disable if no school is selected or no departments available
                  onChanged: _currentDepartments.isEmpty ? null : (String? newValue) {
                    setState(() { _selectedDepartment = newValue; _selectedCourse = null; });
                  },
                  validator: (value) => _selectedSchool != null && value == null ? 'Department is required' : null,
                  isExpanded: true,
                  disabledHint: const Text('Select school first'),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Course', hint: _selectedSchool == null ? 'Select school first' : null, prefixIcon: const Icon(Icons.book_outlined)),
                  value: _selectedCourse,
                  items: _currentCourses.map((String course) => DropdownMenuItem<String>(value: course, child: Text(course, overflow: TextOverflow.ellipsis))).toList(),
                  // Disable if no school is selected or no courses available
                  onChanged: _currentCourses.isEmpty ? null : (String? newValue) { setState(() { _selectedCourse = newValue; }); },
                  validator: (value) => _selectedSchool != null && value == null ? 'Course is required' : null,
                  isExpanded: true,
                  disabledHint: const Text('Select school first'),
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Year of Study', prefixIcon: const Icon(Icons.calendar_view_day_outlined)),
                  value: _selectedYear,
                  items: yearsList.map((String year) => DropdownMenuItem<String>(value: year, child: Text(year))).toList(),
                  onChanged: (String? newValue) { setState(() { _selectedYear = newValue; }); },
                  validator: (value) => value == null ? 'Year of study is required' : null,
                  isExpanded: true,
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Semester', prefixIcon: const Icon(Icons.filter_list_alt)),
                  value: _selectedSemester,
                  items: semestersList.map((String semester) => DropdownMenuItem<String>(value: semester, child: Text(semester))).toList(),
                  onChanged: (String? newValue) { setState(() { _selectedSemester = newValue; }); },
                  validator: (value) => value == null ? 'Semester is required' : null,
                  isExpanded: true,
                ),
                const SizedBox(height: 12),

                // Unit Name
                TextFormField(
                  controller: _unitNameController,
                  decoration: _inputDecoration('Unit Name', prefixIcon: const Icon(Icons.label_outline)),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Unit name is required' : null,
                ),
                const SizedBox(height: 12),
                // Unit Code
                TextFormField(
                  controller: _unitCodeController,
                  decoration: _inputDecoration('Unit Code', prefixIcon: const Icon(Icons.code_outlined)),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Unit code is required' : null,
                ),
                const SizedBox(height: 15),

                // --- Date/Time Pickers ---
                Text("Lecture Schedule *", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // Date Picker Tile (using InkWell + InputDecorator for consistent look)
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: _inputDecoration('Date', prefixIcon: const Icon(Icons.calendar_today_outlined), isRequired: true).copyWith(
                      hintText: _selectedDate == null ? 'Select Date' : null, // Show hint only if null
                    ),
                    // Display formatted date or nothing (let hint show)
                    child: _selectedDate == null
                        ? null
                        : Text(DateFormat.yMMMEd().format(_selectedDate!), style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 10),
                // Time Picker Tiles (Start and End in a Row)
                 Row(
                   children: [
                     Expanded(
                       child: InkWell(
                         onTap: () => _pickTime(true), // Pick start time
                         borderRadius: BorderRadius.circular(12),
                         child: InputDecorator(
                           decoration: _inputDecoration('Start Time', prefixIcon: const Icon(Icons.access_time_outlined), isRequired: true).copyWith(
                             hintText: _selectedStartTime == null ? 'Select Start' : null,
                           ),
                           child: _selectedStartTime == null
                               ? null
                               : Text(_selectedStartTime!.format(context), style: const TextStyle(fontSize: 16)),
                         ),
                       ),
                     ),
                     const SizedBox(width: 10), // Spacing between time pickers
                     Expanded(
                       child: InkWell(
                         onTap: () => _pickTime(false), // Pick end time
                         borderRadius: BorderRadius.circular(12),
                         child: InputDecorator(
                           decoration: _inputDecoration('End Time', prefixIcon: const Icon(Icons.update_outlined), isRequired: true).copyWith(
                             hintText: _selectedEndTime == null ? 'Select End' : null,
                           ),
                           child: _selectedEndTime == null
                               ? null
                               : Text(_selectedEndTime!.format(context), style: const TextStyle(fontSize: 16)),
                         ),
                       ),
                     ),
                   ],
                 ),
                 const SizedBox(height: 12),

                // Venue Dropdown
                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Venue', prefixIcon: const Icon(Icons.location_on_outlined)),
                  value: _selectedVenue,
                  items: venuesList.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                  onChanged: (val) => setState(() => _selectedVenue = val),
                  validator: (value) => value == null ? 'Venue is required' : null,
                  isExpanded: true,
                ),
              ],
            ),
          ),
        ),
      ),
      // Dialog Actions (Buttons)
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      actions: <Widget>[
        // Cancel Button
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false), // Pop with false on cancel
          child: const Text('Cancel'),
        ),
        // Create Button (Primary Action)
        ElevatedButton.icon(
          // Show loading indicator instead of icon when loading
          icon: _isLoading
              ? Container()
              : const Icon(Icons.check_circle_outline, size: 20),
          // Show loading indicator or text based on loading state
          label: _isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Create Lecture'),
          // Disable button when loading, otherwise call submit function
          onPressed: _isLoading ? null : _submitForm,
          style: ElevatedButton.styleFrom( // Apply brand color style
            backgroundColor: CreateLectureDialog.brandColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // Pill shape
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
        ),
      ],
    );
  }
}
