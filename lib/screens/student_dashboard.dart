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

  String? fixedSchool;
  String? fixedDepartment;
  String? fixedCourse;
  String? selectedYear;
  String? selectedSemester;
  bool initialFiltersApplied = false;

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

    if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
       WidgetsBinding.instance.addPostFrameCallback((_) {
         if (mounted) { _showMissingRegNumError(); }
       });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showInitialFilterDialog();
          _loadAttendanceSummary();
        }
      });
    }
  }

  void _showMissingRegNumError() {
     showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Row(
             children: [ Icon(Icons.error_outline, color: Colors.red), SizedBox(width: 10), Text('Registration Incomplete'), ],
          ),
          content: const Text('Your student registration number is missing.\nPlease contact support or re-register to use attendance features.'),
          actions: [
            TextButton(
              onPressed: () async {
                 Navigator.of(context).pop();
                 await Provider.of<AuthService>(context, listen: false).logout();
                 if (mounted) {
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

  Future<void> showInitialFilterDialog() async {
    final initialData = LectureFilterData( school: fixedSchool, department: fixedDepartment, course: fixedCourse, year: null, semester: null, );
    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context, barrierDismissible: false,
      builder: (context) => LectureFilterDialog( initialFilters: initialData, isInitialSelection: true, fixedSchool: fixedSchool, fixedDepartment: fixedDepartment, fixedCourse: fixedCourse, ),
    );
    if (selectedFilters != null && selectedFilters.year != null && selectedFilters.semester != null && mounted) {
      setState(() { selectedYear = selectedFilters.year; selectedSemester = selectedFilters.semester; initialFiltersApplied = true; });
      loadLectures();
      _loadAttendanceSummary();
    } else if (mounted) {
      if (kDebugMode) print("Initial filter dialog closed unexpectedly or without valid selection.");
    }
  }

  Future<void> showRefineFilterDialog() async {
    final currentFilters = LectureFilterData( school: fixedSchool, department: fixedDepartment, course: fixedCourse, year: selectedYear, semester: selectedSemester, );
    final LectureFilterData? selectedFilters = await showDialog<LectureFilterData>(
      context: context, barrierDismissible: true,
      builder: (context) => LectureFilterDialog( initialFilters: currentFilters, isInitialSelection: false, fixedSchool: fixedSchool, fixedDepartment: fixedDepartment, fixedCourse: fixedCourse, ),
    );
    if (selectedFilters != null && mounted) {
      if (selectedFilters.year != selectedYear || selectedFilters.semester != selectedSemester) {
        setState(() { selectedYear = selectedFilters.year; selectedSemester = selectedFilters.semester; _summaryAttendanceRecords = null; });
        loadLectures();
        _loadAttendanceSummary();
      }
    }
  }

  void loadLectures() {
    if (!initialFiltersApplied || selectedYear == null || selectedSemester == null) {
      if (lecturesFuture != null && mounted) { setState(() { lecturesFuture = null; }); }
      return;
    }
    if (!mounted) return;
    setState(() {
      lecturesFuture = apiService.getStudentLectures( fixedSchool, fixedDepartment, fixedCourse, selectedYear, selectedSemester, );
    });
  }

  Future<void> _loadAttendanceSummary() async {
    if (!mounted || widget.currentUser.id.isEmpty) return;
    if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
        setState(() { _isLoadingSummary = false; _summaryError = "Registration number missing."; _summaryAttendanceRecords = null; });
        return;
    }
    setState(() { _isLoadingSummary = true; _summaryError = null; });
    try {
      final summaryData = await apiService.getStudentAttendanceSummary(widget.currentUser.id);
      if (!mounted) return;
      setState(() {
        _attendancePercentage = summaryData['percentage'] as String?;
        _totalLectures = summaryData['totalLectures'] as int?;
        _attendedLectures = summaryData['attendedLectures'] as int?;
        _summaryAttendanceRecords = summaryData['attendanceRecords'] as List<AttendanceRecord>?;
        _isLoadingSummary = false;
      });
      print("Attendance Summary Loaded: $_attendancePercentage% ($_attendedLectures/$_totalLectures). Records: ${_summaryAttendanceRecords?.length ?? 0}");
    } catch (e) {
      if (!mounted) return;
      print("Error loading attendance summary: $e");
      setState(() {
        _summaryError = e is ApiException ? e.message : e.toString();
        _isLoadingSummary = false; _attendancePercentage = null; _totalLectures = null; _attendedLectures = null; _summaryAttendanceRecords = null;
      });
    }
  }

  Future<void> _handleStudentJoin(Lecture lecture) async {
    final studentRegNum = widget.currentUser.registrationNumber;
    if (studentRegNum == null || studentRegNum.isEmpty) {
      showSnackBar('Error: Your registration number is missing. Cannot join lecture.', isError: true); return;
    }
    if (_processingLectureId != null) return;
    setState(() { _processingLectureId = lecture.id; });
    try {
      final AttendanceRecord attendanceRecord = await apiService.joinLecture(lecture.id);
      if (!mounted) return;
      await _loadAttendanceSummary();
      showSnackBar('Successfully joined ${lecture.unitName}!', isError: false);
    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 409) {
         showSnackBar('You have already joined ${lecture.unitName}.', isError: false);
         await _loadAttendanceSummary();
      } else {
         showSnackBar('Failed to join lecture: ${e.toString()}', isError: true);
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
       showSnackBar(currentRecord.checkedIn ? 'You are already checked in for this lecture.' : 'You have already joined this lecture.', isError: false); return;
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
              InputChip( label: Text(studentRegNum, style: TextStyle(fontWeight: FontWeight.bold, color: brandColor)), avatar: Icon(Icons.badge_outlined, color: brandColor), backgroundColor: brandColor.withOpacity(0.1), side: BorderSide.none, isEnabled: false, ),
              const SizedBox(height: 15),
              // --- REVERTED FORMATTING ---
              Text('Date: ${lecture.formattedDate}'),
              Text('Time: ${lecture.formattedStartTime} - ${lecture.formattedEndTime}'), // Use DateTime formatters
              Text('Venue: ${lecture.venue}'),
              // --- END REVERSION ---
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            ElevatedButton.icon( icon: const Icon(Icons.login), label: const Text('Confirm Join'), style: ElevatedButton.styleFrom(backgroundColor: brandColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))), onPressed: () => Navigator.of(dialogContext).pop(true), ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) { await _handleStudentJoin(lecture); }
  }

  Future<void> _scanLectureQrAndCheckIn() async {
     if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
       showSnackBar('Error: Your registration number is missing. Cannot check in via QR.', isError: true); return;
    }
    if (_processingLectureId != null) return;
    final String? scannedLectureId = await Navigator.push<String>( context, MaterialPageRoute(builder: (context) => const QrScannerScreen()), );
    if (!mounted) return;
    if (scannedLectureId != null && scannedLectureId.isNotEmpty) {
      print("Scanned Lecture ID for Check-In: $scannedLectureId");
      setState(() { _processingLectureId = scannedLectureId; });
      try {
        final AttendanceRecord attendanceRecord = await apiService.checkInViaLectureQr(scannedLectureId);
        if (!mounted) return;
        await _loadAttendanceSummary();
        String lectureName = "lecture";
        if (lecturesFuture != null) {
           try {
              final lectures = await lecturesFuture;
              final Lecture? foundLecture = lectures?.firstWhereOrNull((l) => l.id == scannedLectureId);
              if (foundLecture != null) { lectureName = "'${foundLecture.unitName}'"; }
           } catch (_) { /* Ignore */ }
        }
        showSnackBar('Successfully checked in for $lectureName!', isError: false);
      } catch (e) {
        if (!mounted) return;
        if (e is ApiException && (e.statusCode == 400 || e.statusCode == 404)) {
           showSnackBar('Check-in failed: You must join the lecture first.', isError: true);
        } else if (e is ApiException && e.statusCode == 409) {
           showSnackBar('Check-in failed: You are already checked in.', isError: true);
           await _loadAttendanceSummary();
        } else {
           showSnackBar('QR Check-in failed: ${e.toString()}', isError: true);
        }
      } finally {
        if (mounted) { setState(() { _processingLectureId = null; }); }
      }
    } else {
      print("QR Scan cancelled or returned empty lecture ID.");
    }
  }

  void showSnackBar(String message, {bool isError = false}) {
      if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar( content: Text(message), backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green, behavior: SnackBarBehavior.floating, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)), margin: const EdgeInsets.all(10), ),
     );
  }

  Widget _buildAttendanceSummaryCard() {
    if (_isLoadingSummary) { return const Padding( padding: EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0), child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: brandColor)), ); }
    if (_summaryError != null) {
      return Card( margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), color: Colors.red.shade50, elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding( padding: const EdgeInsets.all(16.0), child: Row( children: [ Icon(Icons.error_outline, color: Colors.red.shade700), const SizedBox(width: 12), Expanded( child: Text( 'Could not load attendance summary: $_summaryError', style: TextStyle(color: Colors.red.shade900), ), ), IconButton( icon: Icon(Icons.refresh, color: Colors.red.shade700), tooltip: 'Retry Loading Summary', onPressed: _loadAttendanceSummary, padding: EdgeInsets.zero, constraints: const BoxConstraints(), ) ], ), ), );
    }
    if (_attendancePercentage == null || _attendedLectures == null || _totalLectures == null) {
      return Card( margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding( padding: const EdgeInsets.all(16.0), child: Row( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.info_outline, color: Colors.grey.shade500), const SizedBox(width: 10), Text( 'Attendance summary is currently unavailable.', style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center, ), ], ), ), );
    }
    double percentageValue = double.tryParse(_attendancePercentage!) ?? 0.0;
    double progressValue = (percentageValue / 100.0).clamp(0.0, 1.0);
    Color progressColor = percentageValue >= 75 ? Colors.green.shade600 : (percentageValue >= 50 ? Colors.orange.shade700 : Colors.red.shade600);
    return Card( margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), clipBehavior: Clip.antiAlias,
      child: Padding( padding: const EdgeInsets.all(16.0), child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [ Text( 'Attendance Summary', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: brandColor), ), const SizedBox(height: 12), Row( mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.end, children: [ Flexible( child: Text( _totalLectures == 0 ? '0 / 0 Lectures Attended' : '$_attendedLectures / $_totalLectures Lectures Attended', style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis, ), ), const SizedBox(width: 10), Text( '${_attendancePercentage!}%', style: Theme.of(context).textTheme.headlineSmall?.copyWith( fontWeight: FontWeight.bold, color: progressColor, ), ), ], ), const SizedBox(height: 8), ClipRRect( borderRadius: BorderRadius.circular(4), child: LinearProgressIndicator( value: progressValue, backgroundColor: Colors.grey.shade300, valueColor: AlwaysStoppedAnimation<Color>(progressColor), minHeight: 8, ), ), ], ), ), );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final textTheme = Theme.of(context).textTheme;
    final bool canPerformActions = widget.currentUser.registrationNumber != null && widget.currentUser.registrationNumber!.isNotEmpty;

    // --- REMOVED timeToMinutes helper ---

    return Scaffold(
      appBar: AppBar(
         title: Text('Student Dashboard - ${widget.currentUser.name}', style: const TextStyle(fontSize: 18)),
         backgroundColor: brandColor, foregroundColor: Colors.white, elevation: 2.0,
         actions: [
            if (_processingLectureId != null)
              const Padding( padding: EdgeInsets.only(right: 15.0), child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))), ),
            IconButton( icon: Icon(Icons.edit_calendar_outlined, color: initialFiltersApplied && canPerformActions ? Colors.white : Colors.white54), tooltip: 'Change Year/Semester', onPressed: initialFiltersApplied && canPerformActions && _processingLectureId == null ? showRefineFilterDialog : null, ),
            IconButton( icon: Icon(Icons.refresh, color: initialFiltersApplied && canPerformActions ? Colors.white : Colors.white54), tooltip: 'Refresh Lectures & Summary', onPressed: initialFiltersApplied && canPerformActions && _processingLectureId == null ? () async { loadLectures(); await _loadAttendanceSummary(); } : null, ),
            IconButton( icon: const Icon(Icons.logout), tooltip: 'Logout', onPressed: (_processingLectureId != null) ? null : () async {
                 final confirm = await showDialog<bool>( context: context, builder: (context) => AlertDialog( shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), title: const Text('Confirm Logout'), content: const Text('Are you sure you want to log out?'), actions: [ TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')), TextButton( onPressed: () => Navigator.of(context).pop(true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Logout'), ), ], ), ) ?? false;
                 if (confirm && mounted) { await authService.logout(); Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, ); } }, ),
         ],
      ),
      floatingActionButton: canPerformActions ? FloatingActionButton.extended( onPressed: (_processingLectureId != null) ? null : _scanLectureQrAndCheckIn, label: const Text('Scan QR'), icon: const Icon(Icons.qr_code_scanner), backgroundColor: brandColor, foregroundColor: Colors.white, tooltip: 'Scan Lecture QR Code to Check-In', ) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (canPerformActions) _buildAttendanceSummaryCard(),
          if (initialFiltersApplied && canPerformActions) ...[
            Padding( padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0), child: Text( "Available Lectures", style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: brandColor), ), ),
            Padding( padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0), child: Wrap( spacing: 8.0, runSpacing: 4.0, children: [ if (selectedYear != null) Chip(label: Text('Year: $selectedYear'), backgroundColor: brandColor.withOpacity(0.1), side: BorderSide.none), if (selectedSemester != null) Chip(label: Text('Semester: $selectedSemester'), backgroundColor: brandColor.withOpacity(0.1), side: BorderSide.none), if (fixedCourse != null) Chip(label: Text('Course: $fixedCourse'), backgroundColor: Colors.grey.shade200, side: BorderSide.none), ], ), ),
            const Divider(height: 1, indent: 16, endIndent: 16, thickness: 0.5),
          ],
          Expanded(
            child: initialFiltersApplied && canPerformActions
                ? RefreshIndicator( color: brandColor, onRefresh: () async { loadLectures(); await _loadAttendanceSummary(); },
                    child: FutureBuilder<List<Lecture>>(
                      future: lecturesFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) { return Center(child: CircularProgressIndicator(color: brandColor)); }
                        if (snapshot.hasError) { return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.cloud_off_outlined, color: Colors.orange.shade700, size: 48), const SizedBox(height: 10), Text( 'Error loading lectures: ${snapshot.error}', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700), ), const SizedBox(height: 15), ElevatedButton.icon( icon: const Icon(Icons.refresh), label: const Text('Retry'), onPressed: loadLectures, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white), ) ], ), ) ); }
                        if (!snapshot.hasData || snapshot.data!.isEmpty) { return LayoutBuilder( builder: (context, constraints) { return SingleChildScrollView( physics: const AlwaysScrollableScrollPhysics(), child: ConstrainedBox( constraints: BoxConstraints(minHeight: constraints.maxHeight), child: Center( child: Padding( padding: const EdgeInsets.all(20.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.event_busy_outlined, size: 50, color: Colors.grey.shade400), const SizedBox(height: 10), Text( 'No lectures found for Year $selectedYear, Semester $selectedSemester.\nTry changing filters or pull down to refresh.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ), ], )), ), ), ); } ); }

                        final lectures = snapshot.data!;
                        // --- REVERTED SORTING to use DateTime ---
                        lectures.sort((a, b) {
                           final aDate = a.lectureDate; final bDate = b.lectureDate;
                           if (aDate != null && bDate != null) {
                             int dateComp = aDate.compareTo(bDate); // Earlier date first
                             if (dateComp != 0) return dateComp;
                           } else if (aDate == null && bDate != null) { return 1; }
                             else if (aDate != null && bDate == null) { return -1; }

                           // If dates are the same or both null, sort by start time (earlier first)
                           final aTime = a.startTime; final bTime = b.startTime;
                           if (aTime != null && bTime != null) {
                              return aTime.compareTo(bTime); // Direct DateTime comparison
                           } else if (aTime == null && bTime != null) { return 1; } // Nulls last
                             else if (aTime != null && bTime == null) { return -1; }
                             else { return 0; } // Both null
                        });
                        // --- END SORTING REVERSION ---

                        return ListView.builder(
                           physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 80), itemCount: lectures.length,
                           itemBuilder: (context, index) {
                              final lecture = lectures[index];
                              final attendanceRecord = _summaryAttendanceRecords?.firstWhereOrNull((r) => r.lectureId == lecture.id);
                              final bool isJoined = attendanceRecord != null && !attendanceRecord.checkedIn;
                              final bool isCheckedIn = attendanceRecord != null && attendanceRecord.checkedIn;
                              final bool isCurrentlyProcessing = _processingLectureId == lecture.id;

                              return Card( margin: const EdgeInsets.symmetric(vertical: 6.0), elevation: 1.5, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: ListTile( contentPadding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
                                  leading: CircleAvatar( backgroundColor: brandColor.withOpacity(0.1), child: Icon( isCheckedIn ? Icons.check_circle : (isJoined ? Icons.hourglass_top_rounded : Icons.schedule_outlined), color: brandColor ), ),
                                  title: Text('${lecture.unitName} (${lecture.unitCode})', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                                  subtitle: Padding( padding: const EdgeInsets.only(top: 4.0),
                                     child: Text(
                                      // --- REVERTED FORMATTING ---
                                      'Lecturer: ${lecture.lecturerName}\n${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}\nVenue: ${lecture.venue}', // Use DateTime formatters
                                      // --- END REVERSION ---
                                      style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3),
                                    ),
                                  ),
                                  isThreeLine: true,
                                  trailing: isCheckedIn
                                    ? Chip( avatar: Icon(Icons.check_circle, size: 18, color: Colors.green.shade800), label: Text('Checked In', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500)), backgroundColor: Colors.green.shade100, side: BorderSide.none, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), )
                                    : isJoined
                                      ? Chip( avatar: Icon(Icons.hourglass_bottom_rounded, size: 18, color: Colors.orange.shade800), label: Text('Joined', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w500)), backgroundColor: Colors.orange.shade100, side: BorderSide.none, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), )
                                      : ElevatedButton( onPressed: (_processingLectureId != null || !canPerformActions) ? null : () => showJoinLectureDialog(lecture), style: ElevatedButton.styleFrom( backgroundColor: brandColor, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), minimumSize: const Size(80, 36), ),
                                          child: isCurrentlyProcessing ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Join'), ),
                                ),
                              );
                           },
                        );
                      },
                    ),
                  )
                : Center( child: Padding( padding: const EdgeInsets.all(20.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon( canPerformActions ? Icons.filter_list_off_outlined : Icons.warning_amber_rounded, size: 50, color: canPerformActions ? Colors.grey.shade400 : Colors.orange.shade600, ), const SizedBox(height: 20), Text( canPerformActions ? 'Please select your Year and Semester\nto view available lectures.' : 'Cannot load lectures.\nYour registration number might be missing.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ), if (!initialFiltersApplied && canPerformActions) Padding( padding: const EdgeInsets.only(top: 15.0), child: ElevatedButton.icon( icon: const Icon(Icons.filter_list), label: const Text('Select Year/Semester'), onPressed: showInitialFilterDialog, style: ElevatedButton.styleFrom(backgroundColor: brandColor, foregroundColor: Colors.white), ), ) ], ), ), ),
          ),
        ],
      ),
    );
  }
}
