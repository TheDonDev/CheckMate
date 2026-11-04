// import 'dart:convert'; // Import for jsonEncode
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/services/admin_service.dart';
import 'package:checkmate/services/api_service.dart'; // Import ApiService
// import 'package:checkmate/widgets/document_name_widget.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'dart:async'; // Needed for TimeoutException

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

class EditLectureDialog extends StatefulWidget {
  final Lecture lecture;

  const EditLectureDialog({super.key, required this.lecture});

  @override
  State<EditLectureDialog> createState() => _EditLectureDialogState();
}

class _EditLectureDialogState extends State<EditLectureDialog> {
  final _formKey = GlobalKey<FormState>();
  final ApiService apiService = ApiService();
  final AdminService _adminService = AdminService();
  bool _isLoading = false;

  late TextEditingController _unitNameController;
  late TextEditingController _unitCodeController;
  late TextEditingController _onlineLinkController;

  String? _selectedSchoolId;
  String? _selectedDepartmentId;
  String? _selectedCourseId;
  String? _selectedYearId;
  String? _selectedSemesterId;
  String? _selectedVenueId;
  String? _selectedVenueName; // To check for "ONLINE"
  late DateTime _selectedDate;
  late TimeOfDay _selectedStartTime; //  TimeOfDay for picker state
  late TimeOfDay _selectedEndTime;

  static const Color brandColor = Color(0xFF0175C2);

