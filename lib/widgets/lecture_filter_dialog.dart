import 'package:checkmate/services/admin_service.dart';
import 'package:flutter/material.dart';

// Data class to hold filter values returned by the dialog
class LectureFilterData {
  final String? schoolId;
  final String? departmentId;
  final String? courseId;
  final String? yearId;
  final String? semesterId;

  LectureFilterData({
    this.schoolId,
    this.departmentId,
    this.courseId,
    this.yearId,
    this.semesterId,
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
  final AdminService _adminService = AdminService();

  String? _selectedSchoolId;
  String? _selectedDepartmentId;
  String? _selectedCourseId;
  String? _selectedYearId;
  String? _selectedSemesterId;

  @override
  void initState() {
    super.initState();
    _selectedSchoolId = widget.fixedSchool ?? widget.initialFilters.schoolId;
    _selectedDepartmentId = widget.fixedDepartment ?? widget.initialFilters.departmentId;
    _selectedCourseId = widget.fixedCourse ?? widget.initialFilters.courseId;
    _selectedYearId = widget.initialFilters.yearId;
    _selectedSemesterId = widget.initialFilters.semesterId;
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
      schoolId: widget.fixedSchool ?? _selectedSchoolId,
      departmentId: widget.fixedDepartment ?? _selectedDepartmentId,
      courseId: widget.fixedCourse ?? _selectedCourseId,
      yearId: _selectedYearId,
      semesterId: _selectedSemesterId,
    );
    Navigator.of(context).pop(filters);
  }

  // Helper for consistent InputDecoration
  InputDecoration _inputDecoration(String label, {String? hint, Widget? prefixIcon, bool isRequired = false}) {
    return InputDecoration(
      labelText: '$label${isRequired ? " *" : ""}', 
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
    final bool allowDeptChange = !widget.isInitialSelection && widget.fixedDepartment == null && _selectedSchoolId != null;
    final bool allowCourseChange = !widget.isInitialSelection && widget.fixedCourse == null && _selectedSchoolId != null;

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
                ] else StreamBuilder<LocalQuerySnapshot>(
                  stream: _adminService.getSchools(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    var schools = snapshot.data!.docs;
                    return DropdownButtonFormField<String>(
                      decoration: _inputDecoration('School', prefixIcon: const Icon(Icons.school_outlined)),
                      value: _selectedSchoolId,
                      items: [
                        if (allowSchoolChange) const DropdownMenuItem<String>(value: null, child: Text('Any School')),
                        ...schools.map((school) => DropdownMenuItem<String>(value: school.id, child: Text(school['name'].toUpperCase(), overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: allowSchoolChange ? (String? newValue) {
                        setState(() {
                          _selectedSchoolId = newValue; _selectedDepartmentId = null; _selectedCourseId = null;
                        });
                      } : null,
                      isExpanded: true,
                    );
                  },
                ),

                if (!allowSchoolChange && widget.fixedSchool != null) const SizedBox.shrink() else const SizedBox(height: 15),

                if (widget.fixedDepartment != null) ...[
                  _buildDisabledInfoField('Department', widget.fixedDepartment!),
                  const SizedBox(height: 15),
                ] else StreamBuilder<LocalQuerySnapshot>(
                  stream: _selectedSchoolId == null ? null : _adminService.getDepartments(_selectedSchoolId!),
                  builder: (context, snapshot) {
                    if (_selectedSchoolId == null) {
                      return DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Department', hint: 'Select school first', prefixIcon: const Icon(Icons.business_outlined)),
                        items: const [],
                        onChanged: null,
                        isExpanded: true,
                      );
                    }
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    var departments = snapshot.data!.docs;
                    return DropdownButtonFormField<String>(
                      decoration: _inputDecoration('Department', hint: 'Select your department', prefixIcon: const Icon(Icons.business_outlined)),
                      value: _selectedDepartmentId,
                      items: [
                        if (allowDeptChange) const DropdownMenuItem<String>(value: null, child: Text('Any Department')),
                        ...departments.map((department) => DropdownMenuItem<String>(value: department.id, child: Text(department['name'].toUpperCase(), overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: allowDeptChange ? (String? newValue) {
                        setState(() { _selectedDepartmentId = newValue; });
                      } : null,
                      isExpanded: true,
                    );
                  },
                ),

                if (!allowDeptChange && widget.fixedDepartment != null) const SizedBox.shrink() else const SizedBox(height: 15),

                if (widget.fixedCourse != null) ...[
                  _buildDisabledInfoField('Course', widget.fixedCourse!),
                  const SizedBox(height: 15),
                ] else StreamBuilder<LocalQuerySnapshot>(
                  stream: _selectedDepartmentId == null ? null : _adminService.getCourses(_selectedDepartmentId!),
                  builder: (context, snapshot) {
                    if (_selectedDepartmentId == null) {
                      return DropdownButtonFormField<String>(
                        decoration: _inputDecoration('Course', hint: 'Select department first', prefixIcon: const Icon(Icons.book_outlined)),
                        items: const [],
                        onChanged: null,
                        isExpanded: true,
                      );
                    }
                    if (!snapshot.hasData) return const CircularProgressIndicator();
                    var courses = snapshot.data!.docs;
                    return DropdownButtonFormField<String>(
                      decoration: _inputDecoration('Course', hint: 'Select your course', prefixIcon: const Icon(Icons.book_outlined)),
                      value: _selectedCourseId,
                      items: [
                        if (allowCourseChange) const DropdownMenuItem<String>(value: null, child: Text('Any Course')),
                        ...courses.map((course) => DropdownMenuItem<String>(value: course.id, child: Text(course['name'].toUpperCase(), overflow: TextOverflow.ellipsis))),
                      ],
                      onChanged: allowCourseChange ? (String? newValue) {
                        setState(() { _selectedCourseId = newValue; });
                      } : null,
                      isExpanded: true,
                    );
                  },
                ),
                const SizedBox(height: 15),
              ],
              // --- End Conditional Fields ---

              // --- Year Dropdown (Always Visible) ---
              StreamBuilder<LocalQuerySnapshot>(
                stream: _adminService.getYearsOfStudy(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  var years = snapshot.data!.docs;
                  return DropdownButtonFormField<String>(
                    decoration: _inputDecoration(
                      'Year of Study',
                      prefixIcon: const Icon(Icons.calendar_view_day_outlined, size: 20),
                      isRequired: widget.isInitialSelection, // Mark as required visually
                    ),
                    value: _selectedYearId,
                    items: [
                      if (!widget.isInitialSelection) const DropdownMenuItem<String>(value: null, child: Text('Any Year')),
                      ...years.map((year) => DropdownMenuItem<String>(value: year.id, child: Text(year['name'].toUpperCase()))),
                    ],
                    onChanged: (String? newValue) { setState(() { _selectedYearId = newValue; }); },
                    validator: widget.isInitialSelection
                        ? (value) => value == null ? 'Please select year' : null
                        : null,
                    isExpanded: true,
                  );
                },
              ),
              const SizedBox(height: 15),

              // --- Semester Dropdown (Always Visible) ---
              StreamBuilder<LocalQuerySnapshot>(
                stream: _adminService.getSemesters(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) return const CircularProgressIndicator();
                  var semesters = snapshot.data!.docs;
                  return DropdownButtonFormField<String>(
                    decoration: _inputDecoration(
                      'Semester',
                      prefixIcon: const Icon(Icons.filter_list_alt, size: 20),
                      isRequired: widget.isInitialSelection, // Mark as required visually
                    ),
                    value: _selectedSemesterId,
                    items: [
                      if (!widget.isInitialSelection) const DropdownMenuItem<String>(value: null, child: Text('Any Semester')),
                      ...semesters.map((semester) => DropdownMenuItem<String>(value: semester.id, child: Text(semester['name'].toUpperCase()))),
                    ],
                    onChanged: (String? newValue) { setState(() { _selectedSemesterId = newValue; }); },
                    validator: widget.isInitialSelection
                        ? (value) => value == null ? 'Please select semester' : null
                        : null,
                    isExpanded: true,
                  );
                },
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
      decoration: _inputDecoration(label).copyWith( // helper for consistency
        fillColor: Colors.grey[200], // Slightly darker background for disabled
      ),
      child: Text(value, style: TextStyle(color: Colors.grey[800], fontSize: 16)), // Darker text for readability
    );
  }
}