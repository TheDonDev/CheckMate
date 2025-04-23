// lib/widgets/edit_lecture_dialog.dart
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/services/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:checkmate/constants/dropdown_data.dart';

class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}

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

  String? _selectedYear;
  String? _selectedSemester;
  String? _selectedVenue;
  late DateTime _selectedDate;
  late TimeOfDay _selectedStartTime; // Keep as TimeOfDay for picker state
  late TimeOfDay _selectedEndTime;   // Keep as TimeOfDay for picker state

  static const Color brandColor = Color(0xFF0175C2);

  @override
  void initState() {
    super.initState();

    _unitNameController = TextEditingController(text: widget.lecture.unitName);
    _unitCodeController = TextEditingController(text: widget.lecture.unitCode);

    _selectedYear = yearsList.contains(widget.lecture.yearOfStudy) ? widget.lecture.yearOfStudy : null;
    _selectedSemester = semestersList.contains(widget.lecture.semester) ? widget.lecture.semester : null;
    _selectedVenue = venuesList.contains(widget.lecture.venue) ? widget.lecture.venue : null;

    _selectedDate = widget.lecture.lectureDate ?? DateTime.now();
    _selectedStartTime = widget.lecture.startTime != null
        ? TimeOfDay.fromDateTime(widget.lecture.startTime!.toLocal())
        : TimeOfDay.now();
    _selectedEndTime = widget.lecture.endTime != null
        ? TimeOfDay.fromDateTime(widget.lecture.endTime!.toLocal())
        : TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));
  }

  @override
  void dispose() {
    _unitNameController.dispose();
    _unitCodeController.dispose();
    super.dispose();
  }

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

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme( data: ThemeData.light().copyWith( colorScheme: const ColorScheme.light( primary: brandColor, onPrimary: Colors.white, ), textButtonTheme: TextButtonThemeData( style: TextButton.styleFrom(foregroundColor: brandColor), ), ), child: child!, );
      },
    );
    if (picked != null && picked != _selectedDate) {
      setState(() { _selectedDate = picked; });
    }
  }

  Future<void> _selectTime(BuildContext context, bool isStartTime) async {
    final TimeOfDay? picked = await showTimePicker(
      context: context,
      initialTime: isStartTime ? _selectedStartTime : _selectedEndTime,
      builder: (context, child) {
        return Theme( data: ThemeData.light().copyWith( colorScheme: const ColorScheme.light( primary: brandColor, onPrimary: Colors.white, ), textButtonTheme: TextButtonThemeData( style: TextButton.styleFrom(foregroundColor: brandColor), ), ), child: child!, );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _selectedStartTime = picked;
          if (_selectedEndTime != null) {
             final startMinutes = _selectedStartTime.hour * 60 + _selectedStartTime.minute;
             final endMinutes = _selectedEndTime!.hour * 60 + _selectedEndTime!.minute;
             if(endMinutes <= startMinutes) { _selectedEndTime = TimeOfDay(hour: startMinutes ~/ 60, minute: (startMinutes % 60) + 1); }
          }
        } else {
          _selectedEndTime = picked;
        }
      });
    }
  }

  Future<void> _updateLecture() async {
    if (!_formKey.currentState!.validate()) {
      _showValidationError('Please fill in all required fields correctly.');
      return;
    }
    if (_selectedDate == null || _selectedStartTime == null || _selectedEndTime == null || _selectedYear == null || _selectedSemester == null || _selectedVenue == null) {
       _showValidationError('Please fill in all required fields, including schedule and venue.'); return;
    }

    final DateTime startDateTime = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _selectedStartTime.hour, _selectedStartTime.minute,
    );
    final DateTime endDateTime = DateTime(
      _selectedDate.year, _selectedDate.month, _selectedDate.day,
      _selectedEndTime.hour, _selectedEndTime.minute,
    );

    if (!endDateTime.isAfter(startDateTime)) {
      _showValidationError('End time must be after start time.');
      return;
    }

    setState(() => _isLoading = true);

    final Map<String, dynamic> updatedData = {
      'unitName': _unitNameController.text.trim(),
      'unitCode': _unitCodeController.text.trim().toUpperCase(),
      'venue': _selectedVenue,
      'yearOfStudy': _selectedYear,
      'semester': _selectedSemester,
      'lectureDate': DateFormat('yyyy-MM-dd').format(_selectedDate),
      'startTime': startDateTime.toUtc().toIso8601String(),
      'endTime': endDateTime.toUtc().toIso8601String(),
      'course': widget.lecture.course,
    };

    try {
      await apiService.updateLecture(widget.lecture.id, updatedData);
      if (mounted) { Navigator.of(context).pop(true); }
    // --- MODIFIED CATCH BLOCK ---
    } catch (e, stackTrace) { // Add stackTrace parameter
      // Log detailed error information to the console
      print("--- Update Lecture Error ---");
      print("Error Type: ${e.runtimeType}");
      print("Error Details: $e");
      // If it's an ApiException, print the status code too
      if (e is ApiException) {
        print("API Status Code: ${e.statusCode}");
      }
      print("StackTrace: $stackTrace");
      print("--- End Update Lecture Error ---");

      // Show error message to the user (try to use specific message if available)
      if (mounted) {
        String displayMessage = 'An unexpected error occurred.';
        if (e is ApiException) {
          displayMessage = e.message; // Use the message from ApiException
        } else {
          displayMessage = e.toString(); // Fallback for other error types
        }
        _showValidationError('Failed to update lecture: $displayMessage');
      }
    // --- END MODIFIED CATCH BLOCK ---
    } finally {
      if (mounted) { setState(() => _isLoading = false); }
    }
  }

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
                InputDecorator(
                  decoration: _inputDecoration('Course', isRequired: false).copyWith(
                    fillColor: Colors.grey[200],
                    prefixIcon: Icon(Icons.book_outlined, color: brandColor.withOpacity(0.7)),
                  ),
                  child: Text(widget.lecture.course ?? 'N/A', style: const TextStyle(fontSize: 16)),
                ),
                const SizedBox(height: 12),
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
                DropdownButtonFormField<String>(
                  decoration: _inputDecoration('Venue', prefixIcon: const Icon(Icons.location_on_outlined)),
                  value: _selectedVenue,
                  items: venuesList.map((String value) => DropdownMenuItem<String>(value: value, child: Text(value))).toList(),
                  onChanged: (val) => setState(() => _selectedVenue = val),
                  validator: (value) => value == null ? 'Venue is required' : null,
                  isExpanded: true,
                ),
                const SizedBox(height: 15),
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
              ],
            ),
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
      actions: <Widget>[
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
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
          onPressed: _isLoading ? null : _updateLecture,
        ),
      ],
    );
  }
}
