import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/models/attendance_record.dart'; // Import AttendanceRecord
import 'package:checkmate/services/api_service.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:checkmate/widgets/lecture_filter_dialog.dart'; // Import the dialog
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
// import 'login_screen.dart'; // Not needed directly if using Wrapper
import 'package:checkmate/screens/welcome_screen.dart'; // Import WelcomeScreen for logout
// Import for date/time formatting in UI

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
  String? _joiningLectureIdTemp; // Temp state to show loading on specific button

  // --- Filter State ---
  // School/Dept/Course are fixed based on logged-in user
  String? fixedSchool;
  String? fixedDepartment;
  String? fixedCourse;
  // Year/Semester are selected by the user (initially null)
  String? selectedYear;
  String? selectedSemester;
  // --- End Filter State ---

  // --- State to track if initial selection is done ---
  bool initialFiltersApplied = false;
  // --- End Initial Selection State ---

  @override
  void initState() {
    super.initState();
    // Store fixed user details from the currentUser object
    fixedSchool = widget.currentUser.school;
    fixedDepartment = widget.currentUser.department;
    fixedCourse = widget.currentUser.course;

    // Show the initial filter dialog *after* the first frame is built
    // This prevents errors related to showing dialogs during build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Ensure the widget is still mounted before showing the dialog
      if (mounted) {
        showInitialFilterDialog();
      }
    });
  }

  /// Shows the MANDATORY dialog for selecting Year and Semester on first load.
  Future<void> showInitialFilterDialog() async {
    // Initial filter data for the dialog (Year/Semester are null initially)
    final initialData = LectureFilterData(
      school: fixedSchool,
      department: fixedDepartment,
      course: fixedCourse,
      year: null,
      semester: null,
    );

    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (context) => LectureFilterDialog(
        initialFilters: initialData,
        isInitialSelection: true, // Use initial selection mode
        fixedSchool: fixedSchool, // Pass fixed data to dialog
        fixedDepartment: fixedDepartment,
        fixedCourse: fixedCourse,
      ),
    );

    // If the dialog returned valid filters (user pressed "Show Lectures")
    if (selectedFilters != null && selectedFilters.year != null && selectedFilters.semester != null && mounted) {
      setState(() {
        selectedYear = selectedFilters.year;
        selectedSemester = selectedFilters.semester;
        initialFiltersApplied = true; // Mark initial selection as complete
      });
      loadLectures(); // Load lectures now with the selected filters
    } else if (mounted) {
      // This case should ideally not happen due to barrierDismissible=false
      // and validation in the dialog, but handle defensively.
      print("Initial filter dialog closed unexpectedly or without valid selection.");
      // Consider showing an error or forcing the dialog again.
      // For now, the UI will show the "Please select..." message.
      // Optionally, close the app or navigate back if selection is absolutely mandatory.
    }
  }

  /// Shows the filter dialog to CHANGE Year and Semester after initial selection.
  Future<void> showRefineFilterDialog() async {
    // Pass the currently selected filters as initial values
    final currentFilters = LectureFilterData(
      school: fixedSchool,
      department: fixedDepartment,
      course: fixedCourse,
      year: selectedYear,
      semester: selectedSemester,
    );

    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context,
      barrierDismissible: true, // Allow dismissing this refinement dialog
      builder: (context) => LectureFilterDialog(
        initialFilters: currentFilters,
        isInitialSelection: false, // Refinement mode (allows changing year/semester)
        fixedSchool: fixedSchool,
        fixedDepartment: fixedDepartment,
        fixedCourse: fixedCourse,
      ),
    );

    // If user applied new filters (didn't cancel) and they differ from current
    if (selectedFilters != null && mounted) {
      if (selectedFilters.year != selectedYear || selectedFilters.semester != selectedSemester) {
        setState(() {
          selectedYear = selectedFilters.year;
          selectedSemester = selectedFilters.semester;
          // Reset join state when filters change
          joinedLectureId = null;
          visitNumber = null;
        });
        loadLectures(); // Reload lectures with new filters
      }
    }
  }

  /// Fetches lectures based on FIXED school/dept/course and SELECTED year/semester.
  void loadLectures() {
    // Only load if initial filters (Year/Semester) have been applied
    if (!initialFiltersApplied || selectedYear == null || selectedSemester == null) {
      print("Attempted to load lectures before initial Year/Semester were set.");
      // Clear any existing future to prevent showing old data
      if (lecturesFuture != null && mounted) {
         setState(() { lecturesFuture = null; });
      }
      return; // Do nothing further
    }
    // Set the future to trigger the FutureBuilder
    if (!mounted) return;
    setState(() {
      lecturesFuture = apiService.getStudentLectures(
        fixedSchool,
        fixedDepartment,
        fixedCourse,
        selectedYear, // Use selected year
        selectedSemester, // Use selected semester
      );
    });
  }

  /// Handles the "Join" button press for a specific lecture.
  Future<void> joinLecture(Lecture lecture) async {
     if (isJoining) return; // Prevent double taps
     if (!mounted) return;
     setState(() {
       isJoining = true;
       _joiningLectureIdTemp = lecture.id; // Mark this specific lecture button as loading
       // Reset previous join state immediately for UI responsiveness
       visitNumber = null;
       joinedLectureId = null;
     });
     try {
       final AttendanceRecord attendanceRecord = await apiService.joinLecture(lecture.id, widget.currentUser.id);
       if (!mounted) return;
       setState(() {
         visitNumber = attendanceRecord.visitNumber;
         joinedLectureId = lecture.id; // Mark this lecture as successfully joined
       });
       showSnackBar('Successfully joined ${lecture.unitName}! Your visit number is $visitNumber.', isError: false);
     } catch (e) {
       if (!mounted) return;
       showSnackBar('Failed to join lecture: ${e.toString()}', isError: true);
       // Reset join state on failure
       setState(() {
         joinedLectureId = null;
         visitNumber = null;
       });
     } finally {
       if (mounted) {
         setState(() {
           isJoining = false;
           _joiningLectureIdTemp = null; // Clear loading state for the button
         });
       }
     }
  }

  /// Utility function to display a SnackBar message.
  void showSnackBar(String message, {bool isError = false}) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar( SnackBar( content: Text(message), backgroundColor: isError ? Colors.redAccent : Colors.green, duration: const Duration(seconds: 3), ), );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text('Student Dashboard - ${widget.currentUser.name}'),
        actions: [
           // Filter Button - Now used to CHANGE Year/Semester
           IconButton(
             // Disable filter button until initial selection is done
             icon: Icon(Icons.edit_calendar_outlined, color: initialFiltersApplied ? Colors.white : Colors.white54),
             tooltip: 'Change Year/Semester',
             onPressed: initialFiltersApplied ? showRefineFilterDialog : null,
           ),
           IconButton(
             // Disable refresh until initial selection is done
             icon: Icon(Icons.refresh, color: initialFiltersApplied ? Colors.white : Colors.white54),
             tooltip: 'Refresh Lectures',
             onPressed: initialFiltersApplied ? loadLectures : null,
           ),
           IconButton( icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: () async {
              final confirm = await showDialog<bool>( context: context, builder: (context) => AlertDialog( title: const Text('Confirm Logout'), content: const Text('Are you sure you want to log out?'), actions: [ TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Logout')), ], ), ) ?? false;
              if (confirm && mounted) { await authService.logout(); Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, ); }
           }, ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Show selected Year/Semester only AFTER initial selection
          if (initialFiltersApplied) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
              child: Text(
                "Available Lectures",
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Wrap(
                spacing: 8.0, runSpacing: 4.0,
                children: [
                  // Display the MANDATORY selected year and semester
                  if (selectedYear != null) Chip(label: Text('Year: $selectedYear')),
                  if (selectedSemester != null) Chip(label: Text('Semester: $selectedSemester')),
                  // Optionally display fixed course for context
                  if (fixedCourse != null) Chip(label: Text('Course: $fixedCourse'), backgroundColor: Colors.grey.shade200),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16),
          ],

          // Main Content Area
          Expanded(
            child: initialFiltersApplied
                // If initial filters applied, show RefreshIndicator + FutureBuilder
                ? RefreshIndicator(
                    onRefresh: () async => loadLectures(),
                    child: FutureBuilder<List<Lecture>>(
                      future: lecturesFuture,
                      builder: (context, snapshot) {
                        // --- FutureBuilder states ---
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (snapshot.hasError) {
                          return Center(
                             child: Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.cloud_off, color: Colors.orangeAccent.shade700, size: 48), const SizedBox(height: 10), Text( 'Error loading lectures: ${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: Colors.orangeAccent.shade700), ), const SizedBox(height: 10), ElevatedButton.icon( icon: const Icon(Icons.refresh), label: const Text('Retry'), onPressed: loadLectures, style: ElevatedButton.styleFrom(backgroundColor: Colors.orangeAccent), ) ], ), )
                          );
                        }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return LayoutBuilder(
                             builder: (context, constraints) { return SingleChildScrollView( physics: const AlwaysScrollableScrollPhysics(), child: ConstrainedBox( constraints: BoxConstraints(minHeight: constraints.maxHeight), child: Center( child: Padding( padding: const EdgeInsets.all(20.0), child: Text( 'No lectures found for Year $selectedYear, Semester $selectedSemester.\nTry changing filters or pull down to refresh.', textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.grey), ), ), ), ), ); }
                          );
                        }

                        // --- Success: Display Lecture List ---
                        final lectures = snapshot.data!;
                        // Sort lectures by date and start time
                        lectures.sort((a,b) {
                          int dateComp = a.lectureDate.compareTo(b.lectureDate);
                          if (dateComp != 0) return dateComp;
                          return a.startTime.compareTo(b.startTime);
                        });

                        return ListView.builder(
                           physics: const AlwaysScrollableScrollPhysics(),
                           padding: const EdgeInsets.only(bottom: 16, left: 8, right: 8),
                           itemCount: lectures.length,
                           itemBuilder: (context, index) {
                              final lecture = lectures[index];
                              final bool isSuccessfullyJoined = lecture.id == joinedLectureId;
                              final bool isCurrentlyJoining = isJoining && _joiningLectureIdTemp == lecture.id;

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 5),
                                child: ListTile(
                                  leading: CircleAvatar(
                                    backgroundColor: Theme.of(context).primaryColorLight,
                                    child: Icon(Icons.schedule, color: Theme.of(context).primaryColorDark),
                                  ),
                                  title: Text('${lecture.unitName} (${lecture.unitCode})', style: const TextStyle(fontWeight: FontWeight.w500)),
                                  subtitle: Text(
                                    'Lecturer: ${lecture.lecturerName}\n${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}\nVenue: ${lecture.venue}'
                                  ),
                                  isThreeLine: true,
                                  trailing: isSuccessfullyJoined
                                    // Show Chip with Visit Number if successfully joined
                                    ? Chip(
                                        avatar: Icon(Icons.confirmation_number_outlined, size: 18, color: Colors.green.shade800),
                                        label: Text('Visit #: $visitNumber'),
                                        backgroundColor: Colors.green.shade100,
                                        side: BorderSide(color: Colors.green.shade200),
                                      )
                                    // Show Join Button or Loading Indicator
                                    : ElevatedButton(
                                        onPressed: isJoining ? null : () => joinLecture(lecture), // Disable if any join is in progress
                                        style: ElevatedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                          textStyle: const TextStyle(fontSize: 14),
                                        ),
                                        child: isCurrentlyJoining // Show loading only for the specific button being pressed
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
                // If initial filters NOT applied yet, show a placeholder message
                : const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(), // Show loading while dialog is potentially visible
                          SizedBox(height: 16),
                          Text(
                            'Please select your Year and Semester to view lectures.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey),
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

  // Removed getPotentialJoiningLectureId as logic is now inline in build method
}
