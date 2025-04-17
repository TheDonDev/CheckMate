// lib/screens/student_dashboard.dart
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/models/attendance_record.dart'; // Import AttendanceRecord
import 'package:checkmate/services/api_service.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:checkmate/widgets/lecture_filter_dialog.dart'; // Import the dialog
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:checkmate/screens/welcome_screen.dart'; // Import WelcomeScreen for logout

class StudentDashboard extends StatefulWidget {
  final app_user.User currentUser;
  const StudentDashboard({super.key, required this.currentUser});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final ApiService apiService = ApiService();
  Future<List<Lecture>>? lecturesFuture;
  String? joinedLectureId;
  String? visitNumber;
  bool isJoining = false;
  String? _joiningLectureIdTemp;

  // Filter State
  String? fixedSchool;
  String? fixedDepartment;
  String? fixedCourse;
  String? selectedYear;
  String? selectedSemester;

  bool initialFiltersApplied = false;

  // Define the brand color (consistent styling)
  static const Color brandColor = Color(0xFF0175C2);

  @override
  void initState() {
    super.initState();
    fixedSchool = widget.currentUser.school;
    fixedDepartment = widget.currentUser.department;
    fixedCourse = widget.currentUser.course;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        showInitialFilterDialog();
      }
    });
  }

  Future<void> showInitialFilterDialog() async {
    final initialData = LectureFilterData(
      school: fixedSchool, department: fixedDepartment, course: fixedCourse,
      year: null, semester: null,
    );

    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context,
      barrierDismissible: false,
      builder: (context) => LectureFilterDialog(
        initialFilters: initialData, isInitialSelection: true,
        fixedSchool: fixedSchool, fixedDepartment: fixedDepartment, fixedCourse: fixedCourse,
      ),
    );

    if (selectedFilters != null && selectedFilters.year != null && selectedFilters.semester != null && mounted) {
      setState(() {
        selectedYear = selectedFilters.year;
        selectedSemester = selectedFilters.semester;
        initialFiltersApplied = true;
      });
      loadLectures();
    } else if (mounted) {
      print("Initial filter dialog closed unexpectedly or without valid selection.");
      // Optionally show error or force dialog again
    }
  }

  Future<void> showRefineFilterDialog() async {
    final currentFilters = LectureFilterData(
      school: fixedSchool, department: fixedDepartment, course: fixedCourse,
      year: selectedYear, semester: selectedSemester,
    );

    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context,
      barrierDismissible: true,
      builder: (context) => LectureFilterDialog(
        initialFilters: currentFilters, isInitialSelection: false,
        fixedSchool: fixedSchool, fixedDepartment: fixedDepartment, fixedCourse: fixedCourse,
      ),
    );

    if (selectedFilters != null && mounted) {
      if (selectedFilters.year != selectedYear || selectedFilters.semester != selectedSemester) {
        setState(() {
          selectedYear = selectedFilters.year;
          selectedSemester = selectedFilters.semester;
          joinedLectureId = null;
          visitNumber = null;
        });
        loadLectures();
      }
    }
  }

  void loadLectures() {
    if (!initialFiltersApplied || selectedYear == null || selectedSemester == null) {
      if (lecturesFuture != null && mounted) {
         setState(() { lecturesFuture = null; });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      lecturesFuture = apiService.getStudentLectures(
        fixedSchool, fixedDepartment, fixedCourse, selectedYear, selectedSemester,
      );
    });
  }

  Future<void> joinLecture(Lecture lecture) async {
     if (isJoining) return;
     if (!mounted) return;
     setState(() {
       isJoining = true;
       _joiningLectureIdTemp = lecture.id;
       visitNumber = null;
       joinedLectureId = null;
     });
     try {
       final AttendanceRecord attendanceRecord = await apiService.joinLecture(lecture.id, widget.currentUser.id);
       if (!mounted) return;
       setState(() {
         visitNumber = attendanceRecord.visitNumber;
         joinedLectureId = lecture.id;
       });
       showSnackBar('Successfully joined ${lecture.unitName}! Your visit number is $visitNumber.', isError: false);
     } catch (e) {
       if (!mounted) return;
       showSnackBar('Failed to join lecture: ${e.toString()}', isError: true);
       setState(() { joinedLectureId = null; visitNumber = null; });
     } finally {
       if (mounted) {
         setState(() { isJoining = false; _joiningLectureIdTemp = null; });
       }
     }
  }

  void showSnackBar(String message, {bool isError = false}) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(message),
         backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green, // Use theme error color
         behavior: SnackBarBehavior.floating, // Consistent behavior
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), // Rounded shape
         margin: const EdgeInsets.all(10), // Add margin
       ),
     );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Student Dashboard - ${widget.currentUser.name}', style: const TextStyle(fontSize: 18)), // Slightly smaller title
        backgroundColor: brandColor, // Apply brand color
        foregroundColor: Colors.white, // Ensure text/icons are white
        elevation: 2.0, // Consistent elevation
        actions: [
           IconButton(
             icon: Icon(Icons.edit_calendar_outlined, color: initialFiltersApplied ? Colors.white : Colors.white54),
             tooltip: 'Change Year/Semester',
             onPressed: initialFiltersApplied ? showRefineFilterDialog : null,
           ),
           IconButton(
             icon: Icon(Icons.refresh, color: initialFiltersApplied ? Colors.white : Colors.white54),
             tooltip: 'Refresh Lectures',
             onPressed: initialFiltersApplied ? loadLectures : null,
           ),
           IconButton(
             icon: const Icon(Icons.logout),
             tooltip: 'Logout',
             onPressed: () async {
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // Rounded dialog
                    title: const Text('Confirm Logout'),
                    content: const Text('Are you sure you want to log out?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red), // Highlight logout action
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                ) ?? false;
                if (confirm && mounted) {
                  await authService.logout();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                    (Route<dynamic> route) => false,
                  );
                }
             },
           ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (initialFiltersApplied) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
              child: Text(
                "Available Lectures",
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: brandColor), // Use brand color for title
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Wrap(
                spacing: 8.0, runSpacing: 4.0,
                children: [
                  if (selectedYear != null) Chip(label: Text('Year: $selectedYear'), backgroundColor: brandColor.withOpacity(0.1), side: BorderSide.none),
                  if (selectedSemester != null) Chip(label: Text('Semester: $selectedSemester'), backgroundColor: brandColor.withOpacity(0.1), side: BorderSide.none),
                  if (fixedCourse != null) Chip(label: Text('Course: $fixedCourse'), backgroundColor: Colors.grey.shade200, side: BorderSide.none),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16, thickness: 0.5),
          ],

          Expanded(
            child: initialFiltersApplied
                ? RefreshIndicator(
                    color: brandColor, // Set refresh indicator color
                    onRefresh: () async => loadLectures(),
                    child: FutureBuilder<List<Lecture>>(
                      future: lecturesFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator(color: brandColor)); // Use brand color
                        }
                        if (snapshot.hasError) {
                          return Center(
                             child: Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
                               Icon(Icons.cloud_off_outlined, color: Colors.orange.shade700, size: 48),
                               const SizedBox(height: 10),
                               Text( 'Error loading lectures: ${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700), ),
                               const SizedBox(height: 15),
                               ElevatedButton.icon(
                                 icon: const Icon(Icons.refresh), label: const Text('Retry'),
                                 onPressed: loadLectures,
                                 style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white), // Themed retry button
                               )
                             ], ), )
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return LayoutBuilder(
                             builder: (context, constraints) { return SingleChildScrollView( physics: const AlwaysScrollableScrollPhysics(), child: ConstrainedBox( constraints: BoxConstraints(minHeight: constraints.maxHeight), child: Center( child: Padding( padding: const EdgeInsets.all(20.0), child: Column( // Use column for icon + text
                               mainAxisAlignment: MainAxisAlignment.center,
                               children: [
                                 Icon(Icons.event_busy_outlined, size: 50, color: Colors.grey.shade400),
                                 const SizedBox(height: 10),
                                 Text( 'No lectures found for Year $selectedYear, Semester $selectedSemester.\nTry changing filters or pull down to refresh.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ),
                               ],
                             )), ), ), ); }
                          );
                        }

                        // --- Success: Display Lecture List ---
                        final lectures = snapshot.data!;
                        lectures.sort((a,b) {
                          int dateComp = a.lectureDate.compareTo(b.lectureDate);
                          if (dateComp != 0) return dateComp;
                          return a.startTime.compareTo(b.startTime);
                        });

                        return ListView.builder(
                           physics: const AlwaysScrollableScrollPhysics(),
                           padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12), // Adjusted padding
                           itemCount: lectures.length,
                           itemBuilder: (context, index) {
                              final lecture = lectures[index];
                              final bool isSuccessfullyJoined = lecture.id == joinedLectureId;
                              final bool isCurrentlyJoining = isJoining && _joiningLectureIdTemp == lecture.id;

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6.0), // Consistent margin
                                elevation: 1.5, // Subtle elevation
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), // Rounded corners
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0), // Adjust padding
                                  leading: CircleAvatar(
                                    backgroundColor: brandColor.withOpacity(0.1), // Use brand color subtly
                                    child: Icon(Icons.schedule_outlined, color: brandColor), // Themed icon
                                  ),
                                  title: Text('${lecture.unitName} (${lecture.unitCode})', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)), // Slightly bolder title
                                  subtitle: Padding( // Add padding to subtitle
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      'Lecturer: ${lecture.lecturerName}\n${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}\nVenue: ${lecture.venue}',
                                      style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3), // Adjust style
                                    ),
                                  ),
                                  isThreeLine: true,
                                  trailing: isSuccessfullyJoined
                                    ? Chip(
                                        avatar: Icon(Icons.check_circle_outline, size: 18, color: Colors.green.shade800),
                                        label: Text('Visit #: $visitNumber', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500)),
                                        backgroundColor: Colors.green.shade100,
                                        side: BorderSide.none, // Remove border
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      )
                                    : ElevatedButton(
                                        onPressed: isJoining ? null : () => joinLecture(lecture),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: brandColor, // Use brand color for Join button
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // Pill shape
                                          minimumSize: const Size(80, 36), // Ensure minimum size
                                        ),
                                        child: isCurrentlyJoining
                                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                          : const Text('Join'),
                                      ),
                                ),
                              );
                           },
                        );
                      },
                    ),
                  )
                : Center( // Placeholder when initial filters not applied
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: brandColor), // Use brand color
                          const SizedBox(height: 20),
                          Text(
                            'Please select your Year and Semester\nto view available lectures.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
