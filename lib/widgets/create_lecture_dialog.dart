// lib/widgets/create_lecture_dialog.dart
import 'package:checkmate/constants/dropdown_data.dart'; // Import constants
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/services/api_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class CreateLectureDialog extends StatefulWidget {
  final app_user.User currentUser;

  const CreateLectureDialog({super.key, required this.currentUser});

  @override
  State<CreateLectureDialog> createState() => _CreateLectureDialogState();
}

class _CreateLectureDialogState extends State<CreateLectureDialog> {
  final _formKey = GlobalKey<FormState>();
  final _apiService = ApiService();

  // Form Controllers
  final _lecturerPhoneController = TextEditingController();
  final _unitNameController = TextEditingController();
  final _unitCodeController = TextEditingController();

  // Selectable Values State
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

  @override
  void dispose() {
    _lecturerPhoneController.dispose();
    _unitNameController.dispose();
    _unitCodeController.dispose();
    super.dispose();
  }

  // --- Date/Time Pickers remain the same ---
   Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)), // Allow today
      lastDate: DateTime.now().add(const Duration(days: 365)), // Limit to one year ahead
      helpText: 'Select Lecture Date',
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: Theme.of(context).primaryColor, // Use app's primary color
                ),
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
          data: Theme.of(context).copyWith(
             timePickerTheme: TimePickerThemeData(
               // Optional: Customize picker theme
             ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      setState(() {
        if (isStartTime) {
          _selectedStartTime = picked;
          // Optional: Auto-adjust end time if start time changes and end time is before it
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
   // --- Form Submission ---
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
        id: '',
        lecturerId: widget.currentUser.id,
        lecturerName: widget.currentUser.name,
        lecturerPhone: _lecturerPhoneController.text,
        school: _selectedSchool!,
        department: _selectedDepartment!,
        course: _selectedCourse!,
        yearOfStudy: _selectedYear!,
        semester: _selectedSemester!,
        unitName: _unitNameController.text,
        unitCode: _unitCodeController.text,
        lectureDate: _selectedDate!,
        startTime: Timestamp.fromDate(startDateTime),
        endTime: Timestamp.fromDate(endDateTime),
        venue: _selectedVenue!,
        createdAt: DateTime.now(),
      );

      try {
        final createdLecture = await _apiService.createLecture(newLecture);
        if (!mounted) return;
        print("Lecture created via API: ${createdLecture.id}");
        // *** Pop with true on success ***
        Navigator.of(context).pop(true);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lecture created successfully!'), duration: Duration(seconds: 2)),
        );
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
       SnackBar(content: Text(message), backgroundColor: Colors.redAccent),
     );
  }

  @override
  Widget build(BuildContext context) {
    // Use constant maps for dynamic lists
    List<String> currentDepartments = (_selectedSchool != null && departmentsMap.containsKey(_selectedSchool))
        ? departmentsMap[_selectedSchool]!
        : [];
    List<String> currentCourses = (_selectedSchool != null && coursesMap.containsKey(_selectedSchool))
        ? coursesMap[_selectedSchool]!
        : [];

    return AlertDialog(
      title: const Text('Create New Lecture'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text("Lecturer: ${widget.currentUser.name}", style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 15),

              TextFormField(
                controller: _lecturerPhoneController,
                decoration: const InputDecoration(labelText: 'Your Phone Number', border: OutlineInputBorder(), prefixIcon: Icon(Icons.phone)),
                keyboardType: TextInputType.phone,
                validator: (value) => value == null || value.isEmpty ? 'Phone number is required' : null,
              ),
              const SizedBox(height: 12),

              // --- Use Constant Lists/Maps for Dropdowns ---
              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'School', border: OutlineInputBorder(), prefixIcon: Icon(Icons.school)),
                value: _selectedSchool,
                // Use constant list
                items: schoolsList.map((String school) {
                  return DropdownMenuItem<String>(value: school, child: Text(school, overflow: TextOverflow.ellipsis));
                }).toList(),
                onChanged: (String? newValue) {
                  setState(() {
                    _selectedSchool = newValue;
                    _selectedDepartment = null; // Reset dependent dropdowns
                    _selectedCourse = null;
                    // Update local lists using constant maps
                    currentDepartments = (_selectedSchool != null && departmentsMap.containsKey(_selectedSchool)) ? departmentsMap[_selectedSchool]! : [];
                    currentCourses = (_selectedSchool != null && coursesMap.containsKey(_selectedSchool)) ? coursesMap[_selectedSchool]! : [];
                  });
                },
                validator: (value) => value == null ? 'School is required' : null,
                isExpanded: true,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'Department', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.business), hintText: _selectedSchool == null ? 'Select a school first' : null),
                value: _selectedDepartment,
                // Use local list derived from constant map
                items: currentDepartments.isNotEmpty
                    ? currentDepartments.map((String department) {
                        return DropdownMenuItem<String>(value: department, child: Text(department, overflow: TextOverflow.ellipsis));
                      }).toList()
                    : [],
                onChanged: currentDepartments.isEmpty ? null : (String? newValue) {
                  setState(() {
                    _selectedDepartment = newValue;
                    _selectedCourse = null; // Reset course
                    // Update course list (though already handled by school change, good practice)
                     currentCourses = (_selectedSchool != null && coursesMap.containsKey(_selectedSchool)) ? coursesMap[_selectedSchool]! : [];
                  });
                },
                validator: (value) => _selectedSchool != null && value == null ? 'Department is required' : null,
                isExpanded: true,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'Course', border: const OutlineInputBorder(), prefixIcon: const Icon(Icons.book), hintText: _selectedSchool == null ? 'Select a school first' : null),
                value: _selectedCourse,
                // Use local list derived from constant map
                items: currentCourses.isNotEmpty
                    ? currentCourses.map((String course) {
                        return DropdownMenuItem<String>(value: course, child: Text(course, overflow: TextOverflow.ellipsis));
                      }).toList()
                    : [],
                onChanged: currentCourses.isEmpty ? null : (String? newValue) {
                  setState(() { _selectedCourse = newValue; });
                },
                validator: (value) => _selectedSchool != null && value == null ? 'Course is required' : null,
                isExpanded: true,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Year of Study', border: OutlineInputBorder(), prefixIcon: Icon(Icons.calendar_view_day)),
                value: _selectedYear,
                // Use constant list
                items: yearsList.map((String year) {
                  return DropdownMenuItem<String>(value: year, child: Text(year));
                }).toList(),
                onChanged: (String? newValue) { setState(() { _selectedYear = newValue; }); },
                validator: (value) => value == null ? 'Year of study is required' : null,
                isExpanded: true,
              ),
              const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Semester', border: OutlineInputBorder(), prefixIcon: Icon(Icons.filter_1)),
                value: _selectedSemester,
                // Use constant list
                items: semestersList.map((String semester) {
                  return DropdownMenuItem<String>(value: semester, child: Text(semester));
                }).toList(),
                onChanged: (String? newValue) { setState(() { _selectedSemester = newValue; }); },
                validator: (value) => value == null ? 'Semester is required' : null,
                isExpanded: true,
              ),
              const SizedBox(height: 12),

              TextFormField(
                controller: _unitNameController,
                decoration: const InputDecoration(labelText: 'Unit Name', border: OutlineInputBorder(), prefixIcon: Icon(Icons.label)),
                validator: (value) => value == null || value.isEmpty ? 'Unit name is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _unitCodeController,
                decoration: const InputDecoration(labelText: 'Unit Code', border: OutlineInputBorder(), prefixIcon: Icon(Icons.code)),
                validator: (value) => value == null || value.isEmpty ? 'Unit code is required' : null,
              ),
              const SizedBox(height: 15),

              const Text("Lecture Schedule", style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ListTile(
                leading: const Icon(Icons.calendar_today),
                title: Text(_selectedDate == null ? 'Select Date *' : 'Date: ${DateFormat.yMMMEd().format(_selectedDate!)}'),
                trailing: const Icon(Icons.arrow_drop_down),
                onTap: _pickDate,
                dense: true,
                shape: RoundedRectangleBorder(side: BorderSide(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(4)),
              ),
              const SizedBox(height: 10),
               Row(
                 children: [
                   Expanded(child: ListTile(leading: const Icon(Icons.access_time), title: Text(_selectedStartTime == null ? 'Start Time *' : 'Start: ${_selectedStartTime!.format(context)}'), trailing: const Icon(Icons.arrow_drop_down), onTap: () => _pickTime(true), dense: true, shape: RoundedRectangleBorder(side: BorderSide(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(4)))),
                   const SizedBox(width: 10),
                   Expanded(child: ListTile(leading: const Icon(Icons.access_time_filled), title: Text(_selectedEndTime == null ? 'End Time *' : 'End: ${_selectedEndTime!.format(context)}'), trailing: const Icon(Icons.arrow_drop_down), onTap: () => _pickTime(false), dense: true, shape: RoundedRectangleBorder(side: BorderSide(color: Theme.of(context).dividerColor), borderRadius: BorderRadius.circular(4)))),
                 ],
               ),
               const SizedBox(height: 12),

              DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Venue', border: OutlineInputBorder(), prefixIcon: Icon(Icons.location_on)),
                value: _selectedVenue,
                // Use constant list
                items: venuesList.map((String value) {
                  return DropdownMenuItem<String>(value: value, child: Text(value));
                }).toList(),
                onChanged: (val) => setState(() => _selectedVenue = val),
                validator: (value) => value == null ? 'Venue is required' : null,
                isExpanded: true,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          // Pop with false or null on cancel
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        ElevatedButton.icon(
          icon: _isLoading ? Container() : const Icon(Icons.check_circle_outline),
          label: _isLoading ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Create Lecture'),
          onPressed: _isLoading ? null : _submitForm,
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12)),
        ),
      ],
    );
  }
}
