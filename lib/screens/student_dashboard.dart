// lib/screens/student_dashboard.dart
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/models/lecture.dart'; 
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/services/api_service.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:checkmate/screens/welcome_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:checkmate/screens/qr_scanner_screen.dart';
import 'package:collection/collection.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async'; // Import for TimeoutException

class StudentDashboard extends StatefulWidget {
  final app_user.User currentUser;
  const StudentDashboard({super.key, required this.currentUser});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> {
  final ApiService apiService = ApiService();

  Future<List<Lecture>>? lecturesFuture;
  String? _processingLectureId;

  // User profile details
  String? fixedSchool;
  String? fixedDepartment;
  String? fixedCourse;
  String? fixedYearOfStudy;
  String? fixedSemester;

  // Attendance summary state
  bool _isLoadingSummary = true;
  String? _summaryError;
  String? _attendancePercentage;
  int? _totalLectures;
  int? _attendedLectures;
  List<AttendanceRecord>? _summaryAttendanceRecords;

  static const Color brandColor = Color(0xFF0175C2);

  @override
  void initState() {
    super.initState();
    fixedSchool = widget.currentUser.school;
    fixedDepartment = widget.currentUser.department;
    fixedCourse = widget.currentUser.course;
    fixedYearOfStudy = widget.currentUser.yearOfStudy;
    fixedSemester = widget.currentUser.semester;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
        _showMissingRegNumError();
      } else if (fixedYearOfStudy == null || fixedYearOfStudy!.isEmpty || fixedSemester == null || fixedSemester!.isEmpty) {
        _showMissingYearSemesterError();
      } else {
        loadLectures();
        _loadAttendanceSummary();
      }
    });
  }

  // --- Dialogs ---
  void _showMissingRegNumError() {
     // Ensure context and builder are correctly passed
     showDialog(
        context: context, // Pass the current BuildContext
        barrierDismissible: false,
        builder: (BuildContext dialogContext) { // Use a different context name for builder
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Row(
               children: [ Icon(Icons.error_outline, color: Colors.red), SizedBox(width: 10), Text('Registration Incomplete'), ],
            ),
            content: const Text('Your student registration number is missing.\nPlease contact support or update your profile to use attendance features.'),
            actions: [
              TextButton(
                onPressed: () async {
                   Navigator.of(dialogContext).pop(); // Use dialogContext
                   // Use context from the State, not dialogContext for Provider
                   await Provider.of<AuthService>(context, listen: false).logout();
                   if (mounted) {
                      // Use context from the State for navigation
                      Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, );
                   }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Logout'),
              ),
            ],
          );
        } // End builder
     );
  }

  void _showMissingYearSemesterError() {
     // Ensure context and builder are correctly passed
     showDialog(
        context: context, // Pass the current BuildContext
        barrierDismissible: false,
        builder: (BuildContext dialogContext) { // Use a different context name for builder
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Row(
               children: [ Icon(Icons.error_outline, color: Colors.orange), SizedBox(width: 10), Text('Profile Incomplete'), ],
            ),
            content: const Text('Your Year of Study or Semester is missing.\nPlease contact support or update your profile.'),
            actions: [
              TextButton(
                onPressed: () async {
                   Navigator.of(dialogContext).pop(); // Use dialogContext
                   // Use context from the State, not dialogContext for Provider
                   await Provider.of<AuthService>(context, listen: false).logout();
                   if (mounted) {
                      // Use context from the State for navigation
                      Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, );
                   }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Logout'),
              ),
            ],
          );
        } // End builder
     );
  }

  // --- Data Loading ---
  void loadLectures() {
    if (fixedSchool == null || fixedDepartment == null || fixedCourse == null || fixedYearOfStudy == null || fixedSemester == null) {
      if (kDebugMode) print("Cannot load lectures: Missing fixed user details.");
      if (lecturesFuture != null && mounted) { setState(() { lecturesFuture = null; }); }
      return;
    }
    if (!mounted) return;
    setState(() {
      lecturesFuture = apiService.getStudentLectures(
        fixedSchool, fixedDepartment, fixedCourse, fixedYearOfStudy, fixedSemester,
      );
    });
  }
  Future<void> _loadAttendanceSummary() async {
    if (!mounted || widget.currentUser.id.isEmpty) return;
    if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
        setState(() { _isLoadingSummary = false; _summaryError = "Registration number missing."; _summaryAttendanceRecords = null; });
        return;
    }
     if (fixedYearOfStudy == null || fixedSemester == null) {
        setState(() { _isLoadingSummary = false; _summaryError = "Year/Semester missing."; _summaryAttendanceRecords = null; });
        return;
    }

    setState(() { _isLoadingSummary = true; _summaryError = null; });
    try {
      final summaryData = await apiService.getStudentAttendanceSummary(
          widget.currentUser.id,
          year: fixedYearOfStudy,
          semester: fixedSemester
      );

      if (!mounted) return;
      setState(() {
        _attendancePercentage = summaryData['percentage'] as String?;
        _totalLectures = summaryData['totalLectures'] as int?;
        _attendedLectures = summaryData['attendedLectures'] as int?;
        _summaryAttendanceRecords = summaryData['attendanceRecords'] as List<AttendanceRecord>?;
        _isLoadingSummary = false;
      });
      if (kDebugMode) print("Attendance Summary Loaded for $fixedYearOfStudy/$fixedSemester: $_attendancePercentage% ($_attendedLectures/$_totalLectures). Records: ${_summaryAttendanceRecords?.length ?? 0}");
    } catch (e) {
      if (!mounted) return;
      if (kDebugMode) print("Error loading attendance summary for $fixedYearOfStudy/$fixedSemester: $e");
      setState(() {
        _summaryError = e is ApiException ? e.message : "An error occurred";
        _isLoadingSummary = false;
        _attendancePercentage = null; _totalLectures = null; _attendedLectures = null; _summaryAttendanceRecords = null;
      });
    }
  }

  // --- Helpers ---
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString.trim());
    final Uri launchUri = url.hasScheme ? url : Uri.parse('https://$urlString');
    try {
      if (!await launchUrl(launchUri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch URL');
      }
    } catch (e) {
      if (mounted) {
        showSnackBar('Could not open link: $urlString', isError: true);
      }
      if (kDebugMode) print('Error launching URL $launchUri: $e');
    }
  }

  void showSnackBar(String message, {bool isError = false}) {
      if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(message),
         backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green.shade600,
         behavior: SnackBarBehavior.floating,
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
         margin: const EdgeInsets.all(10),
       ),
     );
  }

  // --- Percentage Widget ---
  Widget _buildPercentageWidget(String? percentageString) {
    // Use context safely within the State class
    final headlineStyle = Theme.of(context).textTheme.headlineSmall;

    // Handle null, "N/A", or empty strings
    if (percentageString == null || percentageString == "N/A" || percentageString.isEmpty) {
      return Text(
        'N/A',
        style: headlineStyle?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade500,
        ),
      );
    }

    double? percentageValue;
    try {
      percentageValue = double.parse(percentageString);
    } catch (e) {
      if (kDebugMode) print("Warning: Could not parse percentage string '$percentageString': $e");
      return Text(
        'ERR',
        style: headlineStyle?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.red.shade700,
        ),
      );
    }

    // Handle invalid numeric values
    if (percentageValue < 0 || percentageValue.isNaN || percentageValue.isInfinite) {
      if (kDebugMode) print("Warning: Invalid percentage value: $percentageValue");
      return Text(
        'ERR',
        style: headlineStyle?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.red.shade700,
        ),
      );
    }

    // Determine color based on percentage value
    final Color percColor = percentageValue >= 75 ? Colors.green.shade600 :
                             percentageValue >= 50 ? Colors.orange.shade700 :
                             Colors.red.shade700;

    // Display the percentage text
    return Text(
      '$percentageString%',
      style: headlineStyle?.copyWith(
        fontWeight: FontWeight.bold,
        color: percColor,
      ),
    );
  }


  // --- Actions ---

  // Join Lecture
  Future<void> _handleStudentJoin(Lecture lecture) async {
    final studentRegNum = widget.currentUser.registrationNumber;
    if (studentRegNum == null || studentRegNum.isEmpty) {
      showSnackBar('Error: Your registration number is missing. Cannot join lecture.', isError: true); return;
    }
    if (_processingLectureId != null) return;

    setState(() { _processingLectureId = lecture.id; });
    try {
      await apiService.joinLecture(lecture.id);
      if (!mounted) return;

      await _loadAttendanceSummary();
      showSnackBar('Successfully joined ${lecture.unitName}!', isError: false);

      if (lecture.venue.toUpperCase() == 'ONLINE' &&
          lecture.onlineLink != null &&
          lecture.onlineLink!.trim().isNotEmpty) {
        if (kDebugMode) print("Attempting to auto-launch online link after join: ${lecture.onlineLink}");
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
            await _launchURL(lecture.onlineLink!);
        }
      }

    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 409) {
         showSnackBar('You have already joined ${lecture.unitName}.', isError: false);
         await _loadAttendanceSummary();
      } else {
         showSnackBar('Failed to join lecture: ${e is ApiException ? e.message : e.toString()}', isError: true);
      }
    } finally {
      if (mounted) { setState(() { _processingLectureId = null; }); }
    }
  }

  Future<void> showJoinLectureDialog(Lecture lecture) async {
     final studentRegNum = widget.currentUser.registrationNumber;
    if (studentRegNum == null || studentRegNum.isEmpty) {
      showSnackBar('Error: Your registration number is missing. Cannot join lecture.', isError: true); return;
    }
    if (_processingLectureId != null) return;

    final currentRecord = _summaryAttendanceRecords?.firstWhereOrNull((r) => r.lectureId == lecture.id);
    if (currentRecord != null) {
       showSnackBar(currentRecord.checkedIn ? 'You are already checked in for this lecture.' : 'You have already joined this lecture.', isError: false);
       return;
    }

    final confirmed = await showDialog<bool>(
      context: context, // Use the State's context
      barrierDismissible: false,
      builder: (BuildContext dialogContext) { // Use a different context name
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
                backgroundColor: brandColor.withOpacity(0.1),
                side: BorderSide.none,
                isEnabled: false,
              ),
              const SizedBox(height: 15),
              Text('Date: ${lecture.formattedDate}'),
              Text('Time: ${lecture.formattedStartTime} - ${lecture.formattedEndTime}'),
              Text('Venue: ${lecture.venue}'),
              if (lecture.venue.toUpperCase() == 'ONLINE' && lecture.onlineLink != null && lecture.onlineLink!.isNotEmpty) ...[
                 const SizedBox(height: 8),
                 SelectableText(
                    'Link: ${lecture.onlineLink}',
                    style: TextStyle(color: Colors.blue.shade800),
                    maxLines: 1,
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
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) { await _handleStudentJoin(lecture); }
  }

  // Scan QR and Check In
  Future<void> _scanLectureQrAndCheckIn() async {
     if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
       showSnackBar('Error: Your registration number is missing. Cannot check in via QR.', isError: true); return;
    }
    if (_processingLectureId != null) return;

    final String? scannedLectureId = await Navigator.push<String>( context, MaterialPageRoute(builder: (context) => const QrScannerScreen()), );
    if (!mounted || scannedLectureId == null || scannedLectureId.isEmpty) {
        if (kDebugMode && scannedLectureId != null) print("QR Scan cancelled or returned empty lecture ID.");
        return;
    }

    if (kDebugMode) print("Scanned Lecture ID for Check-In: $scannedLectureId");

    // Frontend Time Check
    Lecture? scannedLecture;
    if (lecturesFuture != null) {
        try {
            final lectures = await lecturesFuture;
            scannedLecture = lectures?.firstWhereOrNull((l) => l.id == scannedLectureId);
        } catch (e) {
            if (kDebugMode) print("Error accessing lecturesFuture cache during QR scan check: $e");
        }
    }

    if (scannedLecture != null) {
        final lectureEndTime = scannedLecture.endTime;
        if (lectureEndTime != null && DateTime.now().isAfter(lectureEndTime)) {
            if (kDebugMode) print("Frontend Check: Lecture ${scannedLecture.unitName} has ended. Aborting check-in API call.");
            showSnackBar('Cannot check in: Lecture "${scannedLecture.unitName}" has already ended.', isError: true);
            return;
        } else {
             if (kDebugMode) print("Frontend Check: Lecture ${scannedLecture.unitName} end time (${lectureEndTime ?? 'null'}) is in the future or null. Proceeding.");
        }
    } else {
        if (kDebugMode) print("Warning: Could not find lecture details locally for QR time check. Proceeding with API call (backend will verify time).");
    }

    // Proceed with API call
    setState(() { _processingLectureId = scannedLectureId; });
    try {
      await apiService.checkInViaLectureQr(scannedLectureId);
      if (!mounted) return;
      await _loadAttendanceSummary();

      String lectureName = scannedLecture?.unitName ?? "the lecture";
      showSnackBar('Successfully checked in for \'$lectureName\'!', isError: false);

    } catch (e) {
      if (!mounted) return;
      if (e is ApiException) {
          if (e.statusCode == 400 && e.message.toLowerCase().contains("lecture has already ended")) {
              showSnackBar('Check-in failed: The lecture has already ended.', isError: true);
          } else if (e.statusCode == 400 || e.statusCode == 404) {
              showSnackBar('Check-in failed: You must join the lecture first.', isError: true);
          } else if (e.statusCode == 409) {
              showSnackBar('Check-in failed: You are already checked in.', isError: true);
              await _loadAttendanceSummary();
          } else {
              showSnackBar('QR Check-in failed: ${e.message}', isError: true);
          }
      } else {
          showSnackBar('QR Check-in failed: An unexpected error occurred.', isError: true);
      }
      if (kDebugMode) print("Error during checkInViaLectureQr API call: $e");
    } finally {
      if (mounted) { setState(() { _processingLectureId = null; }); }
    }
  }

  // --- UI Building ---

  // Summary Card
  Widget _buildAttendanceSummaryCard() {
    if (_isLoadingSummary) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: brandColor)),
      );
    }
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
              IconButton( icon: Icon(Icons.refresh, color: Colors.red.shade700), tooltip: 'Retry Loading Summary', onPressed: _loadAttendanceSummary, padding: EdgeInsets.zero, constraints: const BoxConstraints(), )
            ],
          ),
        ),
      );
    }
    // Check if data is available AFTER loading and no error
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

    // Calculate progress bar values
    double percentageValue = double.tryParse(_attendancePercentage!) ?? 0.0;
    double progressValue = (percentageValue / 100.0).clamp(0.0, 1.0);
    Color progressColor = percentageValue >= 75 ? Colors.green.shade600 : (percentageValue >= 50 ? Colors.orange.shade700 : Colors.red.shade600);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text( 'Attendance Summary ($fixedYearOfStudy - $fixedSemester)', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: brandColor), ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible( child: Text( _totalLectures == 0 ? '0 / 0 Lectures Attended' : '$_attendedLectures / $_totalLectures Lectures Attended', style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis, ), ),
                const SizedBox(width: 10),
                _buildPercentageWidget(_attendancePercentage), // Use helper
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

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final textTheme = Theme.of(context).textTheme;
    final bool canPerformActions = widget.currentUser.registrationNumber != null &&
                                   widget.currentUser.registrationNumber!.isNotEmpty &&
                                   fixedYearOfStudy != null && fixedYearOfStudy!.isNotEmpty &&
                                   fixedSemester != null && fixedSemester!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
         title: Text('Student Dashboard - ${widget.currentUser.name}', style: const TextStyle(fontSize: 18)),
         backgroundColor: brandColor, foregroundColor: Colors.white, elevation: 2.0,
         actions: [
            if (_processingLectureId != null)
              const Padding( padding: EdgeInsets.only(right: 15.0), child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))), ),
            IconButton(
              icon: Icon(Icons.refresh, color: canPerformActions ? Colors.white : Colors.white54),
              tooltip: 'Refresh Lectures & Summary',
              onPressed: canPerformActions && _processingLectureId == null ? () async { loadLectures(); await _loadAttendanceSummary(); } : null,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: (_processingLectureId != null) ? null : () async {
                 // Ensure context and builder are correctly passed
                 final confirm = await showDialog<bool>(
                    context: context, // Pass the current BuildContext
                    builder: (BuildContext dialogContext) { // Use a different context name
                      return AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        title: const Text('Confirm Logout'),
                        content: const Text('Are you sure you want to log out?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')), // Use dialogContext
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(true), // Use dialogContext
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Logout'),
                          ),
                        ],
                      );
                    } // End builder
                 ) ?? false; // Handle null case if dialog is dismissed
                 if (confirm && mounted) {
                    await authService.logout();
                    // Use context from the State for navigation
                    Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, );
                 }
              },
            ),
         ],
      ),
      floatingActionButton: canPerformActions ? FloatingActionButton.extended(
        onPressed: (_processingLectureId != null) ? null : _scanLectureQrAndCheckIn,
        label: const Text('Scan QR'),
        icon: const Icon(Icons.qr_code_scanner),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        tooltip: 'Scan Lecture QR Code to Check-In',
      ) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canPerformActions) _buildAttendanceSummaryCard(),

          if (canPerformActions) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
              child: Text( "Available Lectures", style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: brandColor), ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Wrap(
                spacing: 8.0, runSpacing: 4.0,
                children: [
                  if (fixedYearOfStudy != null) Chip(label: Text('Year: $fixedYearOfStudy'), backgroundColor: brandColor.withOpacity(0.1), side: BorderSide.none),
                  if (fixedSemester != null) Chip(label: Text('Semester: $fixedSemester'), backgroundColor: brandColor.withOpacity(0.1), side: BorderSide.none),
                  if (fixedCourse != null) Chip(label: Text('Course: $fixedCourse'), backgroundColor: Colors.grey.shade200, side: BorderSide.none),
                ],
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16, thickness: 0.5),
          ],

          Expanded(
            child: canPerformActions
                ? RefreshIndicator(
                    color: brandColor,
                    onRefresh: () async { loadLectures(); await _loadAttendanceSummary(); },
                    child: FutureBuilder<List<Lecture>>(
                      future: lecturesFuture,
                      builder: (context, snapshot) { // *** START OF FutureBuilder builder ***
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return Center(child: CircularProgressIndicator(color: brandColor));
                        }

                        // ***  ERROR HANDLING BLOCK ***
                        if (snapshot.hasError) {
                           // Log the error for debugging
                           final error = snapshot.error;
                           final stackTrace = snapshot.stackTrace;
                           if (kDebugMode) {
                             print("Error loading lectures: $error");
                             print("Stack trace: $stackTrace");
                           }
                           // Display a user-friendly error message
                           String displayMessage = 'Error loading lectures.';
                           if (error is ApiException) {
                             displayMessage = error.message; // Use message from ApiException
                           } else if (error is TimeoutException) {
                             displayMessage = 'Request timed out. Please check your connection.';
                           } else {
                             displayMessage = 'An unexpected error occurred.';
                           }

                           return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cloud_off_outlined, color: Colors.orange.shade700, size: 48),
                                  const SizedBox(height: 10),
                                  Text(
                                    '$displayMessage\n(Year: $fixedYearOfStudy, Sem: $fixedSemester)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey.shade700),
                                  ),
                                  const SizedBox(height: 15),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry'),
                                    onPressed: loadLectures, // Retry loading lectures
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                                  ),
                                   if (kDebugMode)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text('\nDetails: $error', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                    ),
                                ],
                              ),
                            )
                          );
                        }
                        // *** END  ERROR HANDLING BLOCK ***

                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                           return LayoutBuilder( builder: (context, constraints) {
                            return SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                                child: Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(20.0),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(Icons.event_busy_outlined, size: 50, color: Colors.grey.shade400),
                                        const SizedBox(height: 10),
                                        Text( 'No lectures found for Year $fixedYearOfStudy, Semester $fixedSemester.\nPull down to refresh.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ),
                                      ],
                                    )
                                  ),
                                ),
                              ),
                            );
                          });
                        }

                        // --- Success State ---
                        final lectures = snapshot.data!;
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

                        return ListView.builder(
                           physics: const AlwaysScrollableScrollPhysics(),
                           padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 80), // Added bottom padding for FAB
                           itemCount: lectures.length,
                           itemBuilder: (context, index) {
                              final lecture = lectures[index];
                              final attendanceRecord = _summaryAttendanceRecords?.firstWhereOrNull((r) => r.lectureId == lecture.id);
                              final bool isJoined = attendanceRecord != null && !attendanceRecord.checkedIn;
                              final bool isCheckedIn = attendanceRecord != null && attendanceRecord.checkedIn;
                              final bool isCurrentlyProcessing = _processingLectureId == lecture.id;
                              final bool isOnlineWithLink = lecture.venue.toUpperCase() == 'ONLINE' && lecture.onlineLink != null && lecture.onlineLink!.trim().isNotEmpty;

                              final lectureEndTime = lecture.endTime;
                              final bool hasEnded = lectureEndTime != null && DateTime.now().isAfter(lectureEndTime);

                              String subtitleText = 'Lecturer: ${lecture.lecturerName}\n${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}\nVenue: ${lecture.venue}';

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6.0),
                                elevation: 1.5,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        backgroundColor: brandColor.withOpacity(0.1),
                                        child: Icon(
                                          (hasEnded && !isCheckedIn) ? Icons.event_busy_outlined :
                                          isCheckedIn ? Icons.check_circle_outline_rounded :
                                          (isJoined ? Icons.hourglass_bottom_rounded :
                                          (isOnlineWithLink ? Icons.videocam_outlined : Icons.schedule_outlined)),
                                          color: (hasEnded && !isCheckedIn) ? Colors.grey.shade600 : brandColor,
                                          size: 24,
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${lecture.unitName} (${lecture.unitCode})',
                                              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              subtitleText,
                                              style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3),
                                            ),
                                            if (isOnlineWithLink && (isJoined || isCheckedIn || !hasEnded)) ...[
                                              const SizedBox(height: 8),
                                              TextButton.icon(
                                                icon: Icon(Icons.open_in_browser_outlined, size: 18, color: brandColor),
                                                label: Text('Open Online Link', style: TextStyle(fontSize: 13, color: brandColor, fontWeight: FontWeight.w500)),
                                                style: TextButton.styleFrom(
                                                  padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                                  visualDensity: VisualDensity.compact,
                                                  alignment: Alignment.centerLeft,
                                                ),
                                                onPressed: _processingLectureId != null ? null : () => _launchURL(lecture.onlineLink!),
                                              ),
                                            ]
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),

                                      // Trailing Widget Logic
                                      if (hasEnded && !isCheckedIn)
                                        Chip(
                                          avatar: Icon(Icons.event_busy, size: 18, color: Colors.grey.shade700),
                                          label: Text('Ended', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w500)),
                                          backgroundColor: Colors.grey.shade200,
                                          side: BorderSide.none,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        )
                                      else if (isCheckedIn)
                                        Chip(
                                          avatar: Icon(Icons.check_circle, size: 18, color: Colors.green.shade800),
                                          label: Text('Checked In', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500)),
                                          backgroundColor: Colors.green.shade100,
                                          side: BorderSide.none,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        )
                                      else if (isJoined)
                                        Chip(
                                          avatar: Icon(Icons.hourglass_bottom_rounded, size: 18, color: Colors.orange.shade800),
                                          label: Text('Joined', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w500)),
                                          backgroundColor: Colors.orange.shade100,
                                          side: BorderSide.none,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        )
                                      else // Not joined, not checked in, not ended
                                        ElevatedButton(
                                          onPressed: (_processingLectureId != null || !canPerformActions) ? null : () => showJoinLectureDialog(lecture),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: brandColor,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            minimumSize: const Size(80, 36),
                                          ),
                                          child: isCurrentlyProcessing
                                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                              : const Text('Join'),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                           },
                        );
                      }, // *** END OF FutureBuilder builder ***
                    ),
                  )
                : Center( // Placeholder when canPerformActions is false
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 50,
                            color: Colors.orange.shade600,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Cannot load lectures.\nYour profile might be incomplete (missing registration number, year, or semester).\nPlease contact support.',
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
