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
import 'package:flutter/foundation.dart'; // Import for kDebugMode

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
  bool isJoining = false; // Loading state for the join button/dialog
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
    // Pre-fill fixed filters from user profile
    fixedSchool = widget.currentUser.school;
    fixedDepartment = widget.currentUser.department;
    fixedCourse = widget.currentUser.course;

    // Check if the student has a registration number. If not, show an error and prevent further action.
    if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) {
           _showMissingRegNumError();
         }
       });
    } else {
      // If registration number exists, prompt for initial year/semester filters.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showInitialFilterDialog();
        }
      });
    }
  }

  // Show error dialog if student registration number is missing and force logout.
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
                 // Log out the user using AuthService from Provider
                 await Provider.of<AuthService>(context, listen: false).logout();
                 if (mounted) {
                    // Navigate to WelcomeScreen and remove all previous routes
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

  // Show the initial filter dialog to select Year and Semester.
  Future<void> showInitialFilterDialog() async {
    final initialData = LectureFilterData(
      school: fixedSchool, department: fixedDepartment, course: fixedCourse,
      year: null, semester: null, // Start with null year/semester
    );

    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context,
      barrierDismissible: false, // Prevent closing without selection
      builder: (context) => LectureFilterDialog(
        initialFilters: initialData,
        isInitialSelection: true, // Indicate this is the first mandatory selection
        fixedSchool: fixedSchool, // Pass fixed values
        fixedDepartment: fixedDepartment,
        fixedCourse: fixedCourse,
      ),
    );

    // If valid filters were selected, update state and load lectures.
    if (selectedFilters != null && selectedFilters.year != null && selectedFilters.semester != null && mounted) {
      setState(() {
        selectedYear = selectedFilters.year;
        selectedSemester = selectedFilters.semester;
        initialFiltersApplied = true; // Mark that initial filters are set
      });
      loadLectures(); // Load lectures based on the selected filters
    } else if (mounted) {
      // Handle case where dialog was closed without selection (e.g., back button)
      if (kDebugMode) print("Initial filter dialog closed unexpectedly or without valid selection.");
      // Optionally show an error or force the dialog again if initial selection is critical.
      // For now, the UI will show a placeholder message.
    }
  }

  // Show the filter dialog again to allow refining Year and Semester.
  Future<void> showRefineFilterDialog() async {
    final currentFilters = LectureFilterData(
      school: fixedSchool, department: fixedDepartment, course: fixedCourse,
      year: selectedYear, semester: selectedSemester, // Pass current selections
    );

    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context,
      barrierDismissible: true, // Allow dismissing this time
      builder: (context) => LectureFilterDialog(
        initialFilters: currentFilters,
        isInitialSelection: false, // Indicate this is for refining
        fixedSchool: fixedSchool,
        fixedDepartment: fixedDepartment,
        fixedCourse: fixedCourse,
      ),
    );

    // If new filters were selected and they differ from current ones, update state and reload.
    if (selectedFilters != null && mounted) {
      if (selectedFilters.year != selectedYear || selectedFilters.semester != selectedSemester) {
        setState(() {
          selectedYear = selectedFilters.year;
          selectedSemester = selectedFilters.semester;
          joinedLectureId = null; // Reset joined status when filters change
        });
        loadLectures(); // Reload lectures with new filters
      }
    }
  }

  // Load lectures based on the currently selected filters.
  void loadLectures() {
    // Don't attempt to load if initial filters haven't been applied or are invalid.
    if (!initialFiltersApplied || selectedYear == null || selectedSemester == null) {
      // Clear any existing future if filters become invalid
      if (lecturesFuture != null && mounted) {
         setState(() { lecturesFuture = null; });
      }
      return;
    }
    if (!mounted) return; // Check if widget is still mounted
    setState(() {
      joinedLectureId = null; // Reset joined status indicator on each load/refresh
      // Call ApiService to get lectures matching the filters
      lecturesFuture = apiService.getStudentLectures(
        fixedSchool, fixedDepartment, fixedCourse, selectedYear, selectedSemester,
      );
      // TODO: Optionally, fetch the student's current attendance status for these lectures
      // to pre-mark lectures they already joined in this session.
    });
  }

  // Show a confirmation dialog before joining a lecture.
  Future<void> showJoinLectureDialog(Lecture lecture) async {
    // Double-check registration number existence.
    final studentRegNum = widget.currentUser.registrationNumber;
    if (studentRegNum == null || studentRegNum.isEmpty) {
      showSnackBar('Error: Your registration number is missing. Cannot join lecture.', isError: true);
      return;
    }

    // Prevent multiple concurrent join attempts.
    if (isJoining) return;

    // Set loading state specific to this lecture join attempt.
    setState(() {
      isJoining = true;
      _joiningLectureIdTemp = lecture.id;
    });

    // Show confirmation dialog.
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text('Confirm Join: ${lecture.unitName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('You are about to join this lecture using your registered number:'),
              const SizedBox(height: 10),
              // Display registration number read-only.
              InputChip(
                label: Text(studentRegNum, style: TextStyle(fontWeight: FontWeight.bold, color: brandColor)),
                avatar: Icon(Icons.badge_outlined, color: brandColor),
                backgroundColor: brandColor.withOpacity(0.1),
                side: BorderSide.none,
                isEnabled: false,
              ),
              const SizedBox(height: 15),
              // Display lecture details.
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

    // If dialog was cancelled, reset loading state and exit.
    if (confirmed != true) {
       if (mounted) {
         setState(() { isJoining = false; _joiningLectureIdTemp = null; });
       }
       return;
    }

    // --- Proceed with API call if confirmed ---
    try {
      // *** CORRECTED API CALL: Only pass lectureId ***
      // Backend uses the auth token to identify the student.
      final AttendanceRecord attendanceRecord = await apiService.joinLecture(lecture.id);

      if (!mounted) return; // Check mount status after async gap
      // Update UI to show "Joined" status for this lecture.
      setState(() {
        joinedLectureId = lecture.id;
      });
      showSnackBar('Successfully joined ${lecture.unitName}!', isError: false);
    } catch (e) {
      if (!mounted) return; // Check mount status after async gap
      showSnackBar('Failed to join lecture: ${e.toString()}', isError: true);
      // Note: We don't reset joinedLectureId on failure, as the user might have already joined previously
      // and the error could be temporary (e.g., network). The UI will just show the error.
    } finally {
      // Reset loading state regardless of success/failure.
      if (mounted) {
        setState(() { isJoining = false; _joiningLectureIdTemp = null; });
      }
    }
  }

  // Helper to show snackbar messages.
  void showSnackBar(String message, {bool isError = false}) {
     if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(message),
         backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,
         behavior: SnackBarBehavior.floating,
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
         margin: const EdgeInsets.all(10),
       ),
     );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final textTheme = Theme.of(context).textTheme;
    // Determine if student can join lectures (based on registration number existence).
    final bool canJoinLectures = widget.currentUser.registrationNumber != null && widget.currentUser.registrationNumber!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Student Dashboard - ${widget.currentUser.name}', style: const TextStyle(fontSize: 18)),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        elevation: 2.0,
        actions: [
           // Button to refine filters. Disabled if initial filters not set or cannot join.
           IconButton(
             icon: Icon(Icons.edit_calendar_outlined, color: initialFiltersApplied ? Colors.white : Colors.white54),
             tooltip: 'Change Year/Semester',
             onPressed: initialFiltersApplied && canJoinLectures ? showRefineFilterDialog : null,
           ),
           // Button to refresh lectures. Disabled if initial filters not set or cannot join.
           IconButton(
             icon: Icon(Icons.refresh, color: initialFiltersApplied ? Colors.white : Colors.white54),
             tooltip: 'Refresh Lectures',
             onPressed: initialFiltersApplied && canJoinLectures ? loadLectures : null,
           ),
           // Logout button.
           IconButton(
             icon: const Icon(Icons.logout),
             tooltip: 'Logout',
             onPressed: () async {
                // Show confirmation dialog before logging out.
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    title: const Text('Confirm Logout'),
                    content: const Text('Are you sure you want to log out?'),
                    actions: [
                      TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: TextButton.styleFrom(foregroundColor: Colors.red),
                        child: const Text('Logout'),
                      ),
                    ],
                  ),
                ) ?? false;
                // If confirmed, perform logout and navigate to WelcomeScreen.
                if (confirm && mounted) {
                  await authService.logout();
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                    (Route<dynamic> route) => false, // Remove all previous routes
                  );
                }
             },
           ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Display selected filters if they have been applied.
          if (initialFiltersApplied && canJoinLectures) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 8.0),
              child: Text(
                "Available Lectures",
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: brandColor),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Wrap( // Use Wrap for filter chips
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

          // Main content area: Either lecture list or placeholder message.
          Expanded(
            child: initialFiltersApplied && canJoinLectures
                // If filters are applied and student can join, show lecture list.
                ? RefreshIndicator(
                    color: brandColor,
                    onRefresh: () async => loadLectures(), // Enable pull-to-refresh
                    child: FutureBuilder<List<Lecture>>(
                      future: lecturesFuture, // Use the future holding lecture data
                      builder: (context, snapshot) {
                        // Loading state
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator(color: brandColor));
                        }
                        // Error state
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
                                 style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                               )
                             ], ), )
                          );
                        }
                        // Empty state (no lectures found for filters)
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return LayoutBuilder(
                             builder: (context, constraints) { return SingleChildScrollView( physics: const AlwaysScrollableScrollPhysics(), child: ConstrainedBox( constraints: BoxConstraints(minHeight: constraints.maxHeight), child: Center( child: Padding( padding: const EdgeInsets.all(20.0), child: Column(
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
                        // Sort lectures: Earliest start time first (ascending)
                        lectures.sort((a, b) {
                          // *** Corrected Null-Safe Sorting (Ascending) ***
                          final aTime = a.startTime;
                          final bTime = b.startTime;

                          // Handle null times (treat null as later/less relevant)
                          if (aTime == null && bTime == null) {
                            return 0; // Both null, equal
                          } else if (aTime == null) {
                            return 1; // a (null) comes after b (non-null)
                          } else if (bTime == null) {
                            return -1; // b (null) comes after a (non-null)
                          } else {
                            // Both times non-null, compare ascending
                            return aTime.compareTo(bTime);
                          }
                          // Note: Date comparison removed as backend filters for upcoming lectures.
                        });

                        // Build the list view
                        return ListView.builder(
                           physics: const AlwaysScrollableScrollPhysics(), // Ensure scrolling for RefreshIndicator
                           padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                           itemCount: lectures.length,
                           itemBuilder: (context, index) {
                              final lecture = lectures[index];
                              // Check if this lecture was the one just successfully joined.
                              final bool isSuccessfullyJoined = lecture.id == joinedLectureId;
                              // Check if this specific lecture is currently being joined.
                              final bool isCurrentlyJoining = isJoining && _joiningLectureIdTemp == lecture.id;

                              // Build list tile for each lecture.
                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6.0),
                                elevation: 1.5,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                  leading: CircleAvatar(
                                    backgroundColor: brandColor.withOpacity(0.1),
                                    child: Icon(Icons.schedule_outlined, color: brandColor),
                                  ),
                                  title: Text('${lecture.unitName} (${lecture.unitCode})', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      'Lecturer: ${lecture.lecturerName}\n${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}\nVenue: ${lecture.venue}',
                                      style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3),
                                    ),
                                  ),
                                  isThreeLine: true, // Allow subtitle to wrap
                                  // Trailing widget: Either "Joined" chip or "Join" button.
                                  trailing: isSuccessfullyJoined
                                    // Show "Joined" chip if successfully joined.
                                    ? Chip(
                                        avatar: Icon(Icons.check_circle_outline, size: 18, color: Colors.green.shade800),
                                        label: Text('Joined', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500)),
                                        backgroundColor: Colors.green.shade100,
                                        side: BorderSide.none,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      )
                                    // Show "Join" button otherwise.
                                    : ElevatedButton(
                                        // Disable button if any join is in progress or if student cannot join.
                                        onPressed: (isJoining || !canJoinLectures)
                                            ? null
                                            : () => showJoinLectureDialog(lecture), // Trigger join confirmation
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: brandColor,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          minimumSize: const Size(80, 36),
                                        ),
                                        // Show loading indicator or "Join" text.
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
                // Show placeholder if initial filters not applied OR if reg number is missing.
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Show different icon/message based on the reason for not showing lectures.
                          Icon(
                            canJoinLectures ? Icons.filter_list_off_outlined : Icons.warning_amber_rounded,
                            size: 50,
                            color: canJoinLectures ? Colors.grey.shade400 : Colors.orange.shade600,
                          ),
                          const SizedBox(height: 20),
                          Text(
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
