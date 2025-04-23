// lib/screens/student_dashboard.dart
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/services/api_service.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:checkmate/widgets/lecture_filter_dialog.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:checkmate/screens/welcome_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:checkmate/screens/qr_scanner_screen.dart';
import 'package:collection/collection.dart';
// --- ADDED: Import url_launcher ---
import 'package:url_launcher/url_launcher.dart';
// --- END ADDED ---

class StudentDashboard extends StatefulWidget {
  final app_user.User currentUser;
  const StudentDashboard({super.key, required this.currentUser});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final ApiService apiService = ApiService();

  Future<List<Lecture>>? lecturesFuture;
  String? _processingLectureId; // Tracks which lecture action is currently processing

  // User profile details (fixed after login)
  String? fixedSchool;
  String? fixedDepartment;
  String? fixedCourse;

  // Filters selected by the user
  String? selectedYear;
  String? selectedSemester;
  bool initialFiltersApplied = false; // Flag to ensure initial filters are set

  // Attendance summary state
  bool _isLoadingSummary = true;
  String? _summaryError;
  String? _attendancePercentage;
  int? _totalLectures;
  int? _attendedLectures;
  List<AttendanceRecord>? _summaryAttendanceRecords; // Cache for status checks

  static const Color brandColor = Color(0xFF0175C2); // App's brand color

