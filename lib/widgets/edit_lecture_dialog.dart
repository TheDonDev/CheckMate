// lib/widgets/edit_lecture_dialog.dart
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/services/api_service.dart'; // Import ApiService
import 'package:flutter/foundation.dart'; // For kDebugMode
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:checkmate/constants/dropdown_data.dart';
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
  bool _isLoading = false;

  late TextEditingController _unitNameController;
  late TextEditingController _unitCodeController;
  late TextEditingController _onlineLinkController;

  String? _selectedYear;
  String? _selectedSemester;
  String? _selectedVenue;
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

    _selectedYear = yearsList.contains(widget.lecture.yearOfStudy) ? widget.lecture.yearOfStudy : null;
    _selectedSemester = semestersList.contains(widget.lecture.semester) ? widget.lecture.semester : null;
    _selectedVenue = venuesList.contains(widget.lecture.venue) ? widget.lecture.venue : null;

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
      _showValidationError('Please fill in all required fields correctly.');
      return;
    }

    if (_selectedYear == null || _selectedSemester == null || _selectedVenue == null) {
       _showValidationError('Please fill in all required fields, including schedule and venue.'); return;
    }

    // *** Use local DateTime constructor ***
    final DateTime startDateTime = DateTime( // Use local constructor
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _selectedStartTime.hour, _selectedStartTime.minute,
    );
    final DateTime endDateTime = DateTime( // Use local constructor
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _selectedEndTime.hour, _selectedEndTime.minute,
    );

    if (kDebugMode) {
      print("[EditDialog Update] Combined Start DateTime (Local): ${startDateTime.toIso8601String()}");
      print("[EditDialog Update] Combined End DateTime (Local): ${endDateTime.toIso8601String()}");
    }

    // Validate time order (using local times is fine here)
    if (!endDateTime.isAfter(startDateTime)) {
      _showValidationError('End time must be after start time.');
      return;
    }

    // Handle online link based on venue
    String? onlineLinkValue = _selectedVenue == 'ONLINE' ? _onlineLinkController.text.trim() : null;
    // Additional validation for online link if venue is ONLINE
    if (_selectedVenue == 'ONLINE' && (onlineLinkValue == null || onlineLinkValue.isEmpty)) {
       _showValidationError('Online link is required for ONLINE venue.'); return;
    }
    if (_selectedVenue == 'ONLINE' && onlineLinkValue != null) {
        final uri = Uri.tryParse(onlineLinkValue);
        if (uri == null || !uri.hasAbsolutePath || !uri.hasScheme || !(uri.isScheme('http') || uri.isScheme('https'))) {
           _showValidationError('Please enter a valid URL for the online link (e.g., https://...).'); return;
        }
    }


    setState(() => _isLoading = true);

    // Prepare the data payload for the API
    final Map<String, dynamic> updatedData = {
      'unitName': _unitNameController.text.trim(),
      'unitCode': _unitCodeController.text.trim().toUpperCase(),
      'venue': _selectedVenue,
      'yearOfStudy': _selectedYear,
      'semester': _selectedSemester,
      // Send dates/times in ISO 8601 format with offset.
      'lectureDate': DateFormat('yyyy-MM-dd').format(_selectedDate), 
      'startTime': startDateTime.toIso8601String(), // Includes offset
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
        _showValidationError('Failed to update lecture: $displayMessage');
      }
    } finally {
      if (mounted) { setState(() => _isLoading = false); }
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

                // --- Course (Read-Only) ---
                InputDecorator(
                  decoration: _inputDecoration('Course', isRequired: false).copyWith(
                    fillColor: Colors.grey[200],
                    prefixIcon: Icon(Icons.book_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  child: Text(widget.lecture.course ?? 'N/A', style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 12),

                // --- Year & Semester Dropdowns ---
                 Row(
                   crossAxisAlignment: CrossAxisAlignment.start,
                   children: [
                     Expanded(
                       child: DropdownButtonFormField<String>(
                         decoration: _inputDecoration('Year', prefixIcon: const Icon(Icons.calendar_view_day_outlined)),
                         value: _selectedYear,
                         items: yearsList.map((String year) => DropdownMenuItem<String>(value: year, child: Text(year))).toList(),
                         onChanged: (String? newValue) { setState(() { _selectedYear = newValue; }); },
                         validator: (value) => value == null ? 'Required' : null,
                         isExpanded: true,
                       ),
                     ),
                     const SizedBox(width: 10),
                     Expanded(
                       child: DropdownButtonFormField<String>(
                         decoration: _inputDecoration('Semester', prefixIcon: const Icon(Icons.filter_list_alt)),
                         value: _selectedSemester,
                         items: semestersList.map((String semester) => DropdownMenuItem<String>(value: semester, child: Text(semester))).toList(),
                         onChanged: (String? newValue) { setState(() { _selectedSemester = newValue; }); },
                         validator: (value) => value == null ? 'Required' : null,
                         isExpanded: true,
                       ),
                     ),
                   ],
                 ),
                const SizedBox(height: 12),

                // --- Venue Dropdown ---
                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Venue', prefixIcon: const Icon(Icons.location_on_outlined)),
                  value: _selectedVenue,
                  items: venuesList.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                  onChanged: (val) => setState(() => _selectedVenue = val),
                  validator: (value) => value == null ? 'Venue is required' : null,
                  isExpanded: true,
                ),
                // --- END Venue Dropdown ---

                // --- Conditional Online Link Field ---
                if (_selectedVenue == 'ONLINE') ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _onlineLinkController,
                    decoration: _inputDecoration(
                      'Online Lecture Link',
                      prefixIcon: const Icon(Icons.link_outlined),
                      isRequired: true, // Required only when venue is ONLINE
                      hint: 'e.g., https://meet.google.com/abc-xyz'
                    ),
                    keyboardType: TextInputType.url,
                    validator: (value) {
                      // Only validate if the venue is actually ONLINE
                      if (_selectedVenue == 'ONLINE') {
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
                    decoration: _inputDecoration('Date', prefixIcon: const Icon(Icons.calendar_today_outlined), isRequired: true).copyWith(
                      hintText: _selectedDate == null ? 'Select Date' : null,
                    ),
                    child: _selectedDate == null
                        ? null
                        : Text(DateFormat.yMMMEd().format(_selectedDate), style: const TextStyle(fontSize: 16)),
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
                          decoration: _inputDecoration('Start Time', prefixIcon: const Icon(Icons.access_time_outlined), isRequired: true).copyWith(
                            hintText: _selectedStartTime == null ? 'Select Start' : null,
                          ),
                          child: _selectedStartTime == null
                              ? null
                              : Text(_selectedStartTime.format(context), style: const TextStyle(fontSize: 16)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: InkWell(
                        onTap: () => _selectTime(context, false),
                        borderRadius: BorderRadius.circular(12),
                        child: InputDecorator(
                          decoration: _inputDecoration('End Time', prefixIcon: const Icon(Icons.update_outlined), isRequired: true).copyWith(
                            hintText: _selectedEndTime == null ? 'Select End' : null,
                          ),
                          child: _selectedEndTime == null
                              ? null
                              : Text(_selectedEndTime.format(context), style: const TextStyle(fontSize: 16)),
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
