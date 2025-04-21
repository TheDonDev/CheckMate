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

  // Lecture List State
  Future<List<Lecture>>? lecturesFuture;
  // Unified loading state: Tracks the ID of the lecture being processed (join or check-in)
  String? _processingLectureId;

  // Filter State
  String? fixedSchool;
  String? fixedDepartment;
  String? fixedCourse;
  String? selectedYear;
  String? selectedSemester;
  bool initialFiltersApplied = false;

  // --- Attendance Summary State ---
  bool _isLoadingSummary = true;
  String? _summaryError;
  String? _attendancePercentage; // Store as String (e.g., "80.00")
  int? _totalLectures;
  int? _attendedLectures;
  // *** Store the detailed records from the summary ***
  List<AttendanceRecord>? _summaryAttendanceRecords;
  // --- End Attendance Summary State ---

  // Define the brand color (consistent styling)
  static const Color brandColor = Color(0xFF0175C2);

  @override
  void initState() {
    super.initState();
    // Pre-fill fixed filters from user profile
    fixedSchool = widget.currentUser.school;
    fixedDepartment = widget.currentUser.department;
    fixedCourse = widget.currentUser.course;

    // Check if the student has a registration number.
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
          // Also load the initial attendance summary
          _loadAttendanceSummary(); // Load summary after potentially showing filter dialog
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
      year: null, semester: null,
    );

    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context,
      barrierDismissible: false,
      builder: (context) => LectureFilterDialog(
        initialFilters: initialData,
        isInitialSelection: true,
        fixedSchool: fixedSchool,
        fixedDepartment: fixedDepartment,
        fixedCourse: fixedCourse,
      ),
    );

    if (selectedFilters != null && selectedFilters.year != null && selectedFilters.semester != null && mounted) {
      setState(() {
        selectedYear = selectedFilters.year;
        selectedSemester = selectedFilters.semester;
        initialFiltersApplied = true;
      });
      loadLectures(); // Load lectures based on the selected filters
      // Reload summary as well, in case relevant lectures changed
      _loadAttendanceSummary();
    } else if (mounted) {
      if (kDebugMode) print("Initial filter dialog closed unexpectedly or without valid selection.");
    }
  }

  // Show the filter dialog again to allow refining Year and Semester.
  Future<void> showRefineFilterDialog() async {
    final currentFilters = LectureFilterData(
      school: fixedSchool, department: fixedDepartment, course: fixedCourse,
      year: selectedYear, semester: selectedSemester,
    );

    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context,
      barrierDismissible: true,
      builder: (context) => LectureFilterDialog(
        initialFilters: currentFilters,
        isInitialSelection: false,
        fixedSchool: fixedSchool,
        fixedDepartment: fixedDepartment,
        fixedCourse: fixedCourse,
      ),
    );

    if (selectedFilters != null && mounted) {
      if (selectedFilters.year != selectedYear || selectedFilters.semester != selectedSemester) {
        setState(() {
          selectedYear = selectedFilters.year;
          selectedSemester = selectedFilters.semester;
          // Clear summary records when filters change, they will be reloaded
          _summaryAttendanceRecords = null;
        });
        loadLectures(); // Reload lectures with new filters
        // Reload summary as filters might change the total relevant lectures
        _loadAttendanceSummary();
      }
    }
  }

  // Load lectures based on the currently selected filters.
  void loadLectures() {
    if (!initialFiltersApplied || selectedYear == null || selectedSemester == null) {
      if (lecturesFuture != null && mounted) {
         setState(() { lecturesFuture = null; });
      }
      return;
    }
    if (!mounted) return;
    setState(() {
      // Don't clear joinedLectureId here, rely on _summaryAttendanceRecords
      lecturesFuture = apiService.getStudentLectures(
        fixedSchool, fixedDepartment, fixedCourse, selectedYear, selectedSemester,
      );
    });
  }

  // --- Load Attendance Summary (Modified) ---
  Future<void> _loadAttendanceSummary() async {
    if (!mounted || widget.currentUser.id.isEmpty) return;
    if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
        setState(() {
            _isLoadingSummary = false;
            _summaryError = "Registration number missing.";
            _summaryAttendanceRecords = null; // Clear records on error
        });
        return;
    }

    setState(() {
      _isLoadingSummary = true;
      _summaryError = null;
    });
    try {
      final summaryData = await apiService.getStudentAttendanceSummary(widget.currentUser.id);
      if (!mounted) return;

      setState(() {
        _attendancePercentage = summaryData['percentage'] as String?;
        _totalLectures = summaryData['totalLectures'] as int?;
        _attendedLectures = summaryData['attendedLectures'] as int?;
        // *** Store the fetched records ***
        _summaryAttendanceRecords = summaryData['attendanceRecords'] as List<AttendanceRecord>?;
        _isLoadingSummary = false;
      });
      print("Attendance Summary Loaded: $_attendancePercentage% ($_attendedLectures/$_totalLectures). Records: ${_summaryAttendanceRecords?.length ?? 0}");
    } catch (e) {
      if (!mounted) return;
      print("Error loading attendance summary: $e");
      setState(() {
        _summaryError = e is ApiException ? e.message : e.toString();
        _isLoadingSummary = false;
        _attendancePercentage = null;
        _totalLectures = null;
        _attendedLectures = null;
        _summaryAttendanceRecords = null; // Clear records on error
      });
    }
  }
  // --- End Load Attendance Summary ---

  // --- Handle Student Joining a Lecture (Manual Button) ---
  Future<void> _handleStudentJoin(Lecture lecture) async {
    final studentRegNum = widget.currentUser.registrationNumber;
    if (studentRegNum == null || studentRegNum.isEmpty) {
      showSnackBar('Error: Your registration number is missing. Cannot join lecture.', isError: true);
      return;
    }
    // Prevent concurrent operations
    if (_processingLectureId != null) return;

    setState(() { _processingLectureId = lecture.id; });

    try {
      // Call the joinLecture API - Backend now handles setting checkedIn=false
      final AttendanceRecord attendanceRecord = await apiService.joinLecture(lecture.id);
      if (!mounted) return;

      // Update local state immediately for UI feedback (or rely on refresh)
      // Option 1: Refresh summary (safer for consistency)
      await _loadAttendanceSummary(); // Refresh summary to get the updated record list

      showSnackBar('Successfully joined ${lecture.unitName}!', isError: false);

    } catch (e) {
      if (!mounted) return;
      // Check for specific error messages from backend if needed
      if (e is ApiException && e.statusCode == 409) { // Example: Conflict/Already Joined
         showSnackBar('You have already joined ${lecture.unitName}.', isError: false);
         // Optionally refresh summary if state might be stale
         await _loadAttendanceSummary();
      } else {
         showSnackBar('Failed to join lecture: ${e.toString()}', isError: true);
      }
    } finally {
      if (mounted) { setState(() { _processingLectureId = null; }); }
    }
  }


  // Show a confirmation dialog before joining a lecture manually.
  Future<void> showJoinLectureDialog(Lecture lecture) async {
     final studentRegNum = widget.currentUser.registrationNumber;
    if (studentRegNum == null || studentRegNum.isEmpty) {
      showSnackBar('Error: Your registration number is missing. Cannot join lecture.', isError: true);
      return;
    }
    // Check if already processing this or another lecture
    if (_processingLectureId != null) return;

    // Check if already joined or checked in based on local state
    final currentRecord = _summaryAttendanceRecords?.firstWhereOrNull((r) => r.lectureId == lecture.id);
    if (currentRecord != null) {
       // *** Use checkedIn instead of isCheckedIn ***
       showSnackBar(currentRecord.checkedIn ? 'You are already checked in for this lecture.' : 'You have already joined this lecture.', isError: false);
       return;
    }

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

    if (confirmed == true && mounted) {
       // Call the unified join handler
       await _handleStudentJoin(lecture);
    }
  }

  // --- Function to handle QR Code Scan (Student scans Lecture QR for CHECK-IN) ---
  Future<void> _scanLectureQrAndCheckIn() async {
     if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
       showSnackBar('Error: Your registration number is missing. Cannot check in via QR.', isError: true);
       return;
    }
    // Prevent concurrent operations
    if (_processingLectureId != null) return;

    final String? scannedLectureId = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (!mounted) return;

    if (scannedLectureId != null && scannedLectureId.isNotEmpty) {
      print("Scanned Lecture ID for Check-In: $scannedLectureId");
      setState(() { _processingLectureId = scannedLectureId; }); // Indicate processing for this lecture

      try {
        // *** Call the NEW API endpoint for student check-in via lecture QR ***
        final AttendanceRecord attendanceRecord = await apiService.checkInViaLectureQr(scannedLectureId);
        if (!mounted) return;

        // Refresh summary to get the updated record list (including checkedIn=true)
        await _loadAttendanceSummary();

        // Find lecture name for snackbar message (best effort)
        String lectureName = "lecture";
        if (lecturesFuture != null) {
           try {
              final lectures = await lecturesFuture;
              final Lecture? foundLecture = lectures?.firstWhereOrNull((l) => l.id == scannedLectureId);
              if (foundLecture != null) { lectureName = "'${foundLecture.unitName}'"; }
           } catch (_) { /* Ignore if future failed */ }
        }
        showSnackBar('Successfully checked in for $lectureName!', isError: false);

      } catch (e) {
        if (!mounted) return;
        // Handle specific errors from the new API endpoint
        if (e is ApiException && (e.statusCode == 400 || e.statusCode == 404)) {
           showSnackBar('Check-in failed: You must join the lecture first.', isError: true);
        } else if (e is ApiException && e.statusCode == 409) {
           showSnackBar('Check-in failed: You are already checked in.', isError: true);
           // Optionally refresh summary if state might be stale
           await _loadAttendanceSummary();
        } else {
           showSnackBar('QR Check-in failed: ${e.toString()}', isError: true);
        }
      } finally {
        if (mounted) {
          setState(() { _processingLectureId = null; }); // Reset processing flag
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

  // --- Widget to Build Attendance Summary Card ---
  Widget _buildAttendanceSummaryCard() {
    // Handle loading state
    if (_isLoadingSummary) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: brandColor)),
      );
    }

    // Handle error state
    if (_summaryError != null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.red.shade50,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Could not load attendance summary: $_summaryError',
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: Colors.red.shade700),
                tooltip: 'Retry Loading Summary',
                onPressed: _loadAttendanceSummary,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              )
            ],
          ),
        ),
      );
    }

    // Handle state where data hasn't loaded or is unavailable
    if (_attendancePercentage == null || _attendedLectures == null || _totalLectures == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, color: Colors.grey.shade500),
              const SizedBox(width: 10),
              Text(
                'Attendance summary is currently unavailable.',
                style: TextStyle(color: Colors.grey.shade600),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    // --- Build the actual summary card ---
    double percentageValue = double.tryParse(_attendancePercentage!) ?? 0.0;
    double progressValue = (percentageValue / 100.0).clamp(0.0, 1.0);
    Color progressColor = percentageValue >= 75 ? Colors.green.shade600 : (percentageValue >= 50 ? Colors.orange.shade700 : Colors.red.shade600);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Attendance Summary',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: brandColor),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    _totalLectures == 0
                        ? '0 / 0 Lectures Attended'
                        : '$_attendedLectures / $_totalLectures Lectures Attended',
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '${_attendancePercentage!}%',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: progressColor,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressValue,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }
  // --- End Attendance Summary Card Widget ---


  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final textTheme = Theme.of(context).textTheme;
    final bool canPerformActions = widget.currentUser.registrationNumber != null && widget.currentUser.registrationNumber!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
         title: Text('Student Dashboard - ${widget.currentUser.name}', style: const TextStyle(fontSize: 18)),
         backgroundColor: brandColor,
         foregroundColor: Colors.white,
         elevation: 2.0,
         actions: [
            // Show loading indicator if joining/scanning
            if (_processingLectureId != null) // Unified loading indicator
              const Padding(
                padding: EdgeInsets.only(right: 15.0),
                child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
              ),
            IconButton(
              icon: Icon(Icons.edit_calendar_outlined, color: initialFiltersApplied && canPerformActions ? Colors.white : Colors.white54),
              tooltip: 'Change Year/Semester',
              // Disable if processing
              onPressed: initialFiltersApplied && canPerformActions && _processingLectureId == null
                         ? showRefineFilterDialog
                         : null,
            ),
            IconButton(
              icon: Icon(Icons.refresh, color: initialFiltersApplied && canPerformActions ? Colors.white : Colors.white54),
              tooltip: 'Refresh Lectures & Summary',
              // Disable if processing
              onPressed: initialFiltersApplied && canPerformActions && _processingLectureId == null
                ? () async {
                    loadLectures();
                    await _loadAttendanceSummary();
                  }
                : null,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              // Disable if processing
              onPressed: (_processingLectureId != null) ? null : () async {
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
                if (confirm && mounted) {
                  await authService.logout();
                  Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, );
                }
              },
            ),
         ],
      ),
      floatingActionButton: canPerformActions
          ? FloatingActionButton.extended(
              // *** Use the updated QR scan function for CHECK-IN ***
              onPressed: (_processingLectureId != null) ? null : _scanLectureQrAndCheckIn,
              label: const Text('Scan QR'),
              icon: const Icon(Icons.qr_code_scanner),
              backgroundColor: brandColor,
              foregroundColor: Colors.white,
              // *** Updated tooltip ***
              tooltip: 'Scan Lecture QR Code to Check-In',
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // --- Display Attendance Summary Card ---
          if (canPerformActions)
             _buildAttendanceSummaryCard(),
          // --- End Attendance Summary Card ---

          // Display selected filters if they have been applied.
          if (initialFiltersApplied && canPerformActions) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
              child: Text(
                "Available Lectures",
                style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: brandColor),
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

          // Main content area: Either lecture list or placeholder message.
          Expanded(
            child: initialFiltersApplied && canPerformActions
                ? RefreshIndicator(
                    color: brandColor,
                    onRefresh: () async {
                       loadLectures();
                       await _loadAttendanceSummary();
                    },
                    child: FutureBuilder<List<Lecture>>(
                      future: lecturesFuture,
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
                        // Empty state
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

                        // --- Success: Display Lecture List (Modified Trailing Widget Logic) ---
                        final lectures = snapshot.data!;
                        lectures.sort((a, b) {
                           final aTime = a.startTime; final bTime = b.startTime;
                           if (aTime == null && bTime == null) return 0;
                           if (aTime == null) return 1; if (bTime == null) return -1;
                           return aTime.compareTo(bTime);
                        });

                        return ListView.builder(
                           physics: const AlwaysScrollableScrollPhysics(),
                           padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 80), // Add bottom padding for FAB
                           itemCount: lectures.length,
                           itemBuilder: (context, index) {
                              final lecture = lectures[index];
                              // *** Determine status based on _summaryAttendanceRecords ***
                              final attendanceRecord = _summaryAttendanceRecords?.firstWhereOrNull((r) => r.lectureId == lecture.id);
                              // *** Use checkedIn instead of isCheckedIn ***
                              final bool isJoined = attendanceRecord != null && !attendanceRecord.checkedIn;
                              final bool isCheckedIn = attendanceRecord != null && attendanceRecord.checkedIn;
                              final bool isCurrentlyProcessing = _processingLectureId == lecture.id; // Check if THIS lecture is being processed

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6.0),
                                elevation: 1.5,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                  leading: CircleAvatar(
                                    backgroundColor: brandColor.withOpacity(0.1),
                                    child: Icon(
                                       // *** Use isCheckedIn instead of checkedIn ***
                                       isCheckedIn ? Icons.check_circle : (isJoined ? Icons.hourglass_top_rounded : Icons.schedule_outlined), // Updated icon logic
                                       color: brandColor
                                    ),
                                  ),
                                  title: Text('${lecture.unitName} (${lecture.unitCode})', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 4.0),
                                    child: Text(
                                      'Lecturer: ${lecture.lecturerName}\n${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}\nVenue: ${lecture.venue}',
                                      style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3),
                                    ),
                                  ),
                                  isThreeLine: true,
                                  // --- Updated Trailing Widget Logic ---
                                  // *** Use isCheckedIn instead of checkedIn ***
                                  trailing: isCheckedIn
                                    ? Chip( // Checked In Status
                                        avatar: Icon(Icons.check_circle, size: 18, color: Colors.green.shade800),
                                        label: Text('Checked In', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500)),
                                        backgroundColor: Colors.green.shade100,
                                        side: BorderSide.none, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                      )
                                    : isJoined
                                      ? Chip( // Joined Status (Ready for QR Check-in)
                                          avatar: Icon(Icons.hourglass_bottom_rounded, size: 18, color: Colors.orange.shade800),
                                          label: Text('Joined', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w500)),
                                          backgroundColor: Colors.orange.shade100,
                                          side: BorderSide.none, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        )
                                      : ElevatedButton( // Join Button
                                          // Disable if ANY lecture is being processed
                                          onPressed: (_processingLectureId != null || !canPerformActions)
                                              ? null
                                              : () => showJoinLectureDialog(lecture), // Trigger manual join confirmation
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: brandColor, foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            minimumSize: const Size(80, 36),
                                          ),
                                          // Show loading only if THIS lecture is being processed
                                          child: isCurrentlyProcessing
                                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                            : const Text('Join'),
                                        ),
                                  // --- End Trailing Widget Logic ---
                                ),
                              );
                           },
                        );
                      },
                    ),
                  )
                // Placeholder if initial filters not applied OR if reg number is missing.
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
                          if (!initialFiltersApplied && canPerformActions)
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
