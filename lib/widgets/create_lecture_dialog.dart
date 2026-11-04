import 'dart:convert'; // Import for jsonEncode
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/services/api_service.dart';
import 'package:checkmate/services/admin_service.dart';
// import 'package:checkmate/widgets/document_name_widget.dart';
import 'package:flutter/foundation.dart'; // Import kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// --- UpperCaseTextFormatter ---
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
// --- End Formatter ---

class CreateLectureDialog extends StatefulWidget {
  final app_user.User currentUser;
  static const Color brandColor = Color(0xFF0175C2);
  const CreateLectureDialog({super.key, required this.currentUser});

  @override
  State<CreateLectureDialog> createState() => _CreateLectureDialogState();
}

class _CreateLectureDialogState extends State<CreateLectureDialog> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();
  final _adminService = AdminService();

  // Controllers
  final _lecturerPhoneController = TextEditingController();
  final _unitNameController = TextEditingController();
  final _unitCodeController = TextEditingController();
  final _onlineLinkController = TextEditingController();

  // State variables
  String? _selectedSchoolId;
  String? _selectedDepartmentId;
  String? _selectedCourseId;
  String? _selectedYearId;
  String? _selectedSemesterId;
  String? _selectedVenueId;
  String? _selectedVenueName; // To check for "ONLINE"
  DateTime? _selectedDate;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _lecturerPhoneController.text = widget.currentUser.phoneNumber;
    _selectedSchoolId = widget.currentUser.school;
  }

  @override
  void dispose() {
    _lecturerPhoneController.dispose();
    _unitNameController.dispose();
    _unitCodeController.dispose();
    _onlineLinkController.dispose();
    super.dispose();
  }

  InputDecoration _inputDecoration(String label, {String? hint, Widget? prefixIcon, bool isRequired = true}) {
     // ... (input decoration code remains the same) ...
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 1.0),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).colorScheme.error, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.grey[100],
      contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
      errorStyle: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
    );
  }

  Future<void> _pickDate() async {
     // ... (date picker code remains the same) ...
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? today,
      firstDate: today,
      lastDate: today.add(const Duration(days: 365)),
      helpText: 'Select Lecture Date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: CreateLectureDialog.brandColor,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black87,
                ), dialogTheme: DialogThemeData(backgroundColor: Colors.white),
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
     // ... (time picker code remains the same) ...
    final TimeOfDay initialTime = isStartTime
        ? (_selectedStartTime ?? TimeOfDay.now())
        : (_selectedEndTime ?? TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1))));

    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      helpText: isStartTime ? 'Select Start Time' : 'Select End Time',
       builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: CreateLectureDialog.brandColor,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black87,
                ),
             timePickerTheme: const TimePickerThemeData(),
             dialogTheme: DialogThemeData(backgroundColor: Colors.white),
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
             final startMinutes = _selectedStartTime!.hour * 60 + _selectedStartTime!.minute;
             final endMinutes = _selectedEndTime!.hour * 60 + _selectedEndTime!.minute;
             if(endMinutes <= startMinutes) {
                _selectedEndTime = null; // Reset end time if it's not after start time
             }
          }
        } else {
          _selectedEndTime = picked;
        }
      });
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
       _showErrorDialog('Validation Error', 'Please fill in all required fields correctly.');
       return;
    }

    if (_selectedDate == null || _selectedStartTime == null || _selectedEndTime == null || _selectedSchoolId == null || _selectedDepartmentId == null || _selectedCourseId == null || _selectedYearId == null || _selectedSemesterId == null || _selectedVenueId == null) {
       _showErrorDialog('Validation Error', 'Please fill in all required fields, including schedule and venue.'); return;
    }

    // 1. Combine selected date and time into a local DateTime object.
    final DateTime localStartDateTime = DateTime(
      _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
      _selectedStartTime!.hour, _selectedStartTime!.minute,
    );
    final DateTime localEndDateTime = DateTime(
      _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
      _selectedEndTime!.hour, _selectedEndTime!.minute,
    );
    // 2. Convert the local DateTime to UTC for storage and API calls.
    final DateTime startDateTime = localStartDateTime.toUtc();
    final DateTime endDateTime = localEndDateTime.toUtc();

    if (!endDateTime.isAfter(startDateTime)) {
       _showErrorDialog('Validation Error', 'End time must be after start time.'); return;
    }

    final DateTime today = DateTime(DateTime.now().year, DateTime.now().month, DateTime.now().day);
    if (_selectedDate!.isBefore(today)) {
        _showErrorDialog('Validation Error', 'Cannot create a lecture for a past date.'); return;
    }

    String? onlineLinkValue = _selectedVenueName?.toUpperCase() == 'ONLINE' ? _onlineLinkController.text.trim() : null;

    // Create the Lecture object
    final newLecture = Lecture(
      id: '', // ID will be generated by backend
      lecturerId: widget.currentUser.id,
      lecturerName: widget.currentUser.name,
      lecturerPhone: _lecturerPhoneController.text.trim().isEmpty ? null : _lecturerPhoneController.text.trim(),
      school: _selectedSchoolId!, 
      department: _selectedDepartmentId!, 
      course: _selectedCourseId!, 
      yearOfStudy: _selectedYearId!,
      semester: _selectedSemesterId!,
      unitName: _unitNameController.text.trim(),
      unitCode: _unitCodeController.text.trim(),
      // Pass DateTime objects directly; toApiJson should handle conversion
      lectureDate: _selectedDate,
      startTime: startDateTime,
      endTime: endDateTime,
      venue: _selectedVenueId!,
      onlineLink: onlineLinkValue,
      createdAt: null, // Will be set by backend
    );

    // --- *** ADDED LOGGING *** ---
    if (kDebugMode) {
      print('[CreateLectureDialog] Attempting to create lecture...');
      try {
        // Assuming Lecture model has a `toApiJson` method
        // Ensure `toApiJson` converts DateTime fields to ISO8601 strings:
        // e.g., 'startTime': startTime?.toIso8601String(),
        final jsonPayload = newLecture.toApiJson();
        print('[CreateLectureDialog] Lecture Data (JSON Payload): ${jsonEncode(jsonPayload)}');
      } catch (e) {
        print('[CreateLectureDialog] Error converting lecture to JSON for logging: $e');
        // Log the basic object if JSON conversion fails for logging
        print('[CreateLectureDialog] Lecture Data (Object): ${newLecture.toString()}');
      }
    }
    // --- *** END ADDED LOGGING *** ---

    setState(() => _isLoading = true);

    try {
      // Call the API service - it should handle sending the JSON payload
      await _apiService.createLecture(newLecture);
      if (!mounted) return;
      // Success: Pop dialog and return true
      Navigator.of(context).pop(true);
    } catch (e) {
       if (!mounted) return;
       // Handle API or other errors
       String errorMessage = 'Failed to create lecture.';
       if (e is ApiException) {
          errorMessage += ' ${e.message}'; // Use message from ApiException
          if (kDebugMode) print('[CreateLectureDialog] API Error: ${e.statusCode} - ${e.message}');
       } else {
          errorMessage += ' Please try again.'; // Generic message
          if (kDebugMode) print('[CreateLectureDialog] General Error: ${e.toString()}');
       }
       _showErrorDialog('Creation Failed', errorMessage);
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }


  void _showErrorDialog(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ... (build method UI remains the same) ...
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: const Text('Create New Lecture'),
      scrollable: true,
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                // --- Read-Only Fields ---
                InputDecorator(
                  decoration: _inputDecoration('Lecturer', isRequired: false).copyWith(
                    fillColor: Colors.grey[200],
                    prefixIcon: Icon(Icons.person_outline, color: CreateLectureDialog.brandColor.withOpacity(0.7)),
                  ),
                  child: Text(widget.currentUser.name, style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 15),
                TextFormField(
                  controller: _lecturerPhoneController,
                  decoration: _inputDecoration('Your Phone Number', prefixIcon: const Icon(Icons.phone_outlined), isRequired: false),
                  keyboardType: TextInputType.phone,
                  // Optional: Add validation for phone format if needed
                ),
                const SizedBox(height: 12),
                // --- End Read-Only Fields ---

                // --- Dropdowns ---
                StreamBuilder<LocalQuerySnapshot>(
                  stream: _adminService.getSchools(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Text('Error loading schools');
                    }
                    if (!snapshot.hasData) return const Text('No schools found');
                    var schools = snapshot.data!.docs;
                    return DropdownButtonFormField<String>(
                      decoration: _inputDecoration('School', prefixIcon: const Icon(Icons.school_outlined)),
                      value: _selectedSchoolId,
                      items: schools.map((school) {
                        final data = school.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(value: school.id, child: Text(data['name'].toUpperCase(), overflow: TextOverflow.ellipsis));
                      }).toList(),
                      onChanged: (String? newValue) {
                        setState(() {
                          _selectedSchoolId = newValue;
                          _selectedDepartmentId = null;
                          _selectedCourseId = null;
                        });
                      },
                      validator: (value) => value == null ? 'School is required' : null,
                      isExpanded: true,
                    );
                  },
                ),
                const SizedBox(height: 12),
                if (_selectedSchoolId != null)
                  StreamBuilder<LocalQuerySnapshot>(
                    stream: _adminService.getDepartments(_selectedSchoolId!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return const Text('Error loading departments');
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Text('No departments found for this school');
                      }
                      var departments = snapshot.data!.docs;
                      return DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Department', prefixIcon: const Icon(Icons.business_outlined)),
                        value: _selectedDepartmentId,
                        items: departments.map((department) {
                          final data = department.data() as Map<String, dynamic>;
                          return DropdownMenuItem<String>(value: department.id, child: Text(data['name'].toUpperCase(), overflow: TextOverflow.ellipsis));
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedDepartmentId = newValue;
                            _selectedCourseId = null;
                          });
                        },
                        validator: (value) => value == null ? 'Department is required' : null,
                        isExpanded: true,
                      );
                    },
                  ),
                const SizedBox(height: 12),
                if (_selectedDepartmentId != null)
                  StreamBuilder<LocalQuerySnapshot>(
                    stream: _adminService.getCourses(_selectedDepartmentId!),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snapshot.hasError) {
                        return const Text('Error loading courses');
                      }
                      if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                        return const Text('No courses found for this department');
                      }
                      var courses = snapshot.data!.docs;
                      return DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Course', prefixIcon: const Icon(Icons.book_outlined)),
                        value: _selectedCourseId,
                        items: courses.map((course) {
                          final data = course.data() as Map<String, dynamic>;
                          return DropdownMenuItem<String>(value: course.id, child: Text(data['name'].toUpperCase(), overflow: TextOverflow.ellipsis));
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            _selectedCourseId = newValue;
                          });
                        },
                        validator: (value) => value == null ? 'Course is required' : null,
                        isExpanded: true,
                      );
                    },
                  ),
                const SizedBox(height: 12),
                  StreamBuilder<LocalQuerySnapshot>(
                  stream: _adminService.getYearsOfStudy(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Text('Error loading years');
                    }
                    if (!snapshot.hasData) return const Text('No years found');
                    var years = snapshot.data!.docs;
                    return DropdownButtonFormField<String>(
                      decoration: _inputDecoration('Year of Study', prefixIcon: const Icon(Icons.calendar_view_day_outlined)),
                      value: _selectedYearId,
                      items: years.map((year) {
                        final data = year.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(value: year.id, child: Text(data['name'].toUpperCase()));
                      }).toList(),
                      onChanged: (String? newValue) { setState(() { _selectedYearId = newValue; }); },
                      validator: (value) => value == null ? 'Year of study is required' : null,
                      isExpanded: true,
                    );
                  },
                ),
                const SizedBox(height: 12),
                StreamBuilder<LocalQuerySnapshot>(
                  stream: _adminService.getSemesters(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Text('Error loading semesters');
                    }
                    if (!snapshot.hasData) return const Text('No semesters found');
                    var semesters = snapshot.data!.docs;
                    return DropdownButtonFormField<String>(
                      decoration: _inputDecoration('Semester', prefixIcon: const Icon(Icons.filter_list_alt)),
                      value: _selectedSemesterId,
                      items: semesters.map((semester) {
                        final data = semester.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(value: semester.id, child: Text(data['name'].toUpperCase()));
                      }).toList(),
                      onChanged: (String? newValue) { setState(() { _selectedSemesterId = newValue; }); },
                      validator: (value) => value == null ? 'Semester is required' : null,
                      isExpanded: true,
                    );
                  },
                ),
                const SizedBox(height: 12),
                // --- End Dropdowns ---

                // --- Unit Name & Code ---
                TextFormField(
                  controller: _unitNameController,
                  decoration: _inputDecoration('Unit Name', prefixIcon: const Icon(Icons.label_outline)),
                  inputFormatters: [ UpperCaseTextFormatter(), ],
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Unit name is required' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _unitCodeController,
                  decoration: _inputDecoration(
                    'Unit Code',
                    hint: 'E.g., COM 123, IRD 100',
                    prefixIcon: const Icon(Icons.code_outlined)
                  ),
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9 ]')), // Allow letters, numbers, space
                  ],
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Unit code is required';
                    }
                    final trimmedValue = value.trim();
                    // Relaxed format: Allow 2-4 letters, space, then numbers
                    final RegExp unitCodeFormat = RegExp(r'^[A-Z]{2,4} \d+$');
                    if (!unitCodeFormat.hasMatch(trimmedValue)) {
                      return 'Format must be like "COM 123"';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),
                // --- End Unit Name & Code ---

                // --- Date/Time Pickers ---
                Text("Lecture Schedule *", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: _inputDecoration('Date', prefixIcon: const Icon(Icons.calendar_today_outlined), isRequired: true).copyWith(
                      hintText: _selectedDate == null ? 'Select Date' : null,
                      // Show error state if validation fails but field is touched
                      errorText: _formKey.currentState?.validate() == false && _selectedDate == null ? 'Date is required' : null,
                    ),
                    child: _selectedDate == null
                        ? null // Show hint text from decoration
                        : Text(DateFormat.yMMMEd().format(_selectedDate!), style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 10),
                 Row(
                   children: [
                     Expanded(
                       child: InkWell(
                         onTap: () => _pickTime(true),
                         borderRadius: BorderRadius.circular(12),
                         child: InputDecorator(
                           decoration: _inputDecoration('Start Time', prefixIcon: const Icon(Icons.access_time_outlined), isRequired: true).copyWith(
                             hintText: _selectedStartTime == null ? 'Select Start' : null,
                             errorText: _formKey.currentState?.validate() == false && _selectedStartTime == null ? 'Required' : null,
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
                             errorText: _formKey.currentState?.validate() == false && _selectedEndTime == null ? 'Required' : null,
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
                 // --- End Date/Time Pickers ---

                // --- Venue Dropdown ---
                StreamBuilder<LocalQuerySnapshot>(
                  stream: _adminService.getVenues(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (snapshot.hasError) {
                      return const Text('Error loading venues');
                    }
                    if (!snapshot.hasData) return const Text('No venues found');
                    var venues = snapshot.data!.docs;
                    return DropdownButtonFormField<String>(
                      decoration: _inputDecoration('Venue', prefixIcon: const Icon(Icons.location_on_outlined)),
                      value: _selectedVenueId,
                      items: venues.map((venue) {
                        final data = venue.data() as Map<String, dynamic>;
                        // The value is the ID, the child is the Text widget with the name
                        return DropdownMenuItem<String>(value: venue.id, child: Text((data['name'] ?? '')));
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedVenueId = val;
                        // Find the name corresponding to the selected ID
                        final selectedDoc = venues.firstWhere(
                          (doc) => doc.id == val,
                        );
                        // If a doc is found, This correctly hides the online link field when a non-ONLINE venue is selected.
                        _selectedVenueName = selectedDoc.data() is Map<String, dynamic>
                            ? (selectedDoc.data() as Map<String, dynamic>)['name']
                            : null;
                        });
                      },
                      validator: (value) => value == null ? 'Venue is required' : null,
                      isExpanded: true,
                    );
                  },
                ),
                // --- END Venue Dropdown ---

                // --- Conditional Online Link Field ---
                if (_selectedVenueName?.toUpperCase() == 'ONLINE') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _onlineLinkController,
                    decoration: _inputDecoration(
                      'Online Lecture Link',
                      prefixIcon: const Icon(Icons.link_outlined),
                      isRequired: true,
                      hint: 'e.g., https://meet.google.com/abc-xyz'
                    ),
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      // This validation runs only when the field is visible.
                      // The visibility is controlled by `_selectedVenueId == 'ONLINE'`.
                      // So, we can safely assume the link is required here when the name is ONLINE.
                      if (_selectedVenueName?.toUpperCase() == 'ONLINE') {
                        if (value == null || value.trim().isEmpty) {
                          return 'Online link is required for ONLINE venue';
                        }
                        final uri = Uri.tryParse(value.trim());
                        if (uri == null || !uri.hasAbsolutePath || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
                           return 'Please enter a valid URL (e.g., https://...)';
                        }
                      }
                      return null;
                    },
                  ),
                ],
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
          icon: _isLoading ? Container() : const Icon(Icons.check_circle_outline, size: 20),
          label: _isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Create Lecture'),
          onPressed: _isLoading ? null : _submitForm,
          style: ElevatedButton.styleFrom(
            backgroundColor: CreateLectureDialog.brandColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
        ),
      ],
    );
  }
}