  @override
  void initState() {
    super.initState();
    // Store fixed user details
    fixedSchool = widget.currentUser.school;
    fixedDepartment = widget.currentUser.department;
    fixedCourse = widget.currentUser.course;

    // Check if registration number is present, crucial for attendance
    if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
       // Show error dialog after the first frame if reg number is missing
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) { _showMissingRegNumError(); }
       });
    } else {
      // If reg number exists, prompt for initial filters and load summary
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showInitialFilterDialog(); // Ask for Year/Semester
          _loadAttendanceSummary(); // Load overall summary
        }
      });
    }
  }

  // Dialog shown if student registration number is missing
  void _showMissingRegNumError() {
     showDialog(
        context: context,
        barrierDismissible: false, // Prevent dismissing by tapping outside
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
             children: [ Icon(Icons.error_outline, color: Colors.red), SizedBox(width: 10), Text('Registration Incomplete'), ],
          ),
          content: const Text('Your student registration number is missing.\nPlease contact support or re-register to use attendance features.'),
          actions: [
            TextButton(
              onPressed: () async {
                 Navigator.of(context).pop(); // Close dialog
                 await Provider.of<AuthService>(context, listen: false).logout(); // Log out user
                 if (mounted) {
                    // Navigate back to Welcome Screen, removing all previous routes
                    Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, );
                 }
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Logout'),
            ),
          ],
        ),
     );
  }

  // Shows the filter dialog initially to force Year/Semester selection
  Future<void> showInitialFilterDialog() async {
    final initialData = LectureFilterData( school: fixedSchool, department: fixedDepartment, course: fixedCourse, year: null, semester: null, );
    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context, barrierDismissible: false, // Must select initially
      builder: (context) => LectureFilterDialog( initialFilters: initialData, isInitialSelection: true, fixedSchool: fixedSchool, fixedDepartment: fixedDepartment, fixedCourse: fixedCourse, ),
    );
    // If valid filters selected, update state and load lectures/summary
    if (selectedFilters != null && selectedFilters.year != null && selectedFilters.semester != null && mounted) {
      setState(() {
        selectedYear = selectedFilters.year;
        selectedSemester = selectedFilters.semester;
        initialFiltersApplied = true; // Mark initial selection as done
      });
      loadLectures(); // Fetch lectures based on new filters
      _loadAttendanceSummary(); // Refresh summary (though it might not change based on filters)
    } else if (mounted) {
      // Handle case where dialog is closed without selection (shouldn't happen if barrierDismissible=false)
      if (kDebugMode) print("Initial filter dialog closed unexpectedly or without valid selection.");
      // Optionally, show a message or retry? For now, lectures won't load.
    }
  }

  // Shows the filter dialog to allow changing Year/Semester later
  Future<void> showRefineFilterDialog() async {
    final currentFilters = LectureFilterData( school: fixedSchool, department: fixedDepartment, course: fixedCourse, year: selectedYear, semester: selectedSemester, );
    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context, barrierDismissible: true, // Allow closing without changing
      builder: (context) => LectureFilterDialog( initialFilters: currentFilters, isInitialSelection: false, fixedSchool: fixedSchool, fixedDepartment: fixedDepartment, fixedCourse: fixedCourse, ),
    );
    // If filters were selected and changed, update state and reload
    if (selectedFilters != null && mounted) {
      if (selectedFilters.year != selectedYear || selectedFilters.semester != selectedSemester) {
        setState(() {
          selectedYear = selectedFilters.year;
          selectedSemester = selectedFilters.semester;
          _summaryAttendanceRecords = null; // Clear cached summary records as filters changed
        });
        loadLectures(); // Fetch new lectures
        _loadAttendanceSummary(); // Refresh summary
      }
    }
  }

  // Fetches lectures from the API based on current filters
  void loadLectures() {
    // Don't load if initial filters haven't been applied or are invalid
    if (!initialFiltersApplied || selectedYear == null || selectedSemester == null) {
      if (lecturesFuture != null && mounted) { setState(() { lecturesFuture = null; }); } // Clear previous future if any
      return;
    }
    if (!mounted) return; // Check if widget is still mounted
    setState(() {
      // Call API service to get lectures for the student with current filters
      lecturesFuture = apiService.getStudentLectures( fixedSchool, fixedDepartment, fixedCourse, selectedYear, selectedSemester, );
    });
  }

  // Fetches the student's overall attendance summary
  Future<void> _loadAttendanceSummary() async {
    if (!mounted || widget.currentUser.id.isEmpty) return; // Check mount status and user ID
    // Don't load if registration number is missing
    if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
        setState(() { _isLoadingSummary = false; _summaryError = "Registration number missing."; _summaryAttendanceRecords = null; });
        return;
    }
    // Set loading state
    setState(() { _isLoadingSummary = true; _summaryError = null; });
    try {
      // Call API service
      final summaryData = await apiService.getStudentAttendanceSummary(widget.currentUser.id);
      if (!mounted) return; // Check mount status again after async call
      // Update state with fetched summary data
      setState(() {
        _attendancePercentage = summaryData['percentage'] as String?;
        _totalLectures = summaryData['totalLectures'] as int?;
        _attendedLectures = summaryData['attendedLectures'] as int?;
        // Store the list of records to check join/check-in status locally
        _summaryAttendanceRecords = summaryData['attendanceRecords'] as List<AttendanceRecord>?;
        _isLoadingSummary = false; // Mark loading as complete
      });
      if (kDebugMode) print("Attendance Summary Loaded: $_attendancePercentage% ($_attendedLectures/$_totalLectures). Records: ${_summaryAttendanceRecords?.length ?? 0}");
    } catch (e) {
      if (!mounted) return; // Check mount status after error
      if (kDebugMode) print("Error loading attendance summary: $e");
      // Update state to show error
      setState(() {
        _summaryError = e is ApiException ? e.message : e.toString(); // Use specific message if available
        _isLoadingSummary = false;
        // Clear summary data on error
        _attendancePercentage = null; _totalLectures = null; _attendedLectures = null; _summaryAttendanceRecords = null;
      });
    }
  }

  // --- URL Launcher Helper ---
  /// Launches the given URL string using url_launcher.
  /// Handles basic scheme checking and error reporting.
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString.trim()); // Trim whitespace
    // Ensure a scheme (http/https) is present, default to https if missing
    final Uri launchUri = url.hasScheme ? url : Uri.parse('https://$urlString');

    try {
      // Attempt to launch the URL in an external application (browser)
      if (!await launchUrl(launchUri, mode: LaunchMode.externalApplication)) {
        // If launchUrl returns false, it couldn't launch
        throw Exception('Could not launch URL');
      }
    } catch (e) {
      // Catch errors during parsing or launching
      if (mounted) {
        showSnackBar('Could not open link: $urlString', isError: true);
      }
      if (kDebugMode) print('Error launching URL $launchUri: $e');
    }
  }
  // --- END URL Launcher Helper ---

  // Handles the API call when a student confirms joining a lecture
  Future<void> _handleStudentJoin(Lecture lecture) async {
    final studentRegNum = widget.currentUser.registrationNumber;
    // Pre-checks
    if (studentRegNum == null || studentRegNum.isEmpty) {
      showSnackBar('Error: Your registration number is missing. Cannot join lecture.', isError: true); return;
    }
    if (_processingLectureId != null) return; // Prevent double taps

    // Set processing state
    setState(() { _processingLectureId = lecture.id; });
    try {
      // Call API to join
      await apiService.joinLecture(lecture.id);
      if (!mounted) return; // Check mount status after async call

      // Refresh summary and show success message FIRST
      await _loadAttendanceSummary();
      showSnackBar('Successfully joined ${lecture.unitName}!', isError: false);

      // --- *** MODIFIED: Auto-launch link for ONLINE lectures *** ---
      // Check if the venue is ONLINE (case-insensitive) and if a valid link exists
      if (lecture.venue.toUpperCase() == 'ONLINE' &&
          lecture.onlineLink != null &&
          lecture.onlineLink!.trim().isNotEmpty) {
        if (kDebugMode) print("Attempting to auto-launch online link after join: ${lecture.onlineLink}");
        // Use the helper function to launch the URL
        // Add a small delay to allow the snackbar to be seen briefly (optional)
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) { // Check mount status again before launching
            await _launchURL(lecture.onlineLink!);
        }
      }
      // --- *** END MODIFIED *** ---

    } catch (e) {
      if (!mounted) return; // Check mount status after error
      // Handle specific API errors (like already joined)
      if (e is ApiException && e.statusCode == 409) {
         showSnackBar('You have already joined ${lecture.unitName}.', isError: false);
         await _loadAttendanceSummary(); // Refresh just in case status was stale
      } else {
         // Show generic error
         showSnackBar('Failed to join lecture: ${e.toString()}', isError: true);
      }
    } finally {
      // Clear processing state regardless of success/failure
      if (mounted) { setState(() { _processingLectureId = null; }); }
    }
  }

  // Shows the confirmation dialog before joining a lecture
  Future<void> showJoinLectureDialog(Lecture lecture) async {
     final studentRegNum = widget.currentUser.registrationNumber;
    // Pre-checks
    if (studentRegNum == null || studentRegNum.isEmpty) {
      showSnackBar('Error: Your registration number is missing. Cannot join lecture.', isError: true); return;
    }
    if (_processingLectureId != null) return; // Prevent opening multiple dialogs

    // Check local summary cache if student has already joined/checked-in
    final currentRecord = _summaryAttendanceRecords?.firstWhereOrNull((r) => r.lectureId == lecture.id);
    if (currentRecord != null) {
       showSnackBar(currentRecord.checkedIn ? 'You are already checked in for this lecture.' : 'You have already joined this lecture.', isError: false);
       return; // Don't show dialog if already joined/checked-in
    }

    // Show confirmation dialog
    final confirmed = await showDialog<bool>(
      context: context, barrierDismissible: false, // Prevent closing without confirmation
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text('Confirm Join: ${lecture.unitName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('You are about to join this lecture using your registered number:'),
              const SizedBox(height: 10),
              // Display registration number clearly
              InputChip(
                label: Text(studentRegNum, style: TextStyle(fontWeight: FontWeight.bold, color: brandColor)),
                avatar: Icon(Icons.badge_outlined, color: brandColor),
                backgroundColor: brandColor.withOpacity(0.1),
                side: BorderSide.none,
                isEnabled: false, // Read-only chip
              ),
              const SizedBox(height: 15),
              // Display lecture details
              Text('Date: ${lecture.formattedDate}'),
              Text('Time: ${lecture.formattedStartTime} - ${lecture.formattedEndTime}'),
              Text('Venue: ${lecture.venue}'),
              // Display link if it's an online lecture
              if (lecture.venue.toUpperCase() == 'ONLINE' && lecture.onlineLink != null && lecture.onlineLink!.isNotEmpty) ...[
                 const SizedBox(height: 8),
                 // Make link selectable for copying if needed
                 SelectableText(
                    'Link: ${lecture.onlineLink}',
                    style: TextStyle(color: Colors.blue.shade800),
                    maxLines: 1,
                    // overflow: TextOverflow.ellipsis, // Removed ellipsis to show full link if possible
                 ),
              ]
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Confirm Join'),
              style: ElevatedButton.styleFrom(backgroundColor: brandColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              onPressed: () => Navigator.of(dialogContext).pop(true), // Confirm action
            ),
          ],
        );
      },
    );
    // If confirmed, handle the join action
    if (confirmed == true && mounted) { await _handleStudentJoin(lecture); }
  }

  // Handles scanning the lecturer's QR code for check-in
  Future<void> _scanLectureQrAndCheckIn() async {
     // Pre-checks
     if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
       showSnackBar('Error: Your registration number is missing. Cannot check in via QR.', isError: true); return;
    }
    if (_processingLectureId != null) return; // Prevent multiple scans

    // Navigate to QR Scanner screen
    final String? scannedLectureId = await Navigator.push<String>( context, MaterialPageRoute(builder: (context) => const QrScannerScreen()), );
    if (!mounted) return; // Check mount status after returning from scanner

    // If a lecture ID was scanned
    if (scannedLectureId != null && scannedLectureId.isNotEmpty) {
      if (kDebugMode) print("Scanned Lecture ID for Check-In: $scannedLectureId");
      // Set processing state
      setState(() { _processingLectureId = scannedLectureId; });
      try {
        // Call API to check-in via QR
        await apiService.checkInViaLectureQr(scannedLectureId);
        if (!mounted) return; // Check mount status after async call
        await _loadAttendanceSummary(); // Refresh summary to update status

        // Try to find lecture name for success message (best effort)
        String lectureName = "lecture";
        if (lecturesFuture != null) {
           try {
              final lectures = await lecturesFuture; // Await the future if needed
              final Lecture? foundLecture = lectures?.firstWhereOrNull((l) => l.id == scannedLectureId);
              if (foundLecture != null) { lectureName = "'${foundLecture.unitName}'"; }
           } catch (_) { /* Ignore errors finding lecture name */ }
        }
        showSnackBar('Successfully checked in for $lectureName!', isError: false);
      } catch (e) {
        if (!mounted) return; // Check mount status after error
        // Handle specific API errors
        if (e is ApiException && (e.statusCode == 400 || e.statusCode == 404)) {
           showSnackBar('Check-in failed: You must join the lecture first.', isError: true);
        } else if (e is ApiException && e.statusCode == 409) {
           showSnackBar('Check-in failed: You are already checked in.', isError: true);
           await _loadAttendanceSummary(); // Refresh status if already checked in
        } else {
           // Show generic error
           showSnackBar('QR Check-in failed: ${e.toString()}', isError: true);
        }
      } finally {
        // Clear processing state
        if (mounted) { setState(() { _processingLectureId = null; }); }
      }
    } else {
      if (kDebugMode) print("QR Scan cancelled or returned empty lecture ID.");
    }
  }

  // Helper to show snackbar messages
  void showSnackBar(String message, {bool isError = false}) {
      if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(message),
         backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green.shade600, // Use greener success color
         behavior: SnackBarBehavior.floating,
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
         margin: const EdgeInsets.all(10),
       ),
     );
  }

  // Builds the attendance summary card widget
  Widget _buildAttendanceSummaryCard() {
    // Loading state
    if (_isLoadingSummary) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: brandColor)),
      );
    }
    // Error state
    if (_summaryError != null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.red.shade50, elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700),
              const SizedBox(width: 12),
              Expanded( child: Text( 'Could not load attendance summary: $_summaryError', style: TextStyle(color: Colors.red.shade900), ), ),
              // Retry button
              IconButton( icon: Icon(Icons.refresh, color: Colors.red.shade700), tooltip: 'Retry Loading Summary', onPressed: _loadAttendanceSummary, padding: EdgeInsets.zero, constraints: const BoxConstraints(), )
            ],
          ),
        ),
      );
    }
    // Unavailable state (API returned nulls)
    if (_attendancePercentage == null || _attendedLectures == null || _totalLectures == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, color: Colors.grey.shade500),
              const SizedBox(width: 10),
              Text( 'Attendance summary is currently unavailable.', style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center, ),
            ],
          ),
        ),
      );
    }

    // Success state - build the summary card
    double percentageValue = double.tryParse(_attendancePercentage!) ?? 0.0;
    double progressValue = (percentageValue / 100.0).clamp(0.0, 1.0); // Ensure value is between 0.0 and 1.0
    // Determine progress bar color based on percentage
    Color progressColor = percentageValue >= 75 ? Colors.green.shade600 : (percentageValue >= 50 ? Colors.orange.shade700 : Colors.red.shade600);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text( 'Attendance Summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: brandColor), ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // Attended / Total Lectures text
                Flexible( child: Text( _totalLectures == 0 ? '0 / 0 Lectures Attended' : '$_attendedLectures / $_totalLectures Lectures Attended', style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis, ), ),
                const SizedBox(width: 10),
                // Percentage text
                Text( '${_attendancePercentage!}%', style: Theme.of(context).textTheme.headlineSmall?.copyWith( fontWeight: FontWeight.bold, color: progressColor, ), ),
              ],
            ),
            const SizedBox(height: 8),
            // Progress bar
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

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final textTheme = Theme.of(context).textTheme;
    // Determine if user can perform actions (requires registration number)
    final bool canPerformActions = widget.currentUser.registrationNumber != null && widget.currentUser.registrationNumber!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
         title: Text('Student Dashboard - ${widget.currentUser.name}', style: const TextStyle(fontSize: 18)),
         backgroundColor: brandColor, foregroundColor: Colors.white, elevation: 2.0,
         actions: [
            // Show loading indicator if an action is processing
            if (_processingLectureId != null)
              const Padding( padding: EdgeInsets.only(right: 15.0), child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))), ),
            // Filter button (enabled only if filters applied and not processing)
            IconButton(
              icon: Icon(Icons.edit_calendar_outlined, color: initialFiltersApplied && canPerformActions ? Colors.white : Colors.white54),
              tooltip: 'Change Year/Semester',
              onPressed: initialFiltersApplied && canPerformActions && _processingLectureId == null ? showRefineFilterDialog : null,
            ),
            // Refresh button (enabled only if filters applied and not processing)
            IconButton(
              icon: Icon(Icons.refresh, color: initialFiltersApplied && canPerformActions ? Colors.white : Colors.white54),
              tooltip: 'Refresh Lectures & Summary',
              onPressed: initialFiltersApplied && canPerformActions && _processingLectureId == null ? () async { loadLectures(); await _loadAttendanceSummary(); } : null,
            ),
            // Logout button (disabled if processing)
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: (_processingLectureId != null) ? null : () async {
                 final confirm = await showDialog<bool>( context: context, builder: (context) => AlertDialog( shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), title: const Text('Confirm Logout'), content: const Text('Are you sure you want to log out?'), actions: [ TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')), TextButton( onPressed: () => Navigator.of(context).pop(true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Logout'), ), ], ), ) ?? false;
                 if (confirm && mounted) { await authService.logout(); Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, ); }
              },
            ),
         ],
      ),
      // QR Scan FAB (only visible if user can perform actions)
      floatingActionButton: canPerformActions ? FloatingActionButton.extended(
        onPressed: (_processingLectureId != null) ? null : _scanLectureQrAndCheckIn, // Disabled if processing
        label: const Text('Scan QR'),
        icon: const Icon(Icons.qr_code_scanner),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        tooltip: 'Scan Lecture QR Code to Check-In',
      ) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat, // Position FAB centrally
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Show summary card if user can perform actions
          if (canPerformActions) _buildAttendanceSummaryCard(),

          // Show filter info and lecture list title if filters are applied
          if (initialFiltersApplied && canPerformActions) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
              child: Text( "Available Lectures", style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: brandColor), ),
            ),
            // Display current filters as Chips
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

          // Main content area: Lecture list or placeholder
          Expanded(
            child: initialFiltersApplied && canPerformActions
                // Show lecture list if filters are applied
                ? RefreshIndicator(
                    color: brandColor,
                    onRefresh: () async { loadLectures(); await _loadAttendanceSummary(); }, // Pull-to-refresh action
                    child: FutureBuilder<List<Lecture>>(
                      future: lecturesFuture, // Future that fetches lectures
                      builder: (context, snapshot) {
                        // Loading state
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator(color: brandColor));
                        }
                        // Error state
                        if (snapshot.hasError) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cloud_off_outlined, color: Colors.orange.shade700, size: 48),
                                  const SizedBox(height: 10),
                                  Text( 'Error loading lectures: ${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700), ),
                                  const SizedBox(height: 15),
                                  ElevatedButton.icon( icon: const Icon(Icons.refresh), label: const Text('Retry'), onPressed: loadLectures, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white), )
                                ],
                              ),
                            )
                          );
                        }
                        // Empty state (no lectures found)
                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                          return LayoutBuilder( builder: (context, constraints) {
                            return SingleChildScrollView( // Make it scrollable for refresh
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minHeight: constraints.maxHeight), // Ensure it fills height
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.event_busy_outlined, size: 50, color: Colors.grey.shade400),
                                        const SizedBox(height: 10),
                                        Text( 'No lectures found for Year $selectedYear, Semester $selectedSemester.\nTry changing filters or pull down to refresh.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ),
                                      ],
                                    )
                                  ),
                                ),
                              ),
                            );
                          });
                        }

                        // Success state - display lecture list
                        final lectures = snapshot.data!;
                        // Sort lectures by date and then start time (earliest first)
                        lectures.sort((a, b) {
                           final aDate = a.lectureDate; final bDate = b.lectureDate;
                           if (aDate != null && bDate != null) {
                             int dateComp = aDate.compareTo(bDate);
                             if (dateComp != 0) return dateComp;
                           } else if (aDate == null && bDate != null) { return 1; }
                             else if (aDate != null && bDate == null) { return -1; }

                           final aTime = a.startTime; final bTime = b.startTime;
                           if (aTime != null && bTime != null) { return aTime.compareTo(bTime); }
                           else if (aTime == null && bTime != null) { return 1; }
                             else if (aTime != null && bTime == null) { return -1; }
                             else { return 0; }
                        });

                        // Build the list view
                        return ListView.builder(
                           physics: const AlwaysScrollableScrollPhysics(), // Ensure refresh works
                           padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 80), // Padding for FAB
                           itemCount: lectures.length,
                           itemBuilder: (context, index) {
                              final lecture = lectures[index];
                              // Check local summary cache for attendance status
                              final attendanceRecord = _summaryAttendanceRecords?.firstWhereOrNull((r) => r.lectureId == lecture.id);
                              final bool isJoined = attendanceRecord != null && !attendanceRecord.checkedIn;
                              final bool isCheckedIn = attendanceRecord != null && attendanceRecord.checkedIn;
                              final bool isCurrentlyProcessing = _processingLectureId == lecture.id;
                              // --- Check if it's an online lecture with a link ---
                              final bool isOnlineWithLink = lecture.venue.toUpperCase() == 'ONLINE' && lecture.onlineLink != null && lecture.onlineLink!.trim().isNotEmpty;
                              // --- END Check ---

                              // Build subtitle text
                              String subtitleText = 'Lecturer: ${lecture.lecturerName}\n${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}\nVenue: ${lecture.venue}';

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6.0),
                                elevation: 1.5,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                // Use Padding + Row for more flexible layout than ListTile
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center, // Center items vertically
                                    children: [
                                      // --- Leading Avatar (Status Icon) ---
                                      CircleAvatar(
                                        backgroundColor: brandColor.withOpacity(0.1),
                                        child: Icon(
                                          // Choose icon based on status and type
                                          isCheckedIn ? Icons.check_circle_outline_rounded :
                                          (isJoined ? Icons.hourglass_bottom_rounded :
                                          (isOnlineWithLink ? Icons.videocam_outlined : Icons.schedule_outlined)),
                                          color: brandColor,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 16),

                                      // --- Main Content Column ---
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            // Title
                                            Text(
                                              '${lecture.unitName} (${lecture.unitCode})',
                                              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
                                            ),
                                            const SizedBox(height: 4),
                                            // Subtitle
                                            Text(
                                              subtitleText,
                                              style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3),
                                            ),

                                            // --- Conditional Online Link Button ---
                                            // Show button if online, has link, AND student has joined/checked in
                                            if (isOnlineWithLink && (isJoined || isCheckedIn)) ...[
                                              const SizedBox(height: 8),
                                              TextButton.icon(
                                                icon: Icon(Icons.open_in_browser_outlined, size: 18, color: brandColor),
                                                label: Text('Open Online Link', style: TextStyle(fontSize: 13, color: brandColor, fontWeight: FontWeight.w500)),
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap, // Reduce tap area
                                                  visualDensity: VisualDensity.compact,
                                                  alignment: Alignment.centerLeft, // Align icon/text left
                                                ),
                                                onPressed: () => _launchURL(lecture.onlineLink!), // Launch URL on press
                                              ),
                                            ]

                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8), // Spacer before trailing action

                                      // --- Trailing Action (Join Button or Status Chip) ---
                                      if (isCheckedIn)
                                        // Checked In Chip
                                        Chip(
                                          avatar: Icon(Icons.check_circle, size: 18, color: Colors.green.shade800),
                                          label: Text('Checked In', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500)),
                                          backgroundColor: Colors.green.shade100,
                                          side: BorderSide.none,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        )
                                      else if (isJoined)
                                        // Joined Chip
                                        Chip(
                                          avatar: Icon(Icons.hourglass_bottom_rounded, size: 18, color: Colors.orange.shade800),
                                          label: Text('Joined', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w500)),
                                          backgroundColor: Colors.orange.shade100,
                                          side: BorderSide.none,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        )
                                      else // Not joined yet - Show Join Button
                                        ElevatedButton(
                                          onPressed: (_processingLectureId != null || !canPerformActions) ? null : () => showJoinLectureDialog(lecture), // Disabled if processing or cannot act
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: brandColor,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            minimumSize: const Size(80, 36), // Ensure minimum size
                                          ),
                                          child: isCurrentlyProcessing // Show loading indicator if this lecture is processing
                                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                              : const Text('Join'),
                                        ),
                                      // --- End Trailing Action ---
                                    ],
                                  ),
                                ),
                              );
                           },
                        );
                      },
                    ),
                  )
                // Show placeholder if filters not applied or user cannot act
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            canPerformActions ? Icons.filter_list_off_outlined : Icons.warning_amber_rounded, // Different icon based on reason
                            size: 50,
                            color: canPerformActions ? Colors.grey.shade400 : Colors.orange.shade600,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            canPerformActions ? 'Please select your Year and Semester\nto view available lectures.' : 'Cannot load lectures.\nYour registration number might be missing.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                          ),
                          // Show button to select initial filters if needed
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
