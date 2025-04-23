// lib/screens/lecturer_dashboard.dart
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/screens/lecture_attendance_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:checkmate/services/api_service.dart'; // Import ApiException
import 'package:checkmate/widgets/create_lecture_dialog.dart';
import 'package:checkmate/widgets/edit_lecture_dialog.dart';
import 'package:flutter/material.dart';
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/screens/welcome_screen.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart';
import 'package:checkmate/screens/qr_scanner_screen.dart';
import 'package:flutter/foundation.dart'; // For kDebugMode

// --- UpperCaseTextFormatter (Keep as is) ---
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
  late Future<List<Lecture>> lecturesFuture;
  bool _isCheckingInViaQr = false; // Flag to prevent concurrent QR check-in actions

  static const Color brandColor = Color(0xFF0175C2);
  // Regex for allowed characters in registration numbers (adjust as needed)
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
      lecturesFuture = apiService.getLecturesForLecturer(widget.currentUser.id);
    });
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

  // Shows the dialog to create a new lecture
  void showCreateLectureDialog() async {
    if (_isCheckingInViaQr) return; // Prevent opening while QR check-in is active
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent closing by tapping outside
      builder: (BuildContext context) {
        return CreateLectureDialog(currentUser: widget.currentUser);
      },
    );
    // If the dialog returned true (success), reload lectures and show confirmation
    if (result == true && mounted) {
      loadLectures();
      showSnackBar('Lecture created successfully!', isError: false);
    }
  }

  /// Performs the actual check-in API call and handles responses.
  /// Returns true on success, false on failure.
  Future<bool> _performCheckIn(String registrationNumber, Lecture lecture, BuildContext currentContext) async {
    // Basic client-side validation (backend MUST re-validate)
    if (!allowedRegNumChars.hasMatch(registrationNumber)) {
       if (currentContext.mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
             SnackBar(content: Text('Invalid registration number format: $registrationNumber'), backgroundColor: Colors.red)
          );
       }
       return false;
    }

    try {
      // Call the API service to check-in the student
      final AttendanceRecord checkedInRecord = await apiService.checkInStudent(
        lecture.id,
        registrationNumber,
      );
      // If successful and context is still valid, show success message
      if (!currentContext.mounted) return false;
      ScaffoldMessenger.of(currentContext).showSnackBar(
         SnackBar(content: Text('Student ${checkedInRecord.studentName} (${checkedInRecord.registrationNumber}) checked in!'), backgroundColor: Colors.green.shade600) // Use greener success color
      );
      return true; // Indicate success

    // --- *** MODIFIED CATCH BLOCK for Specific Error Handling *** ---
    } catch (e) {
       if (!currentContext.mounted) return false; // Check context after async error

       String errorMessage = 'Check-in failed.'; // Default error message

       if (e is ApiException) {
         // Handle specific API errors based on status code
         if (e.statusCode == 400 || e.statusCode == 404) {
           // Assume 400/404 means student not found OR hasn't joined yet (backend logic dependent)
           // Use the specific message from the API if available and informative
           errorMessage = e.message.contains("join") // Check if message hints at "not joined"
               ? 'Check-in failed: Student has not joined this lecture yet.'
               : 'Check-in failed: Student ($registrationNumber) not found or invalid request.';
         } else if (e.statusCode == 409) {
           // Assume 409 means student is already checked in
           errorMessage = 'Check-in failed: Student is already checked in.';
         } else {
           // Use the message from the API exception for other cases
           errorMessage = 'Check-in failed: ${e.message}';
         }
         if (kDebugMode) print("API Check-In Error (${e.statusCode}): ${e.message}");
       } else {
         // Handle non-API exceptions (network errors, etc.)
         errorMessage = 'Check-in failed: ${e.toString().replaceFirst("Exception: ", "")}';
         if (kDebugMode) print("Generic Check-In Error: $e");
       }

       // Show the determined error message
       ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red)
       );
       return false; // Indicate failure
    }
    // --- *** END MODIFIED CATCH BLOCK *** ---
  }

  // Shows the dialog for manual student check-in via registration number
  void showCheckInDialog(Lecture lecture) {
    if (_isCheckingInViaQr) return; // Prevent opening while QR check-in is active
    final registrationNumberController = TextEditingController();
    bool isCheckingIn = false; // State for the dialog's loading indicator

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing without action
      builder: (dialogContext) {
        // Use StatefulBuilder to manage the dialog's internal loading state
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
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: brandColor, width: 1.5)),
                  filled: true, fillColor: Colors.grey[50],
                ),
                // Formatters and input type
                inputFormatters: [ UpperCaseTextFormatter(), FilteringTextInputFormatter.allow(allowedRegNumChars), ],
                keyboardType: TextInputType.text, textCapitalization: TextCapitalization.characters, autofocus: true,
                textInputAction: TextInputAction.done,
                // Allow submitting via keyboard 'done' button
                onSubmitted: (_) async {
                   if (isCheckingIn) return; // Prevent multiple submissions
                   final registrationNumber = registrationNumberController.text.trim();
                   if (registrationNumber.isEmpty) {
                      // Use ScaffoldMessenger of the dialogContext
                      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Please enter a registration number.'), backgroundColor: Colors.red)); return;
                   }
                   // Set loading state and perform check-in
                   setDialogState(() => isCheckingIn = true);
                   bool success = await _performCheckIn(registrationNumber, lecture, dialogContext);
                   // Close dialog on success, otherwise reset loading state
                   if (success && dialogContext.mounted) { Navigator.of(dialogContext).pop(); }
                   else if (dialogContext.mounted) { setDialogState(() => isCheckingIn = false); }
                },
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              actions: [
                TextButton( onPressed: isCheckingIn ? null : () => Navigator.of(dialogContext).pop(), child: const Text('Cancel'), ),
                ElevatedButton(
                  // Disable button while checking in
                  onPressed: isCheckingIn ? null : () async {
                    final registrationNumber = registrationNumberController.text.trim();
                    if (registrationNumber.isEmpty) {
                      // Use ScaffoldMessenger of the dialogContext
                      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Please enter a registration number.'), backgroundColor: Colors.red)); return;
                    }
                    // Set loading state and perform check-in
                    setDialogState(() => isCheckingIn = true);
                    bool success = await _performCheckIn(registrationNumber, lecture, dialogContext);
                    // Close dialog on success, otherwise reset loading state
                    if (success && dialogContext.mounted) { Navigator.of(dialogContext).pop(); }
                    else if (dialogContext.mounted) { setDialogState(() => isCheckingIn = false); }
                  },
                  style: ElevatedButton.styleFrom( backgroundColor: brandColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), ),
                  // Show loading indicator or text based on state
                  child: isCheckingIn ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Text('Check In'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  // Handles scanning a student's QR code (containing their reg number) for check-in
  Future<void> _scanQrCodeAndCheckIn(Lecture lecture) async {
    if (!mounted || _isCheckingInViaQr) return; // Prevent concurrent scans

    // Navigate to QR scanner screen
    final String? scannedRegNum = await Navigator.push<String>( context, MaterialPageRoute(builder: (context) => const QrScannerScreen()), );
    if (!mounted) return; // Check mount status after returning

    // If a registration number was scanned
    if (scannedRegNum != null && scannedRegNum.isNotEmpty) {
      if (kDebugMode) print("Scanned Registration Number: $scannedRegNum");
      final String processedRegNum = scannedRegNum.trim().toUpperCase(); // Process scanned data

      // Set loading state for the main screen
      setState(() { _isCheckingInViaQr = true; });
      // Perform the check-in using the common function
      // Pass the main screen's context here
      await _performCheckIn(processedRegNum, lecture, context);
      // Clear loading state
      if (mounted) { setState(() { _isCheckingInViaQr = false; }); }
    } else {
      if (kDebugMode) print("QR Scan cancelled or returned empty.");
    }
  }

  // Shows the dialog to edit an existing lecture
  Future<void> _showEditLectureDialog(Lecture lecture) async {
    if (_isCheckingInViaQr) return; // Prevent opening while QR check-in is active
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent closing by tapping outside
      builder: (BuildContext context) {
        return EditLectureDialog(lecture: lecture);
      },
    );
    // If the dialog returned true (success), reload lectures and show confirmation
    if (result == true && mounted) {
      showSnackBar('Lecture "${lecture.unitName}" updated successfully.', isError: false);
      loadLectures();
    }
  }

  @override
  void dispose() {
    // Clean up resources if needed (though no controllers are defined at this level)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Lecturer Dashboard - ${widget.currentUser.name}', style: const TextStyle(fontSize: 18)),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        elevation: 2.0,
        actions: [
          // Show loading indicator in AppBar if QR check-in is active
          if (_isCheckingInViaQr)
             const Padding(
               padding: EdgeInsets.only(right: 15.0),
               child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
             ),
          // Refresh button (disabled during QR check-in)
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Lectures',
            onPressed: _isCheckingInViaQr ? null : loadLectures,
          ),
          // Logout button (disabled during QR check-in)
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: _isCheckingInViaQr ? null : () async {
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
          // "Create New Lecture" button
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create New Lecture'),
              onPressed: _isCheckingInViaQr ? null : showCreateLectureDialog, // Disabled during QR check-in
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
          // Lecture List Area
          Expanded(
            child: RefreshIndicator(
              color: brandColor,
              onRefresh: () async => loadLectures(), // Pull-to-refresh action
              child: FutureBuilder<List<Lecture>>(
                future: lecturesFuture,
                builder: (context, snapshot) {
                  // Loading State
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: brandColor));
                  }
                  // Error State
                  if (snapshot.hasError) {
                    if (kDebugMode) print("Error fetching lectures Future: ${snapshot.error}");
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
                            const SizedBox(height: 10),
                            Text( 'Error loading lectures.\nPlease check connection.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700), ),
                            const SizedBox(height: 15),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh), label: const Text('Retry'),
                              onPressed: loadLectures,
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                            )
                          ],
                        ),
                      )
                    );
                  }
                  // Empty State
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView( // Make it scrollable for refresh
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight), // Fill height
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.event_note_outlined, size: 50, color: Colors.grey.shade400),
                                    const SizedBox(height: 10),
                                    Text( 'You have not created any lectures yet.\nTap "Create New Lecture" or pull down to refresh.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    );
                  }

                  // Success State - Display Lectures
                  final lectures = snapshot.data!;
                  // Sort lectures: Most recent date first, then most recent start time
                  lectures.sort((a, b) {
                     final aDate = a.lectureDate; final bDate = b.lectureDate;
                     if (aDate != null && bDate != null) {
                       int dateComp = bDate.compareTo(aDate); // Descending date
                       if (dateComp != 0) return dateComp;
                     } else if (aDate == null && bDate != null) { return 1; } // Nulls last
                       else if (aDate != null && bDate == null) { return -1; }

                     final aTime = a.startTime; final bTime = b.startTime;
                     if (aTime != null && bTime != null) {
                        return bTime.compareTo(aTime); // Descending time
                     } else if (aTime == null && bTime != null) { return 1; } // Nulls last
                       else if (aTime != null && bTime == null) { return -1; }
                       else { return 0; }
                  });

                  // Build the list view
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(), // Ensure refresh works
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    itemCount: lectures.length,
                    itemBuilder: (context, index) {
                      final lecture = lectures[index];
                      // Combine year/semester text safely
                      final yearSemesterText = [lecture.yearOfStudy, lecture.semester]
                          .where((s) => s.isNotEmpty)
                          .join(' | ');

                      final courseText = lecture.course ?? 'N/A';
                      // Combine date/time text using formatted getters
                      final dateTimeText = '${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}';
                      final venueText = 'Venue: ${lecture.venue}';
                      // Add online link info if available
                      final onlineLinkText = (lecture.venue.toUpperCase() == 'ONLINE' && lecture.onlineLink != null && lecture.onlineLink!.isNotEmpty)
                          ? 'Link: ${lecture.onlineLink}' // Consider shortening if needed
                          : null;

                      // Build subtitle string, including online link if present
                      final subtitleParts = [courseText, yearSemesterText, dateTimeText, venueText];
                      if (onlineLinkText != null) {
                          subtitleParts.add(onlineLinkText);
                      }
                      final subtitleText = subtitleParts
                          .where((part) => part.isNotEmpty)
                          .join('\n');

                      return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                          elevation: 1.5,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: InkWell( // Make the whole card tappable to view attendance
                            borderRadius: BorderRadius.circular(10),
                            onTap: _isCheckingInViaQr ? null : () {
                               // Navigate to the detailed attendance screen for this lecture
                               Navigator.push( context, MaterialPageRoute( builder: (context) => LectureAttendanceScreen(lecture: lecture), ), );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                              child: Row(
                                children: [
                                  // Leading Icon
                                  CircleAvatar( backgroundColor: brandColor.withOpacity(0.1), child: Icon(Icons.school_outlined, size: 22, color: brandColor), ),
                                  const SizedBox(width: 16),
                                  // Main Lecture Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text( '${lecture.unitName} (${lecture.unitCode})', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), ),
                                        const SizedBox(height: 4),
                                        Text( subtitleText, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3), ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Action Buttons Column
                                  Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Manual Check-In Button
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18), label: const Text('Check-In'),
                                            onPressed: _isCheckingInViaQr ? null : () => showCheckInDialog(lecture), // Disabled during QR scan
                                            style: ElevatedButton.styleFrom( backgroundColor: brandColor.withOpacity(0.15), foregroundColor: brandColor, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), ),
                                          ),
                                          const SizedBox(height: 4),
                                          // Row for smaller icon buttons (QR Scan, Edit)
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // Scan Student QR Button
                                              IconButton(
                                                icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scan Student QR Code', color: brandColor.withOpacity(0.8), iconSize: 26, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: BoxConstraints(),
                                                onPressed: _isCheckingInViaQr ? null : () => _scanQrCodeAndCheckIn(lecture), // Disabled during QR scan
                                              ),
                                              const SizedBox(width: 4),
                                              // Edit Lecture Button
                                              IconButton(
                                                icon: const Icon(Icons.edit_outlined), tooltip: 'Edit Lecture', color: brandColor.withOpacity(0.9), iconSize: 26, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: BoxConstraints(),
                                                onPressed: _isCheckingInViaQr ? null : () => _showEditLectureDialog(lecture), // Disabled during QR scan
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                ],
                              ),
                            ),
                          ),
                      );
                    },
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
