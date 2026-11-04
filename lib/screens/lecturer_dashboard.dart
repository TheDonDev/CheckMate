// lib/screens/lecturer_dashboard.dart
import 'dart:async'; // Import for TimeoutException
export 'lecturer_dashboard.dart';
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/screens/lecture_attendance_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:checkmate/services/api_service.dart'; // Import ApiException
import 'package:checkmate/widgets/create_lecture_dialog.dart';
import 'package:checkmate/widgets/edit_lecture_dialog.dart';
import 'package:checkmate/widgets/document_name_widget.dart';
import 'package:flutter/material.dart';
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/screens/welcome_screen.dart';
import 'package:intl/intl.dart'; // Import for date formatting
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:checkmate/screens/qr_scanner_screen.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode

// --- UpperCaseTextFormatter  ---
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(),
      selection: newValue.selection,
    );
  }
}
// --- End Formatter ---

class LecturerDashboard extends StatefulWidget {
  final app_user.User currentUser;
  const LecturerDashboard({super.key, required this.currentUser});

  @override
  State<LecturerDashboard> createState() => _LecturerDashboardState();
}
class _LecturerDashboardState extends State<LecturerDashboard> {
  final ApiService apiService = ApiService();
  Stream<List<Lecture>>? _lecturesStream; // Stream for the API call
  List<Lecture> _allLectures = []; // Stores the latest lectures from the stream

  // --- Filter State ---
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  // --- End Filter State ---

  bool _isCheckingInViaQr = false; // Flag to prevent concurrent QR check-in actions
  String? _deletingLectureId; // New flag to track which lecture is being deleted

  static const Color brandColor = Color(0xFF0175C2);
  final RegExp allowedRegNumChars = RegExp(r'^[A-Z0-9/-]+$');

  @override
  void initState() {
    super.initState();
    loadLectures(); // Initial load of lectures
  }

  // Fetches lectures created by the current lecturer
 void loadLectures() {
    if (!mounted) return;
    if (kDebugMode) print("Fetching lectures for lecturer ID: ${widget.currentUser.id}");
    setState(() {
      _lecturesStream = Stream<List<Lecture>>.fromFuture(
        apiService.getLecturesForLecturer(widget.currentUser.id),
      );
    });
  }

