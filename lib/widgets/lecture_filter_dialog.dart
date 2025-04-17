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
  final bool isInitialSelection;
  final String? fixedSchool;
  final String? fixedDepartment;
  final String? fixedCourse;

  // Define the brand color (consistent styling)
  static const Color brandColor = Color(0xFF0175C2);

  const LectureFilterDialog({
    super.key,
    required this.initialFilters,
    this.isInitialSelection = false,
    this.fixedSchool,
    this.fixedDepartment,
    this.fixedCourse,
  });

  @override
  State<LectureFilterDialog> createState() => _LectureFilterDialogState();
}

class _LectureFilterDialogState extends State<LectureFilterDialog> {
  final _formKey = GlobalKey<FormState>();

  String? _selectedSchool;
  String? _selectedDepartment;
  String? _selectedCourse;
  String? _selectedYear;
  String? _selectedSemester;

  List<String> _currentDepartments = [];
  List<String> _currentCourses = [];

  @override
  void initState() {
    super.initState();
    _selectedSchool = widget.fixedSchool ?? widget.initialFilters.school;
    _selectedDepartment = widget.fixedDepartment ?? widget.initialFilters.department;
    _selectedCourse = widget.fixedCourse ?? widget.initialFilters.course;
    _selectedYear = widget.initialFilters.year;
    _selectedSemester = widget.initialFilters.semester;
    _updateDependentDropdowns();
  }

  void _updateDependentDropdowns() {
    if (widget.fixedSchool == null) {
      _currentDepartments = (_selectedSchool != null && departmentsMap.containsKey(_selectedSchool))
          ? departmentsMap[_selectedSchool]! : [];
      _currentCourses = (_selectedSchool != null && coursesMap.containsKey(_selectedSchool))
          ? coursesMap[_selectedSchool]! : [];
      if (_selectedDepartment != null && !_currentDepartments.contains(_selectedDepartment)) {
        _selectedDepartment = null;
      }
      if (_selectedCourse != null && !_currentCourses.contains(_selectedCourse)) {
        _selectedCourse = null;
      }
    } else {
      _currentDepartments = departmentsMap[widget.fixedSchool] ?? [];
      _currentCourses = coursesMap[widget.fixedSchool] ?? [];
    }
  }

  void _applyFilters() {
    if (widget.isInitialSelection) {
      if (!_formKey.currentState!.validate()) {
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
             content: const Text('Please select Year and Semester'),
             backgroundColor: Theme.of(context).colorScheme.error, // Use theme error color
             behavior: SnackBarBehavior.floating,
           ),
        );
        return;
      }
    }
    final filters = LectureFilterData(
      school: widget.fixedSchool ?? _selectedSchool,
      department: widget.fixedDepartment ?? _selectedDepartment,
      course: widget.fixedCourse ?? _selectedCourse,
      year: _selectedYear,
      semester: _selectedSemester,
    );
    Navigator.of(context).pop(filters);
  }

  // Helper for consistent InputDecoration
  InputDecoration _inputDecoration(String label, {String? hint, Widget? prefixIcon, bool isRequired = false}) {
    return InputDecoration(
      labelText: '$label${isRequired ? " *" : ""}', // Add asterisk if required
      hintText: hint,
      prefixIcon: prefixIcon != null
          ? IconTheme(
              data: IconThemeData(color: LectureFilterDialog.brandColor.withOpacity(0.7)),
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
        borderSide: const BorderSide(color: LectureFilterDialog.brandColor, width: 1.5),
      ),
      filled: true,
      fillColor: Colors.grey[100],
      contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool allowSchoolChange = !widget.isInitialSelection && widget.fixedSchool == null;
    final bool allowDeptChange = !widget.isInitialSelection && widget.fixedDepartment == null && _selectedSchool != null;
    final bool allowCourseChange = !widget.isInitialSelection && widget.fixedCourse == null && _selectedSchool != null;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // Rounded corners
      title: Text(widget.isInitialSelection ? 'Select Year & Semester' : 'Change Filters'),
      scrollable: true,
      content: Form(
        key: _formKey,
        child: Padding( // Add padding around the form content
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              // --- Conditionally show/disable School/Dept/Course ---
              if (!widget.isInitialSelection) ...[
                if (widget.fixedSchool != null) ...[
                  _buildDisabledInfoField('School', widget.fixedSchool!),
                  const SizedBox(height: 15),
                ] else DropdownButtonFormField<String>(
                  decoration: _inputDecoration('School', prefixIcon: const Icon(Icons.school_outlined)),
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
                  decoration: _inputDecoration('Department', hint: _selectedSchool == null ? 'Select school first' : null, prefixIcon: const Icon(Icons.business_outlined)),
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
                  decoration: _inputDecoration('Course', hint: _selectedSchool == null ? 'Select school first' : null, prefixIcon: const Icon(Icons.book_outlined)),
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
                const SizedBox(height: 15),
              ],
              // --- End Conditional Fields ---

              // --- Year Dropdown (Always Visible) ---
              DropdownButtonFormField<String>(
                decoration: _inputDecoration(
                  'Year of Study',
                  prefixIcon: const Icon(Icons.calendar_view_day_outlined, size: 20),
                  isRequired: widget.isInitialSelection, // Mark as required visually
                ),
                value: _selectedYear,
                items: [
                  if (!widget.isInitialSelection) const DropdownMenuItem<String>(value: null, child: Text('Any Year')),
                  ...yearsList.map((String year) => DropdownMenuItem<String>(value: year, child: Text(year))),
                ],
                onChanged: (String? newValue) { setState(() { _selectedYear = newValue; }); },
                validator: widget.isInitialSelection
                    ? (value) => value == null ? 'Please select year' : null
                    : null,
                isExpanded: true,
              ),
              const SizedBox(height: 15),

              // --- Semester Dropdown (Always Visible) ---
              DropdownButtonFormField<String>(
                decoration: _inputDecoration(
                  'Semester',
                  prefixIcon: const Icon(Icons.filter_list_alt, size: 20),
                  isRequired: widget.isInitialSelection, // Mark as required visually
                ),
                value: _selectedSemester,
                items: [
                  if (!widget.isInitialSelection) const DropdownMenuItem<String>(value: null, child: Text('Any Semester')),
                  ...semestersList.map((String semester) => DropdownMenuItem<String>(value: semester, child: Text(semester))),
                ],
                onChanged: (String? newValue) { setState(() { _selectedSemester = newValue; }); },
                validator: widget.isInitialSelection
                    ? (value) => value == null ? 'Please select semester' : null
                    : null,
                isExpanded: true,
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0), // Adjust action button padding
      actions: <Widget>[
        if (!widget.isInitialSelection)
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ElevatedButton(
          onPressed: _applyFilters,
          style: ElevatedButton.styleFrom( // Apply brand color to primary action
            backgroundColor: LectureFilterDialog.brandColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // Pill shape
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          ),
          child: Text(widget.isInitialSelection ? 'Show Lectures' : 'Apply Filters'),
        ),
      ],
    );
  }

  Widget _buildDisabledInfoField(String label, String value) {
    return InputDecorator(
      decoration: _inputDecoration(label).copyWith( // Use helper for consistency
        fillColor: Colors.grey[200], // Slightly darker background for disabled
      ),
      child: Text(value, style: TextStyle(color: Colors.grey[800], fontSize: 16)), // Darker text for readability
    );
  }
}
