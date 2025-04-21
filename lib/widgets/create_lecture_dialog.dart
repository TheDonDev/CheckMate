// lib/widgets/create_lecture_dialog.dart
import 'package:checkmate/constants/dropdown_data.dart'; // Keep for Year, Semester, Venue
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// --- Custom Input Formatter to force uppercase input ---
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

  // Define the brand color
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
  String? _selectedYear;
  String? _selectedSemester;
  String? _selectedVenue;
  DateTime? _selectedDate;
  TimeOfDay? _selectedStartTime;
  TimeOfDay? _selectedEndTime;

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill lecturer's phone if available
    // Assuming currentUser.phoneNumber is non-nullable String based on usage.
    // If it CAN be null, you'd need: widget.currentUser.phoneNumber ?? ''
    _lecturerPhoneController.text = widget.currentUser.phoneNumber;
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
      fillColor: Colors.grey[100], // Subtle background fill
      contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
      errorStyle: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error),
    );
  }

  // Method to show the date picker
  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
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

  // Method to show the time picker
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
    // Validate the form fields (excluding the now read-only School/Dept/Course)
    if (_formKey.currentState!.validate()) {
      // Perform additional validation for date/time pickers and other required fields
      if (_selectedDate == null || _selectedStartTime == null || _selectedEndTime == null || _selectedYear == null || _selectedSemester == null || _selectedVenue == null) {
         _showValidationError('Please fill in all required fields, including schedule and venue.'); return;
      }
      // Combine date and time into DateTime objects
      final DateTime startDateTime = DateTime(
          _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
          _selectedStartTime!.hour, _selectedStartTime!.minute
      );
      final DateTime endDateTime = DateTime(
          _selectedDate!.year, _selectedDate!.month, _selectedDate!.day,
          _selectedEndTime!.hour, _selectedEndTime!.minute
      );
      // Validate end time is after start time
      if (!endDateTime.isAfter(startDateTime)) {
         _showValidationError('End time must be after start time.'); return;
      }

      // Set loading state
      setState(() => _isLoading = true);

      // Create Lecture object using data from currentUser for restricted fields
      final newLecture = Lecture(
        id: '', // ID will be generated by backend/Firestore
        lecturerId: widget.currentUser.id,
        lecturerName: widget.currentUser.name,
        lecturerPhone: _lecturerPhoneController.text.trim().isEmpty ? null : _lecturerPhoneController.text.trim(),
        // *** FIX: Use null-coalescing operator (??) to provide a default value ***
        school: widget.currentUser.school ?? 'N/A', // Provide default if null
        department: widget.currentUser.department ?? 'N/A', // Provide default if null
        course: widget.currentUser.course ?? 'N/A', // Provide default if null
        // *** End restricted fields ***
        yearOfStudy: _selectedYear!,
        semester: _selectedSemester!,
        unitName: _unitNameController.text.trim(),
        unitCode: _unitCodeController.text.trim(),
        lectureDate: _selectedDate,
        startTime: startDateTime,
        endTime: endDateTime,
        venue: _selectedVenue!,
        createdAt: null, // Let backend/server set the creation timestamp
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
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    } else {
       _showValidationError('Please fill in all required fields correctly.');
    }
  }

  // Helper to show validation error snackbar
  void _showValidationError(String message) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(message),
         backgroundColor: Theme.of(context).colorScheme.error,
         behavior: SnackBarBehavior.floating,
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
         margin: const EdgeInsets.all(10),
       ),
     );
  }

  @override
  Widget build(BuildContext context) {
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
                // Display lecturer name (read-only)
                InputDecorator(
                  decoration: _inputDecoration('Lecturer', isRequired: false).copyWith(
                    fillColor: Colors.grey[200],
                    prefixIcon: Icon(Icons.person_outline, color: CreateLectureDialog.brandColor.withOpacity(0.7)),
                  ),
                  child: Text(widget.currentUser.name, style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 15),

                // Lecturer Phone (Pre-filled, optional validation)
                TextFormField(
                  controller: _lecturerPhoneController,
                  decoration: _inputDecoration('Your Phone Number', prefixIcon: const Icon(Icons.phone_outlined), isRequired: false),
                  keyboardType: TextInputType.phone,
                  // validator: (value) { ... } // Optional phone validation
                ),
                const SizedBox(height: 12),

                // --- MODIFIED: Display School (Read-Only) ---
                InputDecorator(
                  decoration: _inputDecoration('School', isRequired: false).copyWith(
                    fillColor: Colors.grey[200], // Disabled look
                    prefixIcon: Icon(Icons.school_outlined, color: CreateLectureDialog.brandColor.withOpacity(0.7)),
                  ),
                  // *** FIX: Use null-coalescing operator (??) for Text widget ***
                  child: Text(widget.currentUser.school ?? 'N/A', style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 12),

                // --- MODIFIED: Display Department (Read-Only) ---
                InputDecorator(
                  decoration: _inputDecoration('Department', isRequired: false).copyWith(
                    fillColor: Colors.grey[200], // Disabled look
                    prefixIcon: Icon(Icons.business_outlined, color: CreateLectureDialog.brandColor.withOpacity(0.7)),
                  ),
                  // *** FIX: Use null-coalescing operator (??) for Text widget ***
                  child: Text(widget.currentUser.department ?? 'N/A', style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 12),

                // --- MODIFIED: Display Course (Read-Only) ---
                InputDecorator(
                  decoration: _inputDecoration('Course', isRequired: false).copyWith(
                    fillColor: Colors.grey[200], // Disabled look
                    prefixIcon: Icon(Icons.book_outlined, color: CreateLectureDialog.brandColor.withOpacity(0.7)),
                  ),
                  // *** FIX: Use null-coalescing operator (??) for Text widget ***
                  child: Text(widget.currentUser.course ?? 'N/A', style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 12),
                // --- END MODIFIED Read-Only Fields ---

                // --- Dropdowns for Year, Semester, Venue (Unchanged) ---
                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Year of Study', prefixIcon: const Icon(Icons.calendar_view_day_outlined)),
                  value: _selectedYear,
                  // Assuming yearsList comes from dropdown_data.dart
                  items: yearsList.map((String year) => DropdownMenuItem<String>(value: year, child: Text(year))).toList(),
                  onChanged: (String? newValue) { setState(() { _selectedYear = newValue; }); },
                  validator: (value) => value == null ? 'Year of study is required' : null,
                  isExpanded: true,
                ),
                const SizedBox(height: 12),

                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Semester', prefixIcon: const Icon(Icons.filter_list_alt)),
                  value: _selectedSemester,
                  // Assuming semestersList comes from dropdown_data.dart
                  items: semestersList.map((String semester) => DropdownMenuItem<String>(value: semester, child: Text(semester))).toList(),
                  onChanged: (String? newValue) { setState(() { _selectedSemester = newValue; }); },
                  validator: (value) => value == null ? 'Semester is required' : null,
                  isExpanded: true,
                ),
                const SizedBox(height: 12),

                // --- Unit Name (Unchanged) ---
                TextFormField(
                  controller: _unitNameController,
                  decoration: _inputDecoration('Unit Name', prefixIcon: const Icon(Icons.label_outline)),
                  inputFormatters: [ UpperCaseTextFormatter(), ],
                  textCapitalization: TextCapitalization.characters,
                  validator: (value) => (value == null || value.trim().isEmpty) ? 'Unit name is required' : null,
                ),
                const SizedBox(height: 12),

                // --- Unit Code (Unchanged) ---
                TextFormField(
                  controller: _unitCodeController,
                  decoration: _inputDecoration(
                    'Unit Code',
                    hint: 'E.g., COM 123, IRD 100',
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
                    final RegExp unitCodeFormat = RegExp(r'^[A-Z]+ \d+$');
                    if (!unitCodeFormat.hasMatch(trimmedValue)) {
                      return 'Format must be like "COM 123"';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 15),

                // --- Date/Time Pickers (Unchanged) ---
                Text("Lecture Schedule *", style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                InkWell(
                  onTap: _pickDate,
                  borderRadius: BorderRadius.circular(12),
                  child: InputDecorator(
                    decoration: _inputDecoration('Date', prefixIcon: const Icon(Icons.calendar_today_outlined), isRequired: true).copyWith(
                      hintText: _selectedDate == null ? 'Select Date' : null,
                    ),
                    child: _selectedDate == null
                        ? null
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

                // Venue Dropdown (Unchanged)
                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Venue', prefixIcon: const Icon(Icons.location_on_outlined)),
                  value: _selectedVenue,
                  // Assuming venuesList comes from dropdown_data.dart
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
      // Dialog Actions (Unchanged)
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      actions: <Widget>[
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: _isLoading
              ? Container()
              : const Icon(Icons.check_circle_outline, size: 20),
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
