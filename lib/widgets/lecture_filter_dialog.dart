// lib/widgets/lecture_filter_dialog.dart
import 'package:checkmate/constants/dropdown_data.dart';
import 'package:flutter/material.dart';

// Data class to hold filter values returned by the dialog
class LectureFilterData {
  final String? school;
  final String? department;
  final String? course;
  final String? year;
  final String? semester;

  LectureFilterData({
    this.school,
    this.department,
    this.course,
    this.year,
    this.semester,
  });
}

class LectureFilterDialog extends StatefulWidget {
  final LectureFilterData initialFilters;
  // Flag to control dialog behavior: true for initial mandatory selection, false for refinement
  final bool isInitialSelection;
  // Pass fixed student details for display/disabling if needed
  final String? fixedSchool;
  final String? fixedDepartment;
  final String? fixedCourse;

  const LectureFilterDialog({
    super.key,
    required this.initialFilters,
    this.isInitialSelection = false, // Default to refinement mode
    this.fixedSchool,
    this.fixedDepartment,
    this.fixedCourse,
  });

  @override
  State<LectureFilterDialog> createState() => _LectureFilterDialogState();
}

class _LectureFilterDialogState extends State<LectureFilterDialog> {
  // Form key for validation in initial selection mode
  final _formKey = GlobalKey<FormState>();

  // State variables for selected values within the dialog
  String? _selectedSchool;
  String? _selectedDepartment;
  String? _selectedCourse;
  String? _selectedYear;
  String? _selectedSemester;

  // Local lists for dependent dropdowns (only relevant if school/dept/course are changeable)
  List<String> _currentDepartments = [];
  List<String> _currentCourses = [];

  @override
  void initState() {
    super.initState();
    // Initialize state with passed-in initial values OR fixed values
    _selectedSchool = widget.fixedSchool ?? widget.initialFilters.school;
    _selectedDepartment = widget.fixedDepartment ?? widget.initialFilters.department;
    _selectedCourse = widget.fixedCourse ?? widget.initialFilters.course;
    _selectedYear = widget.initialFilters.year;
    _selectedSemester = widget.initialFilters.semester;

    // Initialize dependent dropdown lists based on initial/fixed school
    _updateDependentDropdowns();
  }

  // Helper to update department and course lists based on selected school
  void _updateDependentDropdowns() {
    // Only update if school is not fixed (i.e., changeable in refinement mode)
    if (widget.fixedSchool == null) {
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
    } else {
      // If school is fixed, use that to determine departments/courses (relevant for refinement mode if needed)
      _currentDepartments = departmentsMap[widget.fixedSchool] ?? [];
      _currentCourses = coursesMap[widget.fixedSchool] ?? [];
    }
  }