  Future<void> _showDateFilterDialog() async {
    final DateTime firstDate = DateTime.now().subtract(const Duration(days: 365)); // Allow filtering past year
    final DateTime lastDate = DateTime.now().add(const Duration(days: 365)); // Allow filtering future year

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      initialDateRange: _filterStartDate != null && _filterEndDate != null
          ? DateTimeRange(start: _filterStartDate!, end: _filterEndDate!)
          : null, // Pre-select range if already set
      firstDate: firstDate,
      lastDate: lastDate,
      helpText: 'Select Lecture Date Range',
      saveText: 'Apply Filter',
      builder: (context, child) {
        // Optional: Theme the picker
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
                  primary: brandColor,
                  onPrimary: Colors.white,
                  surface: Colors.white,
                  onSurface: Colors.black87,
                ), dialogTheme: DialogThemeData(backgroundColor: Colors.white),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      // Update state and apply filters
      setState(() {
        _filterStartDate = picked.start;
        _filterEndDate = picked.end;
      });
    }
  }

  void _clearFilters() {
    setState(() {
      _filterStartDate = null;
      _filterEndDate = null;
    });
  }
  // --- End Filtering Logic ---

  // Helper to show a user-friendly error dialog
  void _showErrorDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Row(children: [ Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error), const SizedBox(width: 10), Text(title), ]),
            content: Text(content),
            actions: <Widget>[ TextButton(child: const Text('OK'), onPressed: () => Navigator.of(dialogContext).pop()), ],
          );
        });
  }


  // Helper to show snackbar messages
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

  // Shows the dialog to create a new lecture
  void showCreateLectureDialog() async {
    if (_isCheckingInViaQr || _deletingLectureId != null) return; // Disable if other actions are processing
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return CreateLectureDialog(currentUser: widget.currentUser);
      },
    );
    if (result == true && mounted) {
      // Stream will auto-update, just show snackbar
      showSnackBar('Lecture created successfully!', isError: false);
    }
  }

  /// Performs the actual check-in API call and handles responses.
  Future<bool> _performCheckIn(String registrationNumber, Lecture lecture, BuildContext currentContext) async {
    if (!allowedRegNumChars.hasMatch(registrationNumber)) {
       _showErrorDialog('Check-in Failed', 'Invalid registration number format: ');
       return false;
    }

    try {
      final AttendanceRecord checkedInRecord = await apiService.checkInStudent(
        lecture.id,
        registrationNumber,
      );
      if (!currentContext.mounted) return false;
      showSnackBar('Student ${checkedInRecord.studentName} (${checkedInRecord.registrationNumber}) checked in!', isError: false);
      return true;

    } catch (e) {
       if (!currentContext.mounted) return false;
       String errorMessage = 'Check-in failed.';
       if (e is ApiException) {
         if (e.statusCode == 400 || e.statusCode == 404) {
           errorMessage = e.message.contains("join")
               ? 'Check-in failed: Student has not joined this lecture yet.'
               : 'Check-in failed: Student () not found or invalid request.';
         } else if (e.statusCode == 409) {
           errorMessage = 'Check-in failed: Student is already checked in.';
         } else {
           errorMessage = 'Check-in failed: ${e.message}';
         }
         if (kDebugMode) print("API Check-In Error (${e.statusCode}): ${e.message}");
       } else {
         errorMessage = 'Check-in failed: ${e.toString().replaceFirst("Exception: ", "")}';
         if (kDebugMode) print("Generic Check-In Error: ");
       }
       // Use the main screen's error dialog for consistency
       if (mounted) {
         _showErrorDialog('Check-in Failed', errorMessage);
       }
       return false;
    }
  }

  // Shows the dialog for manual student check-in via registration number
  void showCheckInDialog(Lecture lecture) {
    if (_isCheckingInViaQr || _deletingLectureId != null) return; // Disable if other actions are processing
    final registrationNumberController = TextEditingController();
    bool isCheckingIn = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Text('Manual Check-In: ${lecture.unitName}'),
              content: TextField(
                controller: registrationNumberController,
                decoration: InputDecoration(
                  labelText: 'Student Registration Number', hintText: 'e.g., SSTE/COM03/047/21',
                  prefixIcon: Icon(Icons.badge_outlined, color: brandColor.withOpacity(0.7)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade400)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: brandColor, width: 1.5)),
                  filled: true, fillColor: Colors.grey[50],
                ),
                inputFormatters: [ UpperCaseTextFormatter(), FilteringTextInputFormatter.allow(allowedRegNumChars), ],
                keyboardType: TextInputType.text, textCapitalization: TextCapitalization.characters, autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) async {
                   if (isCheckingIn) return;
                   final registrationNumber = registrationNumberController.text.trim();
                   if (registrationNumber.isEmpty) { return; }
                   setDialogState(() => isCheckingIn = true);
                   bool success = await _performCheckIn(registrationNumber, lecture, dialogContext);
                   if (success && dialogContext.mounted) { Navigator.of(dialogContext).pop(); }
                   else if (dialogContext.mounted) { setDialogState(() => isCheckingIn = false); }
                },
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              actions: [
                TextButton( onPressed: isCheckingIn ? null : () => Navigator.of(dialogContext).pop(), child: const Text('Cancel'), ),
                ElevatedButton(
                  onPressed: isCheckingIn ? null : () async {
                    final registrationNumber = registrationNumberController.text.trim();
                    if (registrationNumber.isEmpty) { return; }
                    setDialogState(() => isCheckingIn = true);
                    bool success = await _performCheckIn(registrationNumber, lecture, dialogContext);
                    if (success && dialogContext.mounted) { Navigator.of(dialogContext).pop(); }
                    else if (dialogContext.mounted) { setDialogState(() => isCheckingIn = false); }
                  },
                  style: ElevatedButton.styleFrom( backgroundColor: brandColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), ),
                  child: isCheckingIn ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Check In'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  // Handles scanning a student's QR code for check-in
  Future<void> _scanQrCodeAndCheckIn(Lecture lecture) async {
    if (!mounted || _isCheckingInViaQr || _deletingLectureId != null) return; // Disable if other actions are processing

    final String? scannedRegNum = await Navigator.push<String>( context, MaterialPageRoute(builder: (context) => const QrScannerScreen()), );
    if (!mounted) return;

    if (scannedRegNum != null && scannedRegNum.isNotEmpty) {
      if (kDebugMode) print("Scanned Registration Number: ");
      final String processedRegNum = scannedRegNum.trim().toUpperCase();

      setState(() { _isCheckingInViaQr = true; });
      await _performCheckIn(processedRegNum, lecture, context);
      if (mounted) { setState(() { _isCheckingInViaQr = false; }); }
    } else {
      if (kDebugMode) print("QR Scan cancelled or returned empty.");
    }
  }

  // Shows the dialog to edit an existing lecture
  Future<void> _showEditLectureDialog(Lecture lecture) async {
    if (_isCheckingInViaQr || _deletingLectureId != null) return;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return EditLectureDialog(lecture: lecture);
      },
    );
    if (result == true && mounted) {
      showSnackBar('Lecture "${lecture.unitName}" updated successfully.', isError: false);
      // Stream will auto-update
    }
  }

  // --- New: Confirm and Delete Lecture ---
  Future<void> _confirmAndDeleteLecture(Lecture lecture) async {
    if (_isCheckingInViaQr || _deletingLectureId != null) return; // Prevent multiple actions

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: const Text('Confirm Deletion'),
          content: Text('Are you sure you want to delete the lecture "${lecture.unitName}" (${lecture.unitCode})?\nThis action cannot be undone and will also delete all associated attendance records.'),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (confirm == true && mounted) {
      await _deleteLecture(lecture);
    }
  }

  // --- New: Delete Lecture ---
  Future<void> _deleteLecture(Lecture lecture) async {
    if (!mounted) return;
    setState(() {
      _deletingLectureId = lecture.id; // Set the ID of the lecture being deleted
    });

    try {
      await apiService.deleteLecture(lecture.id);
      if (!mounted) return;
      showSnackBar('Lecture "${lecture.unitName}" deleted successfully.', isError: false);
      // The stream will update the list automatically.
    } catch (e) {
      if (!mounted) return;
      String errorMessage = 'Failed to delete lecture.';
      if (e is ApiException) {
        errorMessage += ' ${e.message}';
        if (kDebugMode) print("API Delete Error: ${e.statusCode} - ${e.message}");
      } else {
        errorMessage += ' Please try again.';
        if (kDebugMode) print("Generic Delete Error: ");
      }
      _showErrorDialog('Deletion Failed', errorMessage);
    } finally {
      if (mounted) {
        setState(() {
          _deletingLectureId = null; // Clear the deleting ID
        });
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final textTheme = Theme.of(context).textTheme;
    final DateFormat filterDateFormat = DateFormat.yMMMd(); // Format for displaying filter dates

    // Determine if any action is currently processing to disable buttons
    final bool isAnyActionProcessing = _isCheckingInViaQr || _deletingLectureId != null;

    return Scaffold(
      appBar: AppBar(
        title: Text('Lecturer Dashboard - ${widget.currentUser.name}', style: const TextStyle(fontSize: 18)),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        elevation: 2.0,
        actions: [
          if (isAnyActionProcessing) // Show global loading indicator if any action is processing
             const Padding(
               padding: EdgeInsets.only(right: 15.0),
               child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
             ),
          // --- Filter Button ---
          IconButton(
            icon: Icon(Icons.filter_list, color: (_filterStartDate != null || _filterEndDate != null) ? Colors.amberAccent : Colors.white),
            tooltip: 'Filter by Date',
            onPressed: isAnyActionProcessing ? null : _showDateFilterDialog, // Disable if any action is processing
          ),
          // --- End Filter Button ---
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Lectures',
            onPressed: isAnyActionProcessing ? null : loadLectures, // Disable if any action is processing
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: isAnyActionProcessing ? null : () async { // Disable if any action is processing
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
              if (confirm == true && mounted) {
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
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create New Lecture'),
              onPressed: isAnyActionProcessing ? null : showCreateLectureDialog, // Disable if any action is processing
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52), backgroundColor: brandColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const Divider(thickness: 0.5, height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            child: Text( "Your Created Lectures", style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: brandColor), textAlign: TextAlign.center, ),
          ),

          // --- Display Active Filter ---
          if (_filterStartDate != null || _filterEndDate != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Chip(
                    label: Text(
                      'Filtered: ${ _filterStartDate != null ? filterDateFormat.format(_filterStartDate!) : 'Start'} - ${ _filterEndDate != null ? filterDateFormat.format(_filterEndDate!) : 'End'}',
                      style: const TextStyle(fontSize: 12, color: brandColor),
                    ),
                    backgroundColor: brandColor.withOpacity(0.1),
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    visualDensity: VisualDensity.compact,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.clear, size: 18, color: Colors.grey.shade600),
                    tooltip: 'Clear Date Filter',
                    onPressed: _clearFilters,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    visualDensity: VisualDensity.compact,
                  )
                ],
              ),
            ),
          // --- End Display Active Filter ---

          Expanded(
            child: RefreshIndicator(
              color: brandColor,
              onRefresh: () async => loadLectures(),
              child: StreamBuilder<List<Lecture>>(
                stream: _lecturesStream,
                builder: (context, snapshot) {
                  // Handle stream data
                  if (snapshot.hasData) {
                    _allLectures = snapshot.data ?? [];
                  }

                  // --- Perform Filtering Here ---
                  List<Lecture> currentlyDisplayed = List.from(_allLectures);
                  if (_filterStartDate != null || _filterEndDate != null) {
                    currentlyDisplayed = currentlyDisplayed.where((lecture) {
                      final lectureDate = lecture.startTime?.toLocal();
                      if (lectureDate == null) return false;
                      final lectureDay = DateTime(lectureDate.year, lectureDate.month, lectureDate.day);
                      final filterStartDay = _filterStartDate != null ? DateTime(_filterStartDate!.year, _filterStartDate!.month, _filterStartDate!.day) : null;
                      final filterEndDay = _filterEndDate != null ? DateTime(_filterEndDate!.year, _filterEndDate!.month, _filterEndDate!.day) : null;
                      bool afterStartDate = filterStartDay == null || !lectureDay.isBefore(filterStartDay);
                      bool beforeEndDate = filterEndDay == null || !lectureDay.isAfter(filterEndDay);
                      return afterStartDate && beforeEndDate;
                    }).toList();
                  }
                  currentlyDisplayed.sort((a, b) {
                    final aTime = a.startTime; final bTime = b.startTime;
                    if (aTime != null && bTime != null) return bTime.compareTo(aTime);
                    return (aTime == null) ? 1 : -1;
                  });
                  // --- End Filtering ---

                  // --- Loading State ---
                  if (snapshot.connectionState == ConnectionState.waiting && _allLectures.isEmpty) {
                     // Show loading only on initial load or if _allLectures is empty
                    return const Center(child: CircularProgressIndicator(color: brandColor));
                  }
                  // --- Error State ---
                  if (snapshot.hasError && _allLectures.isEmpty) { // Show error only if no data was previously loaded
                    final error = snapshot.error;
                    String displayMessage = 'Error loading lectures.';
                    if (error is ApiException) { displayMessage = error.message; }
                    else if (error is TimeoutException) { displayMessage = 'Request timed out.'; }
                    else { displayMessage = 'An unexpected error occurred.'; }
                    if (kDebugMode) print("Error fetching lectures Future: ");
                    return Center(
                       child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
                            const SizedBox(height: 10),
                            Text(
                              '\n$displayMessage\n\nPlease check connection.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 15),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh), label: const Text('Retry'),
                              onPressed: loadLectures,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                            ),
                            if (kDebugMode)
                              Padding(
                                padding: const EdgeInsets.only(top: 8.0),
                                child: Text('\nDetails: ${error?.toString() ?? 'No details available.'}', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                              ),
                          ],
                        ),
                      )
                    );
                  }

                  // --- Empty or Filtered Empty State ---
                  if (currentlyDisplayed.isEmpty) {
                    return LayoutBuilder(
                       builder: (context, constraints) {
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
                                    Icon(
                                      (_filterStartDate != null || _filterEndDate != null)
                                          ? Icons.filter_alt_off_outlined // Icon for filtered empty
                                          : Icons.event_note_outlined, // Icon for no lectures created
                                      size: 50, color: Colors.grey.shade400
                                    ),
                                    const SizedBox(height: 10),
                                    Text(
                                      (_filterStartDate != null || _filterEndDate != null)
                                          ? 'No lectures found for the selected date range.\nTry adjusting the filter or pull down to refresh.'
                                          : 'You have not created any lectures yet.\nTap "Create New Lecture" or pull down to refresh.',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    );
                  }

                  // --- Success State - Display Lectures ---
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    itemCount: currentlyDisplayed.length, // Use filtered list
                    itemBuilder: (context, index) { // Start of itemBuilder
                      final lecture = currentlyDisplayed[index]; // Use filtered list
                      final dateTimeText = '${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}';
                      
                      // Build the subtitle dynamically with DocumentNameWidget
                      final subtitleWidgets = <Widget>[
                        DocumentNameWidget(collection: 'courses', documentId: lecture.course, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3)),
                        Row(
                          children: [
                            DocumentNameWidget(collection: 'years_of_study', documentId: lecture.yearOfStudy, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3)),
                            Text(' | ', style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3)), // Separator
                            DocumentNameWidget(collection: 'semesters', documentId: lecture.semester, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3)),
                          ],
                        ),
                        Text(dateTimeText, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3)),
                        Row(
                          children: [
                            Text('Venue: ', style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3)),
                            // Use DocumentNameWidget to check the venue name
                            DocumentNameWidget(
                              collection: 'venues', documentId: lecture.venue, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3),
                              builder: (context, venueName) {
                                // Conditionally show the online link based on the fetched venue name
                                if (venueName?.toUpperCase() == 'ONLINE' && lecture.onlineLink != null && lecture.onlineLink!.isNotEmpty) {
                                  return Flexible(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(venueName ?? lecture.venue, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3)),
                                        Text(
                                          'Link: ${lecture.onlineLink}',
                                          style: textTheme.bodySmall?.copyWith(color: Colors.blue.shade700, height: 1.3),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  );
                                }
                                // Otherwise, just show the venue name
                                return Text(venueName ?? lecture.venue, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3));
                              },
                            ),
                          ],
                        ),
                      ];
                      return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                          elevation: 1.5,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: isAnyActionProcessing ? null : () { // Disable if any action is processing
                               Navigator.push( context, MaterialPageRoute( builder: (context) => LectureAttendanceScreen(lecture: lecture), ), );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                              child: Row(
                                children: [
                                  const CircleAvatar( backgroundColor: brandColor, child: Icon(Icons.school_outlined, size: 22, color: Colors.white), ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text( '${lecture.unitName} (${lecture.unitCode})', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), ),
                                        const SizedBox(height: 6),
                                        ...subtitleWidgets.map((widget) => Padding(
                                          padding: const EdgeInsets.only(top: 1.0),
                                          child: widget,
                                        )),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18), label: const Text('Check-In'),
                                            onPressed: isAnyActionProcessing ? null : () => showCheckInDialog(lecture), // Disable if any action is processing
                                            style: ElevatedButton.styleFrom( backgroundColor: brandColor.withOpacity(0.15), foregroundColor: brandColor, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), ),
                                          ),
                                          const SizedBox(height: 4),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // QR Scan Button
                                              IconButton(
                                                icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scan Student QR Code', color: brandColor.withOpacity(0.8), iconSize: 26, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                                onPressed: isAnyActionProcessing ? null : () => _scanQrCodeAndCheckIn(lecture), // Disable if any action is processing
                                              ),
                                              // Edit Button
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined), tooltip: 'Edit Lecture', color: brandColor.withOpacity(0.9), iconSize: 26, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: const BoxConstraints(),
                                                onPressed: isAnyActionProcessing ? null : () => _showEditLectureDialog(lecture), // Disable if any action is processing
                                              ),
                                              // --- New: Delete Button ---
                                              IconButton(
                                                icon: _deletingLectureId == lecture.id
                                                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red))
                                                    : const Icon(Icons.delete_outline),
                                                tooltip: 'Delete Lecture',
                                                color: Colors.red.shade700,
                                                iconSize: 26,
                                                visualDensity: VisualDensity.compact,
                                                padding: EdgeInsets.zero,
                                                constraints: const BoxConstraints(),
                                                onPressed: _deletingLectureId == lecture.id || isAnyActionProcessing
                                                    ? null
                                                    : () => _confirmAndDeleteLecture(lecture),
                                              ),
                                              // --- End New: Delete Button ---
                                            ],
                                          ),
                                        ],
                                      ),
                                ],
                              ),
                            ),
                          ),
                      );
                    }, // End of itemBuilder
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
