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

// --- Import the QR Scanner Screen ---
import 'package:checkmate/screens/qr_scanner_screen.dart'; // Ensure this path is correct

// --- Import collection package ---
import 'package:collection/collection.dart'; // Import for firstWhereOrNull

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
  bool isJoining = false; // Loading state for the manual join button/dialog
  String? _joiningLectureIdTemp; // Track which lecture is being joined manually

  // --- Add QR Check-in State ---
  bool _isCheckingInViaQr = false; // Loading state for QR check-in process

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
      // UI will show a placeholder message.
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
    });
  }

  // Show a confirmation dialog before joining a lecture manually.
  Future<void> showJoinLectureDialog(Lecture lecture) async {
    final studentRegNum = widget.currentUser.registrationNumber;
    if (studentRegNum == null || studentRegNum.isEmpty) {
      showSnackBar('Error: Your registration number is missing. Cannot join lecture.', isError: true);
      return;
    }
    if (isJoining || _isCheckingInViaQr) return; // Prevent if already processing

    setState(() { isJoining = true; _joiningLectureIdTemp = lecture.id; });

    final confirmed = await showDialog<bool>(
      context: context, barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text('Confirm Join: ${lecture.unitName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('You are about to join this lecture using your registered number:'),
              const SizedBox(height: 10),
              InputChip(
                label: Text(studentRegNum, style: TextStyle(fontWeight: FontWeight.bold, color: brandColor)),
                avatar: Icon(Icons.badge_outlined, color: brandColor),
                backgroundColor: brandColor.withOpacity(0.1), side: BorderSide.none, isEnabled: false,
              ),
              const SizedBox(height: 15),
              Text('Date: ${lecture.formattedDate}'), Text('Time: ${lecture.formattedStartTime} - ${lecture.formattedEndTime}'), Text('Venue: ${lecture.venue}'),
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.login), label: const Text('Confirm Join'),
              style: ElevatedButton.styleFrom(backgroundColor: brandColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
       if (mounted) { setState(() { isJoining = false; _joiningLectureIdTemp = null; }); }
       return;
    }

    try {
      // Use the existing joinLecture API call
      final AttendanceRecord attendanceRecord = await apiService.joinLecture(lecture.id);
      if (!mounted) return;
      setState(() { joinedLectureId = lecture.id; });
      showSnackBar('Successfully joined ${lecture.unitName}!', isError: false);
    } catch (e) {
      if (!mounted) return;
      showSnackBar('Failed to join lecture: ${e.toString()}', isError: true);
    } finally {
      if (mounted) { setState(() { isJoining = false; _joiningLectureIdTemp = null; }); }
    }
  }

  // --- Function to handle QR Code Scan and Check-In ---
  Future<void> _scanAndCheckIn() async {
    // Prevent action if registration number is missing or already processing
    if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
       showSnackBar('Error: Your registration number is missing. Cannot check in.', isError: true);
       return;
    }
    if (_isCheckingInViaQr || isJoining) return;

    // Navigate to the scanner screen and wait for a result (lectureId)
    final String? scannedLectureId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (!mounted) return; // Check again after await

    if (scannedLectureId != null && scannedLectureId.isNotEmpty) {
      print("Scanned Lecture ID: $scannedLectureId"); // Debug log

      // Show loading indicator
      setState(() { _isCheckingInViaQr = true; });

      try {
        // Call the existing joinLecture method, passing the scanned lecture ID
        final AttendanceRecord attendanceRecord = await apiService.joinLecture(scannedLectureId);

        if (!mounted) return; // Check mount status after async gap

        // Update UI: Mark the specific lecture as joined/checked-in if it's currently displayed
        setState(() {
           joinedLectureId = scannedLectureId; // Mark for potential UI update in list builder
        });

        // Find lecture name for better feedback (optional, requires searching the list)
        String lectureName = "lecture"; // Default
        if (lecturesFuture != null) {
           try {
              // Await the future to get the list if it's not already completed
              final lectures = await lecturesFuture;
              // --- CORRECTED: Use firstWhereOrNull ---
              final Lecture? foundLecture = lectures?.firstWhereOrNull(
                  (l) => l.id == scannedLectureId
              );
              // --- END CORRECTION ---
              // Check if foundLecture is not null before accessing its properties
              if (foundLecture != null) {
                 lectureName = "'${foundLecture.unitName}'";
              }
           } catch (_) { /* Ignore error if future fails here, use default name */ }
        }
        showSnackBar('Successfully checked in for $lectureName!', isError: false);
        // Optionally refresh the list if the backend might filter out joined lectures
        // loadLectures();

      } catch (e) {
        if (!mounted) return; // Check mount status after async gap
        showSnackBar('QR Check-in failed: ${e.toString()}', isError: true);
      } finally {
        // Hide loading indicator regardless of success/failure
        if (mounted) {
          setState(() { _isCheckingInViaQr = false; });
        }
      }
    } else {
      print("QR Scan cancelled or returned empty lecture ID.");
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
    // Determine if student can perform actions (based on registration number existence).
    final bool canPerformActions = widget.currentUser.registrationNumber != null && widget.currentUser.registrationNumber!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
        title: Text('Student Dashboard - ${widget.currentUser.name}', style: const TextStyle(fontSize: 18)),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        elevation: 2.0,
        actions: [
           // --- Show loading indicator in AppBar if checking in via QR ---
           if (_isCheckingInViaQr)
             const Padding(
               padding: EdgeInsets.only(right: 15.0),
               child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
             ),
           // Button to refine filters. Disabled if initial filters not set or cannot perform actions.
           IconButton(
             icon: Icon(Icons.edit_calendar_outlined, color: initialFiltersApplied && canPerformActions ? Colors.white : Colors.white54),
             tooltip: 'Change Year/Semester',
             onPressed: initialFiltersApplied && canPerformActions && !_isCheckingInViaQr ? showRefineFilterDialog : null,
           ),
           // Button to refresh lectures. Disabled if initial filters not set or cannot perform actions.
           IconButton(
             icon: Icon(Icons.refresh, color: initialFiltersApplied && canPerformActions ? Colors.white : Colors.white54),
             tooltip: 'Refresh Lectures',
             onPressed: initialFiltersApplied && canPerformActions && !_isCheckingInViaQr ? loadLectures : null,
           ),
           // Logout button. Disabled if checking in.
           IconButton(
             icon: const Icon(Icons.logout),
             tooltip: 'Logout',
             onPressed: _isCheckingInViaQr ? null : () async {
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
      // --- Add Floating Action Button for QR Scan ---
      floatingActionButton: canPerformActions // Only show FAB if student can perform actions
          ? FloatingActionButton.extended(
              onPressed: _isCheckingInViaQr ? null : _scanAndCheckIn, // Disable while processing
              label: const Text('Scan QR'),
              icon: const Icon(Icons.qr_code_scanner),
              backgroundColor: brandColor,
              foregroundColor: Colors.white,
              tooltip: 'Scan Lecture QR Code to Check-In',
            )
          : null, // Don't show FAB if reg number is missing
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat, // Position FAB
      // --- End FAB ---
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Display selected filters if they have been applied.
          if (initialFiltersApplied && canPerformActions) ...[
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
            child: initialFiltersApplied && canPerformActions
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
                          final aTime = a.startTime; final bTime = b.startTime;
                          if (aTime == null && bTime == null) return 0;
                          if (aTime == null) return 1; if (bTime == null) return -1;
                          return aTime.compareTo(bTime);
                        });

                        // Build the list view
                        return ListView.builder(
                           physics: const AlwaysScrollableScrollPhysics(), // Ensure scrolling for RefreshIndicator
                           padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 80), // Add bottom padding for FAB
                           itemCount: lectures.length,
                           itemBuilder: (context, index) {
                              final lecture = lectures[index];
                              // Check if this lecture was the one just successfully joined/checked-in.
                              final bool isSuccessfullyJoined = lecture.id == joinedLectureId;
                              // Check if this specific lecture is currently being joined manually.
                              final bool isCurrentlyJoiningManually = isJoining && _joiningLectureIdTemp == lecture.id;

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
                                    // Show "Joined" chip if successfully joined/checked-in.
                                    ? Chip(
                                        avatar: Icon(Icons.check_circle, size: 18, color: Colors.green.shade800), // Use filled check
                                        label: Text('Checked In', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500)),
                                        backgroundColor: Colors.green.shade100,
                                        side: BorderSide.none,
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      )
                                    // Show "Join" button otherwise.
                                    : ElevatedButton(
                                        // Disable button if any join/scan is in progress or if student cannot perform actions.
                                        onPressed: (isJoining || _isCheckingInViaQr || !canPerformActions)
                                            ? null
                                            : () => showJoinLectureDialog(lecture), // Trigger manual join confirmation
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: brandColor,
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                          minimumSize: const Size(80, 36),
                                        ),
                                        // Show loading indicator or "Join" text.
                                        child: isCurrentlyJoiningManually
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
                          Icon(
                            canPerformActions ? Icons.filter_list_off_outlined : Icons.warning_amber_rounded,
                            size: 50,
                            color: canPerformActions ? Colors.grey.shade400 : Colors.orange.shade600,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            canPerformActions
                              ? 'Please select your Year and Semester\nto view available lectures.'
                              : 'Cannot load lectures.\nYour registration number might be missing.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                          ),
                          // Add a button to retry initial filter selection if needed
                          if (!initialFiltersApplied && canPerformActions) // Corrected condition: Show if initial filters not applied AND can perform actions
                             Padding(
                               padding: const EdgeInsets.only(top: 15.0),
                               child: ElevatedButton.icon(
                                 icon: const Icon(Icons.filter_list),
                                 label: const Text('Select Year/Semester'),
                                 onPressed: showInitialFilterDialog,
                                 style: ElevatedButton.styleFrom(backgroundColor: brandColor, foregroundColor: Colors.white),
                               ),
                             )
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