  @override
  void initState() {
    super.initState();

    _unitNameController = TextEditingController(text: widget.lecture.unitName);
    _unitCodeController = TextEditingController(text: widget.lecture.unitCode);
    _onlineLinkController = TextEditingController(text: widget.lecture.onlineLink ?? '');

    _selectedSchoolId = widget.lecture.school;
    _selectedDepartmentId = widget.lecture.department;
    _selectedCourseId = widget.lecture.course;
    _selectedYearId = widget.lecture.yearOfStudy;
    _selectedSemesterId = widget.lecture.semester;
    _selectedVenueId = widget.lecture.venue;

    // Ensure date/time are initialized correctly from the lecture object
    _selectedDate = widget.lecture.lectureDate?.toLocal() ?? DateTime.now(); // Use local time for display
    _selectedStartTime = widget.lecture.startTime != null
        ? TimeOfDay.fromDateTime(widget.lecture.startTime!.toLocal())
        : TimeOfDay.now();
    _selectedEndTime = widget.lecture.endTime != null
        ? TimeOfDay.fromDateTime(widget.lecture.endTime!.toLocal())
        : TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));

    if (kDebugMode) {
      print("[EditDialog Init] Initial Start Time (Local): $_selectedStartTime");
      print("[EditDialog Init] Initial End Time (Local): $_selectedEndTime");
      print("[EditDialog Init] Initial Date (Local): $_selectedDate");
    }

    // Pre-fetch the initial venue name to correctly show/hide the online link field on load
    if (_selectedVenueId != null) {
      _adminService.getVenues().first.then((snapshot) {
        final venueDocs = snapshot.docs.where((doc) => doc.id == _selectedVenueId);
        if (venueDocs.isNotEmpty && mounted) {
          final venueDoc = venueDocs.first;
          setState(() => _selectedVenueName = (venueDoc.data() as Map<String, dynamic>)['name']);
        }
      });
    }
  }

  @override
  void dispose() {
    _unitNameController.dispose();
    _unitCodeController.dispose();
    _onlineLinkController.dispose();
    super.dispose();
  }

  // Helper for consistent InputDecoration styling
  InputDecoration _inputDecoration(String label, {String? hint, Widget? prefixIcon, bool isRequired = true}) {
     return InputDecoration(
      labelText: '$label${isRequired ? " *" : ""}',
      hintText: hint,
      prefixIcon: prefixIcon != null
          ? IconTheme(
              data: IconThemeData(color: brandColor.withOpacity(0.7)),
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
        borderSide: const BorderSide(color: brandColor, width: 1.5),
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

  // Method to show the date picker
  Future<void> _selectDate(BuildContext context) async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate.isBefore(today) ? today : _selectedDate, // Start from today if current date is past
      firstDate: today, // Prevent selecting past dates
      lastDate: today.add(const Duration(days: 365)), // Allow up to one year in the future
      helpText: 'Select New Lecture Date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: brandColor,
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
      setState(() {
        _selectedDate = picked;
        if (kDebugMode) print("[EditDialog] Date Selected (Local): $_selectedDate");
      });
    }
  }

  // Method to show the time picker
  Future<void> _selectTime(BuildContext context, bool isStartTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStartTime ? _selectedStartTime : _selectedEndTime,
      helpText: isStartTime ? 'Select New Start Time' : 'Select New End Time',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: brandColor,
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
          if (kDebugMode) print("[EditDialog] Start Time Selected (Local): $_selectedStartTime");
          // Reset end time if it becomes invalid
           final startMinutes = _selectedStartTime.hour * 60 + _selectedStartTime.minute;
           final endMinutes = _selectedEndTime.hour * 60 + _selectedEndTime.minute;
           if(endMinutes <= startMinutes) {
              // Calculate end time ensuring it wraps around midnight correctly if needed
              final newEndMinute = (startMinutes + 60) % (24 * 60); // 60 minutes, wrap around 24 hours
              _selectedEndTime = TimeOfDay(hour: newEndMinute ~/ 60, minute: newEndMinute % 60);
              if (kDebugMode) print("[EditDialog] End Time Auto-Adjusted (Local): $_selectedEndTime");
           }
        } else {
          _selectedEndTime = picked;
          if (kDebugMode) print("[EditDialog] End Time Selected (Local): $_selectedEndTime");
        }
      });
      // Re-validate the form to check time order immediately after selection
      _formKey.currentState?.validate();
    }
  }

  // Method to handle form submission for update
  Future<void> _updateLecture() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorDialog('Validation Error', 'Please fill in all required fields correctly.');
      return;
    }

    if (_selectedSchoolId == null || _selectedDepartmentId == null || _selectedCourseId == null || _selectedYearId == null || _selectedSemesterId == null || _selectedVenueId == null) {
       _showErrorDialog('Validation Error', 'Please fill in all required fields, including schedule and venue.'); return;
    }

    // 1. Combine selected date and time into a local DateTime object.
    final DateTime localStartDateTime = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _selectedStartTime.hour, _selectedStartTime.minute,
    );
    final DateTime localEndDateTime = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _selectedEndTime.hour, _selectedEndTime.minute,
    );
    // 2. Convert the local DateTime to UTC for storage and API calls.
    final DateTime startDateTime = localStartDateTime.toUtc();
    final DateTime endDateTime = localEndDateTime.toUtc();
    if (kDebugMode) {
      print("[EditDialog Update] Combined Start DateTime (Local): ${startDateTime.toIso8601String()}");
      print("[EditDialog Update] Combined End DateTime (Local): ${endDateTime.toIso8601String()}");
    }

    // Validate time order (using local times is fine here)
    if (!endDateTime.isAfter(startDateTime)) {
      _showErrorDialog('Validation Error', 'End time must be after start time.');
      return;
    }

    // Handle online link based on venue
    String? onlineLinkValue = _selectedVenueName?.toUpperCase() == 'ONLINE' ? _onlineLinkController.text.trim() : null;
    // Additional validation for online link if venue is ONLINE
    if (_selectedVenueName?.toUpperCase() == 'ONLINE' && (onlineLinkValue == null || onlineLinkValue.isEmpty)) {
       _showErrorDialog('Validation Error', 'Online link is required for ONLINE venue.'); return;
    }
    if (_selectedVenueName?.toUpperCase() == 'ONLINE' && onlineLinkValue != null) {
        final uri = Uri.tryParse(onlineLinkValue);
        if (uri == null || !uri.hasAbsolutePath || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
           _showErrorDialog('Validation Error', 'Please enter a valid URL for the online link (e.g., https://...).'); return;
        }
    }


    setState(() => _isLoading = true);

    // Prepare the data payload for the API
    final Map<String, dynamic> updatedData = {
      'unitName': _unitNameController.text.trim(),
      'unitCode': _unitCodeController.text.trim().toUpperCase(),
      'school': _selectedSchoolId,
      'department': _selectedDepartmentId,
      'course': _selectedCourseId,
      'venue': _selectedVenueId,
      'yearOfStudy': _selectedYearId,
      'semester': _selectedSemesterId,
      // Send dates/times in ISO 8601 format with offset.
      'lectureDate': DateFormat('yyyy-MM-dd').format(localStartDateTime), 
      'startTime': startDateTime.toIso8601String(), 
      'endTime': endDateTime.toIso8601String(),     
      'onlineLink': onlineLinkValue,
    };

    // ***  Log data being sent ***
    if (kDebugMode) {
      print("[EditDialog Update] Sending update data to API: $updatedData");
    }
    // *** END LOGGING ***

    try {
      await apiService.updateLecture(widget.lecture.id, updatedData);
      if (mounted) { Navigator.of(context).pop(true); } // Success, return true
    } catch (e, stackTrace) {
      print("--- Update Lecture Error ---");
      print("Error Type: ${e.runtimeType}");
      print("Error Details: $e");
      if (e is ApiException) { print("API Status Code: ${e.statusCode}"); }
      print("StackTrace: $stackTrace");
      print("--- End Update Lecture Error ---");

      if (mounted) {
        String displayMessage = (e is ApiException) ? e.message : "An unexpected error occurred during update.";
        _showErrorDialog('Update Failed', displayMessage);
      }
    } finally {
      if (mounted) { setState(() => _isLoading = false); }
    }
  }

  // Helper to show validation error snackbar
  void _showErrorDialog(String title, String content) {
     if (!mounted) return;
     showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Row(
              children: [
                Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error),
                const SizedBox(width: 10),
                Text(title),
              ],
            ),
            content: Text(content),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      title: const Row(
        children: [
          Icon(Icons.edit_note, color: brandColor),
          SizedBox(width: 10),
          Text('Edit Lecture'),
        ],
      ),
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
                // --- Unit Name ---
                TextFormField(
                  controller: _unitNameController,
                  decoration: _inputDecoration('Unit Name', prefixIcon: const Icon(Icons.label_outline)),
                  inputFormatters: [ UpperCaseTextFormatter(), ],
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Unit name is required' : null,
                ),
                const SizedBox(height: 12),

                // --- Unit Code ---
                TextFormField(
                  controller: _unitCodeController,
                  decoration: _inputDecoration(
                    'Unit Code',
                    hint: 'E.g., COM 123',
                    prefixIcon: const Icon(Icons.code_outlined)
                  ),
                  inputFormatters: [
                    UpperCaseTextFormatter(),
                    FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9 ]')),
                  ],
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Unit code is required';
                    }
                    final trimmedValue = value.trim();
                    final RegExp unitCodeFormat = RegExp(r'^[A-Z]{2,4} \d{3,}$');
                    if (!unitCodeFormat.hasMatch(trimmedValue)) {
                      return 'Format must be like "COM 123"';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),

                // --- School, Department, Course Dropdowns ---
                StreamBuilder<LocalQuerySnapshot>(
                  stream: _adminService.getSchools(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    var schools = snapshot.data!.docs;
                    return DropdownButtonFormField<String>(
                      decoration: _inputDecoration('School', prefixIcon: const Icon(Icons.school_outlined)),
                      value: schools.any((doc) => doc.id == _selectedSchoolId) ? _selectedSchoolId : null,
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
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      var departments = snapshot.data!.docs;
                      return DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Department', prefixIcon: const Icon(Icons.business_outlined)),
                        value: departments.any((doc) => doc.id == _selectedDepartmentId) ? _selectedDepartmentId : null,
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
                      if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                      var courses = snapshot.data!.docs;
                      return DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Course', prefixIcon: const Icon(Icons.book_outlined)),
                        value: courses.any((doc) => doc.id == _selectedCourseId) ? _selectedCourseId : null,
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

                // --- Year & Semester Dropdowns ---
                 Row(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Expanded(
                       child: StreamBuilder<LocalQuerySnapshot>(
                         stream: _adminService.getYearsOfStudy(),
                         builder: (context, snapshot) {
                           if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                           var years = snapshot.data!.docs;
                           return DropdownButtonFormField<String>(
                             decoration: _inputDecoration('Year', prefixIcon: const Icon(Icons.calendar_view_day_outlined)),
                             value: years.any((doc) => doc.id == _selectedYearId) ? _selectedYearId : null,
                             items: years.map((year) {
                               final data = year.data() as Map<String, dynamic>;
                               return DropdownMenuItem<String>(value: year.id, child: Text(data['name'].toUpperCase()));
                             }).toList(),
                             onChanged: (String? newValue) { setState(() { _selectedYearId = newValue; }); },
                             validator: (value) => value == null ? 'Required' : null,
                             isExpanded: true,
                           );
                         },
                       ),
                     ),
                     const SizedBox(width: 10),
                     Expanded(
                       child: StreamBuilder<LocalQuerySnapshot>(
                         stream: _adminService.getSemesters(),
                         builder: (context, snapshot) {
                           if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                           var semesters = snapshot.data!.docs;
                           return DropdownButtonFormField<String>(
                             decoration: _inputDecoration('Semester', prefixIcon: const Icon(Icons.filter_list_alt)),
                             value: semesters.any((doc) => doc.id == _selectedSemesterId) ? _selectedSemesterId : null,
                             items: semesters.map((semester) {
                               final data = semester.data() as Map<String, dynamic>;
                               return DropdownMenuItem<String>(value: semester.id, child: Text(data['name'].toUpperCase()));
                             }).toList(),
                             onChanged: (String? newValue) { setState(() { _selectedSemesterId = newValue; }); },
                             validator: (value) => value == null ? 'Required' : null,
                             isExpanded: true,
                           );
                         },
                       ),
                     ),
                   ],
                 ),
                const SizedBox(height: 12),

                // --- Venue Dropdown ---
                StreamBuilder<LocalQuerySnapshot>(
                  stream: _adminService.getVenues(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                    var venues = snapshot.data!.docs;
                    return DropdownButtonFormField<String>(
                      decoration: _inputDecoration('Venue', prefixIcon: const Icon(Icons.location_on_outlined)),
                      value: venues.any((doc) => doc.id == _selectedVenueId) ? _selectedVenueId : null,
                      items: venues.map((venue) {
                        final data = venue.data() as Map<String, dynamic>;
                        return DropdownMenuItem<String>(value: venue.id, child: Text(data['name'] ?? ''));
                      }).toList(),
                      onChanged: (val) {
                        setState(() {
                          _selectedVenueId = val;
                          // Find the name corresponding to the selected ID
                          final selectedDoc = venues.where((doc) => doc.id == val).isNotEmpty
                              ? venues.firstWhere((doc) => doc.id == val)
                              : null;
                          _selectedVenueName = selectedDoc != null ? (selectedDoc.data() as Map<String, dynamic>)['name'] : null;
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
                      // Only validate if the venue is actually ONLINE
                      // This validation runs only when the field is visible.
                      // The visibility is controlled by `_selectedVenueName`.
                      if (_selectedVenueName?.toUpperCase() == 'ONLINE') {
                        if (value == null || value.trim().isEmpty) {
                          return 'Online link is required for ONLINE venue';
                        }
                        // Basic URL validation
                        final uri = Uri.tryParse(value.trim());
                        if (uri == null || !uri.hasAbsolutePath || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
                           return 'Please enter a valid URL (e.g., https://...)';
                        }
                      }
                      return null; // No error if venue is not ONLINE
                    },
                  ),
                ],
               

                const SizedBox(height: 15), // Spacing before schedule

                // --- Date/Time Pickers ---
                Text("Lecture Schedule *", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _selectDate(context),
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: _inputDecoration('Date', prefixIcon: const Icon(Icons.calendar_today_outlined), isRequired: true),
                    child: Text(DateFormat.yMMMEd().format(_selectedDate), style: const TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectTime(context, true),
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: _inputDecoration('Start Time', prefixIcon: const Icon(Icons.access_time_outlined), isRequired: true),
                          child: Text(_selectedStartTime.format(context), style: const TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectTime(context, false),
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: _inputDecoration('End Time', prefixIcon: const Icon(Icons.update_outlined), isRequired: true),
                          child: Text(_selectedEndTime.format(context), style: const TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                  ],
                ),
                // --- End Date/Time Pickers ---
              ],
            ),
          ),
        ),
      ),
      // --- Dialog Actions ---
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      actions: <Widget>[
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false), // Cancel
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: _isLoading ? Container() : const Icon(Icons.save_alt_outlined, size: 18),
          label: _isLoading
              ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Update'),
          style: ElevatedButton.styleFrom(
            backgroundColor: brandColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          onPressed: _isLoading ? null : _updateLecture, // Submit
        ),
      ],
      // --- End Dialog Actions ---
    );
  }
}
