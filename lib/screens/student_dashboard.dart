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
  String? joinedLectureId; // Keep track of the lecture just joined for UI feedback
  // Removed visitNumber state
  bool isJoining = false; // Still needed for loading state on button/dialog
  String? _joiningLectureIdTemp; // Track which lecture is being joined

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

    // Ensure registration number exists for student
    if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) {
           _showMissingRegNumError();
         }
       });
    } else {
      // Only show filter dialog if registration number exists
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showInitialFilterDialog();
        }
      });
    }
  }

  // Show error if student registration number is missing
  void _showMissingRegNumError() {
     showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
             children: [
               Icon(Icons.error_outline, color: Colors.red),
               SizedBox(width: 10),
               Text('Registration Incomplete'),
             ],
          ),
          content: const Text('Your student registration number is missing.\nPlease contact support or re-register to use attendance features.'),
          actions: [
            TextButton(
              onPressed: () async {
                 Navigator.of(context).pop(); // Close dialog
                 // Log out the user
                 await Provider.of<AuthService>(context, listen: false).logout();
                 if (mounted) {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                      (Route<dynamic> route) => false,
                    );
                 }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Logout'),
            ),
          ],
        ),
     );
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
      // Optionally handle this case, maybe show error or force dialog again
      // If closing is critical, you might want to prevent it or show a message
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
          joinedLectureId = null; // Reset joined status when filters change
          // visitNumber = null; // Removed visitNumber
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
      joinedLectureId = null; // Reset joined status on refresh/load
      lecturesFuture = apiService.getStudentLectures(
        fixedSchool, fixedDepartment, fixedCourse, selectedYear, selectedSemester,
      );
      // TODO: Optionally, fetch the student's current attendance status for these lectures
      // to pre-mark lectures they already joined in this session.
      // This would require an additional API call like `getStudentAttendanceForLectures(studentId, lectureIds)`
    });
  }

  // --- Modified: Show Dialog before Joining ---
  Future<void> showJoinLectureDialog(Lecture lecture) async {
    // Ensure student has a registration number (should be guaranteed by initial check, but double-check)
    final studentRegNum = widget.currentUser.registrationNumber;
    if (studentRegNum == null || studentRegNum.isEmpty) {
      showSnackBar('Error: Your registration number is missing. Cannot join lecture.', isError: true);
      // Optionally call _showMissingRegNumError() again here
      return;
    }

    if (isJoining) return; // Prevent multiple dialogs

    setState(() {
      isJoining = true; // Set loading state for the main button
      _joiningLectureIdTemp = lecture.id; // Mark which lecture is being attempted
    });

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Don't dismiss by tapping outside
      builder: (dialogContext) {
        // Use StatefulBuilder if the dialog needs internal state changes (e.g., its own loading indicator)
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text('Confirm Join: ${lecture.unitName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min, // Prevent excessive height
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('You are about to join this lecture using your registered number:'),
              const SizedBox(height: 10),
              // Display the registration number clearly and read-only
              InputChip(
                label: Text(studentRegNum, style: TextStyle(fontWeight: FontWeight.bold, color: brandColor)),
                avatar: Icon(Icons.badge_outlined, color: brandColor),
                backgroundColor: brandColor.withOpacity(0.1),
                side: BorderSide.none,
                isEnabled: false, // Make it non-interactive
              ),
              const SizedBox(height: 15),
              Text('Date: ${lecture.formattedDate}'),
              Text('Time: ${lecture.formattedStartTime} - ${lecture.formattedEndTime}'),
              Text('Venue: ${lecture.venue}'),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false), // Cancel
              child: const Text('Cancel'),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Confirm Join'),
              style: ElevatedButton.styleFrom(
                backgroundColor: brandColor,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true), // Confirm
            ),
          ],
        );
      },
    );

    // Reset loading state if dialog was cancelled
    if (confirmed != true) {
       if (mounted) {
         setState(() { isJoining = false; _joiningLectureIdTemp = null; });
       }
       return; // Stop if cancelled
    }

    // --- Proceed with API call if confirmed ---
    try {
      // Call API using the student's registration number
      // Ensure the registration number is not null before passing
      final AttendanceRecord attendanceRecord = await apiService.joinLecture(
          lecture.id,
          widget.currentUser.id,
          studentRegNum // Pass the non-null registration number
      );
      if (!mounted) return;
      setState(() {
        // Removed visitNumber update
        joinedLectureId = lecture.id; // Mark as successfully joined
      });
      // Updated Snackbar message - no visit number
      showSnackBar('Successfully joined ${lecture.unitName}!', isError: false);
    } catch (e) {
      if (!mounted) return;
      showSnackBar('Failed to join lecture: ${e.toString()}', isError: true);
      setState(() { joinedLectureId = null; }); // Ensure joined state is reset on failure
    } finally {
      if (mounted) {
        // Reset loading state regardless of success/failure
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
    // Determine if join button should be generally disabled (missing reg number)
    final bool canJoinLectures = widget.currentUser.registrationNumber != null && widget.currentUser.registrationNumber!.isNotEmpty;

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
             // Disable if initial filters not set or reg number missing
             onPressed: initialFiltersApplied && canJoinLectures ? showRefineFilterDialog : null,
           ),
           IconButton(
             icon: Icon(Icons.refresh, color: initialFiltersApplied ? Colors.white : Colors.white54),
             tooltip: 'Refresh Lectures',
             // Disable if initial filters not set or reg number missing
             onPressed: initialFiltersApplied && canJoinLectures ? loadLectures : null,
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
          // Show filters only if applied and reg number exists
          if (initialFiltersApplied && canJoinLectures) ...[
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
            // Show lecture list only if filters applied and reg number exists
            child: initialFiltersApplied && canJoinLectures
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
                              // Check if this lecture is the one just successfully joined
                              final bool isSuccessfullyJoined = lecture.id == joinedLectureId;
                              // Check if this specific lecture is currently in the process of joining
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
                                    ? Chip( // Updated Chip for "Joined" status - no visit number
                                        avatar: Icon(Icons.check_circle_outline, size: 18, color: Colors.green.shade800),
                                        label: Text('Joined', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500)),
                                        backgroundColor: Colors.green.shade100,
                                        side: BorderSide.none, // Remove border
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      )
                                    : ElevatedButton(
                                        // Disable button if any join operation is in progress OR if student cannot join (no reg number)
                                        onPressed: (isJoining || !canJoinLectures)
                                            ? null
                                            : () => showJoinLectureDialog(lecture), // Call the dialog function
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: brandColor, // Use brand color for Join button
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // Pill shape
                                          minimumSize: const Size(80, 36), // Ensure minimum size
                                        ),
                                        child: isCurrentlyJoining // Show loading indicator only for the specific lecture being joined
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
                // Show placeholder if initial filters not applied OR if reg number is missing
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Show loading indicator while checking reg number or waiting for filters
                          if (!canJoinLectures && widget.currentUser.registrationNumber == null)
                             CircularProgressIndicator(color: brandColor) // Show loading if reg num check is pending (though initState handles this)
                          else
                             Icon(
                               canJoinLectures ? Icons.filter_list_off_outlined : Icons.warning_amber_rounded, // Different icon based on reason
                               size: 50,
                               color: canJoinLectures ? Colors.grey.shade400 : Colors.orange.shade600,
                             ),
                          const SizedBox(height: 20),
                          Text(
                            // Different message based on whether reg number is missing or filters not selected
                            canJoinLectures
                              ? 'Please select your Year and Semester\nto view available lectures.'
                              : 'Cannot load lectures.\nYour registration number might be missing.',
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