  /// Validates (if needed) and returns the selected filter data via Navigator.pop
  void _applyFilters() {
    // Validate only if it's the initial mandatory selection
    if (widget.isInitialSelection) {
      if (!_formKey.currentState!.validate()) {
        // Show error or prevent closing if validation fails
        ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('Please select Year and Semester'), backgroundColor: Colors.redAccent),
        );
        return; // Don't proceed if validation fails
      }
    }

    // Create filter data object with the final selections
    final filters = LectureFilterData(
      // Return fixed values if they were provided, otherwise return selection
      school: widget.fixedSchool ?? _selectedSchool,
      department: widget.fixedDepartment ?? _selectedDepartment,
      course: widget.fixedCourse ?? _selectedCourse,
      year: _selectedYear,
      semester: _selectedSemester,
    );
    // Pop the dialog and return the selected filters object
    Navigator.of(context).pop(filters);
  }

  @override
  Widget build(BuildContext context) {
    // Determine if School/Dept/Course fields should be enabled (only in refinement mode)
    final bool allowSchoolChange = !widget.isInitialSelection && widget.fixedSchool == null;
    final bool allowDeptChange = !widget.isInitialSelection && widget.fixedDepartment == null && _selectedSchool != null;
    final bool allowCourseChange = !widget.isInitialSelection && widget.fixedCourse == null && _selectedSchool != null;

    return AlertDialog(
      // Change title based on mode
      title: Text(widget.isInitialSelection ? 'Select Year & Semester' : 'Change Filters'),
      scrollable: true, // Make content scrollable if it overflows
      content: Form( // Wrap content in Form for validation
        key: _formKey,
        child: Column( // Use Column directly inside content
          mainAxisSize: MainAxisSize.min, // Take minimum vertical space
          children: <Widget>[
            // --- Conditionally show/disable School/Dept/Course ---
            // Only show these fields if NOT in initial selection mode
            if (!widget.isInitialSelection) ...[
              if (widget.fixedSchool != null) ...[
                _buildDisabledInfoField('School', widget.fixedSchool!),
                const SizedBox(height: 15),
              ] else DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'School ${allowSchoolChange ? "(Optional)" : ""}', border: const OutlineInputBorder()),
                value: _selectedSchool,
                items: [
                  if (allowSchoolChange) const DropdownMenuItem<String>(value: null, child: Text('Any School')),
                  ...schoolsList.map((String school) => DropdownMenuItem<String>(value: school, child: Text(school, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: allowSchoolChange ? (String? newValue) {
                  setState(() {
                    _selectedSchool = newValue; _selectedDepartment = null; _selectedCourse = null;
                    _updateDependentDropdowns();
                  });
                } : null,
                isExpanded: true,
              ),

              if (!allowSchoolChange && widget.fixedSchool != null) const SizedBox.shrink() else const SizedBox(height: 15),

              if (widget.fixedDepartment != null) ...[
                _buildDisabledInfoField('Department', widget.fixedDepartment!),
                const SizedBox(height: 15),
              ] else DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'Department ${allowDeptChange ? "(Optional)" : ""}', border: const OutlineInputBorder(), hintText: _selectedSchool == null ? 'Select school first' : null),
                value: _selectedDepartment,
                items: [
                  if (allowDeptChange) const DropdownMenuItem<String>(value: null, child: Text('Any Department')),
                  ..._currentDepartments.map((String department) => DropdownMenuItem<String>(value: department, child: Text(department, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: allowDeptChange ? (String? newValue) {
                  setState(() { _selectedDepartment = newValue; });
                } : null,
                isExpanded: true,
              ),

              if (!allowDeptChange && widget.fixedDepartment != null) const SizedBox.shrink() else const SizedBox(height: 15),

              if (widget.fixedCourse != null) ...[
                _buildDisabledInfoField('Course', widget.fixedCourse!),
                const SizedBox(height: 15),
              ] else DropdownButtonFormField<String>(
                decoration: InputDecoration(labelText: 'Course ${allowCourseChange ? "(Optional)" : ""}', border: const OutlineInputBorder(), hintText: _selectedSchool == null ? 'Select school first' : null),
                value: _selectedCourse,
                items: [
                  if (allowCourseChange) const DropdownMenuItem<String>(value: null, child: Text('Any Course')),
                  ..._currentCourses.map((String course) => DropdownMenuItem<String>(value: course, child: Text(course, overflow: TextOverflow.ellipsis))),
                ],
                onChanged: allowCourseChange ? (String? newValue) {
                  setState(() { _selectedCourse = newValue; });
                } : null,
                isExpanded: true,
              ),
              const SizedBox(height: 15), // Add spacing after conditional fields
            ],
            // --- End Conditional Fields ---

            // --- Year Dropdown (Always Visible) ---
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Year of Study ${widget.isInitialSelection ? "*" : "(Optional)"}', // Add asterisk for mandatory
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.calendar_view_day_outlined, size: 20), // Add icon
              ),
              value: _selectedYear,
              items: [
                // Hide "Any" option in initial selection mode
                if (!widget.isInitialSelection) const DropdownMenuItem<String>(value: null, child: Text('Any Year')),
                ...yearsList.map((String year) => DropdownMenuItem<String>(value: year, child: Text(year))),
              ],
              onChanged: (String? newValue) { setState(() { _selectedYear = newValue; }); },
              // Add validator for initial selection
              validator: widget.isInitialSelection
                  ? (value) => value == null ? 'Please select year' : null
                  : null,
              isExpanded: true,
            ),
            const SizedBox(height: 15),

            // --- Semester Dropdown (Always Visible) ---
            DropdownButtonFormField<String>(
              decoration: InputDecoration(
                labelText: 'Semester ${widget.isInitialSelection ? "*" : "(Optional)"}', // Add asterisk for mandatory
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.filter_list_alt, size: 20), // Add icon
              ),
              value: _selectedSemester,
              items: [
                // Hide "Any" option in initial selection mode
                if (!widget.isInitialSelection) const DropdownMenuItem<String>(value: null, child: Text('Any Semester')),
                ...semestersList.map((String semester) => DropdownMenuItem<String>(value: semester, child: Text(semester))),
              ],
              onChanged: (String? newValue) { setState(() { _selectedSemester = newValue; }); },
               // Add validator for initial selection
              validator: widget.isInitialSelection
                  ? (value) => value == null ? 'Please select semester' : null
                  : null,
              isExpanded: true,
            ),
          ],
        ),
      ),
      actions: <Widget>[
        // Hide Cancel button in initial selection mode
        if (!widget.isInitialSelection)
          TextButton(
            onPressed: () => Navigator.of(context).pop(), // Pop without returning data
            child: const Text('Cancel'),
          ),
        ElevatedButton(
          onPressed: _applyFilters, // Call the apply method
          // Change button text based on mode
          child: Text(widget.isInitialSelection ? 'Show Lectures' : 'Apply Filters'),
        ),
      ],
    );
  }

  // Helper widget to display fixed info fields nicely
  Widget _buildDisabledInfoField(String label, String value) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: OutlineInputBorder(borderSide: BorderSide(color: Colors.grey.shade400)), // Subtle border
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        filled: true, // Add a background color
        fillColor: Colors.grey[100],
      ),
      child: Text(value, style: TextStyle(color: Colors.grey[700], fontSize: 16)),
    );
  }
}
