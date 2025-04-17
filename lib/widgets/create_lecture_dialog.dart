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

  final _lecturerPhoneController = TextEditingController();
  final _unitNameController = TextEditingController();
  final _unitCodeController = TextEditingController();

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
    // Pre-fill known lecturer details if possible (optional)
    // _lecturerPhoneController.text = widget.currentUser.phone ?? ''; // Assuming phone is available
    _updateDependentDropdowns(); // Initialize based on potentially pre-selected school
  }


  @override
  void dispose() {
    _lecturerPhoneController.dispose();
    _unitNameController.dispose();
    _unitCodeController.dispose();
    super.dispose();
  }

  // Helper for consistent InputDecoration
  InputDecoration _inputDecoration(String label, {String? hint, Widget? prefixIcon, bool isRequired = true}) {
    return InputDecoration(
      labelText: '$label${isRequired ? " *" : ""}',
      hintText: hint,
      prefixIcon: prefixIcon != null
          ? IconTheme(
              data: IconThemeData(color: CreateLectureDialog.brandColor.withOpacity(0.7)),
              child: prefixIcon,
            )
          : null,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: CreateLectureDialog.brandColor, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.grey[100],
      contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
    );
  }

  // Helper to update dependent dropdown lists based on selected school
  void _updateDependentDropdowns() {
    _currentDepartments = (_selectedSchool != null && departmentsMap.containsKey(_selectedSchool))
        ? departmentsMap[_selectedSchool]!
        : [];
    _currentCourses = (_selectedSchool != null && coursesMap.containsKey(_selectedSchool))
        ? coursesMap[_selectedSchool]!
        : [];

    // Ensure selected department/course are still valid if school changes
    if (_selectedDepartment != null && !_currentDepartments.contains(_selectedDepartment)) {
      _selectedDepartment = null;
    }
    if (_selectedCourse != null && !_currentCourses.contains(_selectedCourse)) {
      _selectedCourse = null;
    }
  }

   Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select Lecture Date',
      builder: (context, child) {
        return Theme(
          // Apply brand color to date picker
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: CreateLectureDialog.brandColor,
                  onPrimary: Colors.white, // Text on primary color
                  surface: Colors.white, // Background
                  onSurface: Colors.black87, // Text color
                ),
             dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() { _selectedDate = picked; });
    }
  }

  Future<void> _pickTime(bool isStartTime) async {
    final TimeOfDay initialTime = isStartTime
        ? (_selectedStartTime ?? TimeOfDay.now())
        : (_selectedEndTime ?? TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))));

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: isStartTime ? 'Select Start Time' : 'Select End Time',
       builder: (context, child) {
        return Theme(
          // Apply brand color to time picker
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: CreateLectureDialog.brandColor,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black87,
                ),
             timePickerTheme: TimePickerThemeData(
               // Customize picker theme further if needed
               // dialHandColor: CreateLectureDialog.brandColor,
               // hourMinuteTextColor: MaterialStateColor.resolveWith((states) => states.contains(MaterialState.selected) ? Colors.white : CreateLectureDialog.brandColor),
             ),
             dialogBackgroundColor: Colors.white,
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _selectedStartTime = picked;
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

  Future<void> _submitForm() async {
    if (_formKey.currentState!.validate()) {
      if (_selectedDate == null || _selectedStartTime == null || _selectedEndTime == null) {
         _showValidationError('Please select date and times.'); return;
      }
      final DateTime startDateTime = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedStartTime!.hour, _selectedStartTime!.minute);
      final DateTime endDateTime = DateTime(_selectedDate!.year, _selectedDate!.month, _selectedDate!.day, _selectedEndTime!.hour, _selectedEndTime!.minute);
      if (!endDateTime.isAfter(startDateTime)) {
         _showValidationError('End time must be after start time.'); return;
      }

      setState(() => _isLoading = true);

      final newLecture = Lecture(
        id: '', lecturerId: widget.currentUser.id, lecturerName: widget.currentUser.name,
        lecturerPhone: _lecturerPhoneController.text.trim(),
        school: _selectedSchool!, department: _selectedDepartment!, course: _selectedCourse!,
        yearOfStudy: _selectedYear!, semester: _selectedSemester!,
        unitName: _unitNameController.text.trim(), unitCode: _unitCodeController.text.trim(),
        lectureDate: _selectedDate!, startTime: Timestamp.fromDate(startDateTime), endTime: Timestamp.fromDate(endDateTime),
        venue: _selectedVenue!, createdAt: DateTime.now(),
      );

      try {
        await _apiService.createLecture(newLecture);
        if (!mounted) return;
        Navigator.of(context).pop(true); // Pop with true on success
        // Show success snackbar on the dashboard screen (after dialog closes)
        // ScaffoldMessenger.of(context).showSnackBar(...); // This won't work well here
      } catch (e) {
         if (!mounted) return;
         _showValidationError('Failed to create lecture: ${e.toString()}');
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
       _showValidationError('Please fill in all required fields correctly.');
    }
  }

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
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Padding( // Add padding around form content
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // Display lecturer name prominently
                InputDecorator(
                  decoration: _inputDecoration('Lecturer', isRequired: false).copyWith(
                    fillColor: Colors.grey[200], // Disabled look
                    prefixIcon: Icon(Icons.person_outline, color: CreateLectureDialog.brandColor.withOpacity(0.7)),
                  ),
                  child: Text(widget.currentUser.name, style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 15),

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
                  onChanged: _currentDepartments.isEmpty ? null : (String? newValue) {
                    setState(() { _selectedDepartment = newValue; _selectedCourse = null; _updateDependentDropdowns(); });
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

                TextFormField(
                  controller: _unitNameController,
                  decoration: _inputDecoration('Unit Name', prefixIcon: const Icon(Icons.label_outline)),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Unit name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _unitCodeController,
                  decoration: _inputDecoration('Unit Code', prefixIcon: const Icon(Icons.code_outlined)),
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Unit code is required' : null,
                ),
                const SizedBox(height: 15),

                // --- Date/Time Pickers ---
                Text("Lecture Schedule *", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                // Date Picker Tile
                InkWell( // Use InkWell for tap effect
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: _inputDecoration('Date', prefixIcon: const Icon(Icons.calendar_today_outlined), isRequired: true).copyWith(
                      // Display selected date or placeholder
                      hintText: _selectedDate == null ? 'Select Date' : null,
                    ),
                    child: _selectedDate == null
                        ? null // Show label/hint from decoration
                        : Text(DateFormat.yMMMEd().format(_selectedDate!), style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 10),
                // Time Picker Tiles (Row)
                 Row(
                   children: [
                     Expanded(
                       child: InkWell(
                         onTap: () => _pickTime(true),
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
                     const SizedBox(width: 10),
                     Expanded(
                       child: InkWell(
                         onTap: () => _pickTime(false),
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
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      actions: <Widget>[
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: _isLoading
              ? Container() // Hide icon when loading
              : const Icon(Icons.check_circle_outline, size: 20),
          label: _isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Create Lecture'),
          onPressed: _isLoading ? null : _submitForm,
          style: ElevatedButton.styleFrom( // Apply brand color
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
