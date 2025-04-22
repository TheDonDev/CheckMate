// lib/screens/lecturer_dashboard.dart
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/screens/lecture_attendance_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:checkmate/services/api_service.dart'; // Ensure this uses the updated ApiService
import 'package:checkmate/widgets/create_lecture_dialog.dart';
import 'package:flutter/material.dart';
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/screens/welcome_screen.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart'; // Import for input formatters

// --- Import the QR Scanner Screen ---
import 'package:checkmate/screens/qr_scanner_screen.dart'; // Ensure this path is correct

// --- Custom Input Formatter to force uppercase input ---
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
  bool _isCheckingInViaQr = false; // Loading state for QR check-in
  // --- Add Delete State ---
  bool _isDeleting = false; // Loading state for delete operation
  String? _deletingLectureId; // Track which lecture is being deleted
  // --- End Delete State ---

  // Define the brand color (consistent styling)
  static const Color brandColor = Color(0xFF0175C2);
  // Define the allowed characters regex consistent with register_screen.dart
  final RegExp allowedRegNumChars = RegExp(r'^[A-Z0-9/-]+$');

  @override
  void initState() {
    super.initState();
    loadLectures();
  }

  // Method to load lectures for the current lecturer
  void loadLectures() {
    if (!mounted) return;
    print("Fetching lectures for lecturer ID: ${widget.currentUser.id}"); // Debugging statement
    setState(() {
      // Fetch lectures using the ApiService
      lecturesFuture = apiService.getLecturesForLecturer(widget.currentUser.id);
    });
  }

  // Helper to show snackbar messages (uses the main Scaffold context)
  void showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green,
        behavior: SnackBarBehavior.floating, // Consistent behavior
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(10),
      ),
    );
  }

  // Method to show the dialog for creating a new lecture
  void showCreateLectureDialog() async {
    // Prevent opening if another operation is in progress
    if (_isCheckingInViaQr || _isDeleting) return;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (BuildContext context) {
        return CreateLectureDialog(currentUser: widget.currentUser);
      },
    );
    if (result == true && mounted) {
      loadLectures(); // Refresh the list of lectures after creation
      showSnackBar('Lecture created successfully!', isError: false); // Show success message
    }
  }

  // --- Refactored Check-In Logic ---
  Future<bool> _performCheckIn(String registrationNumber, Lecture lecture, BuildContext currentContext) async {
    // Validate registration number format before sending to API
    if (!allowedRegNumChars.hasMatch(registrationNumber)) {
       if (currentContext.mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
             SnackBar(content: Text('Invalid registration number format: $registrationNumber'), backgroundColor: Colors.red)
          );
       }
       return false;
    }
    try {
      // Call the API service to check in the student
      final AttendanceRecord checkedInRecord = await apiService.checkInStudent(
        lecture.id,
        registrationNumber,
      );
      // Show success message if mounted
      if (!currentContext.mounted) return false;
      ScaffoldMessenger.of(currentContext).showSnackBar(
         SnackBar(content: Text('Student ${checkedInRecord.studentName} (${checkedInRecord.registrationNumber}) checked in!'), backgroundColor: Colors.green)
      );
      return true; // Indicate success
    } catch (e) {
       // Show error message if mounted
       if (!currentContext.mounted) return false;
       String errorMessage = 'Check-in failed: ${e.toString().replaceFirst("Exception: ", "")}';
       ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red)
       );
       return false; // Indicate failure
    }
  }


  // --- Manual Check-In Dialog ---
  void showCheckInDialog(Lecture lecture) {
    // Prevent opening if another operation is in progress
    if (_isCheckingInViaQr || _isDeleting) return;

    final registrationNumberController = TextEditingController();
    bool isCheckingIn = false; // State for the dialog's loading indicator

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent closing while checking in
      builder: (dialogContext) {
        // Use StatefulBuilder to manage the loading state within the dialog
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
                // Apply formatters and constraints
                inputFormatters: [ UpperCaseTextFormatter(), FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9/-]')), ],
                keyboardType: TextInputType.text, textCapitalization: TextCapitalization.characters, autofocus: true,
                textInputAction: TextInputAction.done,
                // Handle submission via keyboard action
                onSubmitted: (_) async {
                   if (isCheckingIn) return; // Prevent double submission
                   final registrationNumber = registrationNumberController.text.trim();
                   if (registrationNumber.isEmpty) {
                      // Show error within the dialog context
                      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Please enter a registration number.'), backgroundColor: Colors.red)); return;
                   }
                   setDialogState(() => isCheckingIn = true); // Show loading in button
                   bool success = await _performCheckIn(registrationNumber, lecture, dialogContext);
                   // Close dialog only on success
                   if (success && dialogContext.mounted) { Navigator.of(dialogContext).pop(); }
                   // Reset loading state on failure if dialog is still mounted
                   else if (dialogContext.mounted) { setDialogState(() => isCheckingIn = false); }
                },
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              actions: [
                // Cancel button
                TextButton( onPressed: isCheckingIn ? null : () => Navigator.of(dialogContext).pop(), child: const Text('Cancel'), ),
                // Check In button
                ElevatedButton(
                  onPressed: isCheckingIn ? null : () async {
                    final registrationNumber = registrationNumberController.text.trim();
                    if (registrationNumber.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Please enter a registration number.'), backgroundColor: Colors.red)); return;
                    }
                    setDialogState(() => isCheckingIn = true);
                    bool success = await _performCheckIn(registrationNumber, lecture, dialogContext);
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

  // --- Function to handle QR Code Scan Initiation ---
  Future<void> _scanQrCodeAndCheckIn(Lecture lecture) async {
    // Prevent initiating scan if another operation is in progress or widget is unmounted
    if (!mounted || _isCheckingInViaQr || _isDeleting) return;

    // Navigate to the QR Scanner screen and wait for a result
    final String? scannedRegNum = await Navigator.push<String>( context, MaterialPageRoute(builder: (context) => const QrScannerScreen()), );
    if (!mounted) return; // Check mount status after await

    // Process the scanned result if available
    if (scannedRegNum != null && scannedRegNum.isNotEmpty) {
      print("Scanned Registration Number: $scannedRegNum");
      final String processedRegNum = scannedRegNum.trim().toUpperCase(); // Ensure uppercase and trimmed

      // Set loading state for the main screen (e.g., disable buttons)
      setState(() { _isCheckingInViaQr = true; });
      // Perform the check-in using the scanned number
      await _performCheckIn(processedRegNum, lecture, context); // Use main context for snackbar
      // Reset loading state if mounted
      if (mounted) { setState(() { _isCheckingInViaQr = false; }); }
    } else {
      // Handle cancellation or empty scan result
      print("QR Scan cancelled or returned empty.");
      // Optionally show a snackbar message
      // showSnackBar("QR scan cancelled.", isError: true);
    }
  }

  // --- Function to show Delete Confirmation Dialog ---
  Future<void> _showDeleteConfirmationDialog(Lecture lecture) async {
    // Prevent opening if another operation is in progress
    if (_isCheckingInViaQr || _isDeleting) return;

    final bool? confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // User must explicitly confirm or cancel
      builder: (BuildContext dialogContext) {
        // Use StatefulBuilder to manage loading state within the dialog
        bool isDialogDeleting = false;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: const Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 10),
                  Text('Confirm Deletion'),
                ],
              ),
              content: Text('Are you sure you want to permanently delete the lecture:\n"${lecture.unitName} (${lecture.unitCode})"?\n\nThis action cannot be undone and will remove associated attendance data.'),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              actions: <Widget>[
                // Cancel button
                TextButton(
                  // Disable cancel while deleting
                  onPressed: isDialogDeleting ? null : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
                // Delete button
                ElevatedButton.icon(
                  icon: isDialogDeleting
                      ? Container() // Hide icon when loading
                      : const Icon(Icons.delete_forever, size: 20),
                  label: isDialogDeleting
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Delete'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red, // Destructive action color
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  // Disable button while deleting
                  onPressed: isDialogDeleting ? null : () async {
                    // Set loading state for the dialog button
                    setDialogState(() { isDialogDeleting = true; });
                    // Set loading state for the main screen (disables other actions)
                    setState(() { _isDeleting = true; _deletingLectureId = lecture.id; });

                    try {
                      // Call the API service to delete the lecture
                      await apiService.deleteLecture(lecture.id);
                      // If successful, pop the dialog with true
                      if (dialogContext.mounted) {
                         Navigator.of(dialogContext).pop(true);
                      }
                    } catch (e) {
                       // If error, show snackbar and pop dialog with false
                       if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop(false); // Close dialog on error
                          // Use the main context's showSnackBar
                          showSnackBar('Failed to delete lecture: ${e.toString().replaceFirst("Exception: ", "")}', isError: true);
                       }
                    } finally {
                       // Reset loading state for the main screen regardless of outcome
                       if (mounted) {
                          setState(() { _isDeleting = false; _deletingLectureId = null; });
                       }
                       // No need to reset isDialogDeleting as the dialog is popped
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );

    // If deletion was confirmed and successful (dialog popped with true)
    if (confirm == true && mounted) {
      showSnackBar('Lecture "${lecture.unitName}" deleted successfully.', isError: false);
      loadLectures(); // Refresh the list to remove the deleted lecture
    }
  }
  // --- End Delete Confirmation Dialog ---


  @override
  void dispose() {
    // Clean up resources if needed (though no controllers here)
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
          // --- Show loading indicator in AppBar if any operation is in progress ---
          if (_isCheckingInViaQr || _isDeleting)
             Padding(
               padding: const EdgeInsets.only(right: 15.0),
               child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
             ),
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Lectures',
            // Disable refresh while any operation is in progress
            onPressed: (_isCheckingInViaQr || _isDeleting) ? null : loadLectures,
          ),
          // Logout button
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            // Disable logout while any operation is in progress
            onPressed: (_isCheckingInViaQr || _isDeleting) ? null : () async {
              // Show confirmation dialog before logging out
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
              ) ?? false; // Default to false if dialog is dismissed

              // Perform logout and navigation if confirmed and mounted
              if (confirm == true && mounted) {
                await authService.logout();
                // Navigate to WelcomeScreen and remove all previous routes
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                  (Route<dynamic> route) => false, // Remove all routes
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Button to create a new lecture
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create New Lecture'),
              // Disable create button while any operation is in progress
              onPressed: (_isCheckingInViaQr || _isDeleting) ? null : showCreateLectureDialog,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52), backgroundColor: brandColor, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const Divider(thickness: 0.5, height: 1, indent: 16, endIndent: 16),
          // Title for the lectures list
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            child: Text( "Your Created Lectures", style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: brandColor), textAlign: TextAlign.center, ),
          ),
          // List of lectures
          Expanded(
            child: RefreshIndicator(
              color: brandColor, // Color of the refresh indicator
              onRefresh: () async => loadLectures(), // Trigger lecture loading on pull-to-refresh
              child: FutureBuilder<List<Lecture>>(
                future: lecturesFuture, // The future that fetches lecture data
                builder: (context, snapshot) {
                  // --- Loading State ---
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: brandColor));
                  }
                  // --- Error State ---
                  if (snapshot.hasError) {
                    print("Error fetching lectures Future: ${snapshot.error}"); // Log the error
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
                            const SizedBox(height: 10),
                            Text(
                              'Error loading lectures.\nPlease check connection.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
                            const SizedBox(height: 15),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.refresh),
                              label: const Text('Retry'),
                              onPressed: loadLectures, // Allow retrying
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                            )
                          ],
                        ),
                      )
                    );
                  }
                  // --- Empty State ---
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    // Use LayoutBuilder and SingleChildScrollView for consistent pull-to-refresh on empty list
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(), // Ensure scrollability for refresh
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight), // Take full height
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.event_note_outlined, size: 50, color: Colors.grey.shade400),
                                    const SizedBox(height: 10),
                                    Text(
                                      'You have not created any lectures yet.\nTap "Create New Lecture" or pull down to refresh.',
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

                  // --- Success State: Display Lectures ---
                  final lectures = snapshot.data!;
                  // Sort lectures by date and time (most recent first)
                  lectures.sort((a, b) {
                     final aDate = a.lectureDate; final bDate = b.lectureDate;
                     // Handle null dates if necessary (though they shouldn't be null ideally)
                     if (aDate == null && bDate == null) {} else if (aDate == null) { return 1; } else if (bDate == null) { return -1; } else { int dateComp = bDate.compareTo(aDate); if (dateComp != 0) return dateComp; }
                     // If dates are the same, sort by start time (most recent first)
                     final aTime = a.startTime; final bTime = b.startTime;
                     if (aTime == null && bTime == null) { return 0; } else if (aTime == null) { return 1; } else if (bTime == null) { return -1; } else { return bTime.compareTo(aTime); }
                  });

                  // Build the list view
                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(), // Ensure scrollability for refresh
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    itemCount: lectures.length,
                    itemBuilder: (context, index) {
                      final lecture = lectures[index];
                      // *** MODIFIED: Include Year and Semester in subtitle ***
                      final yearSemesterText = (lecture.semester != null)
                          ? '${lecture.yearOfStudy} | ${lecture.semester}'
                          : (lecture.yearOfStudy ?? lecture.semester ?? ''); // Show whichever is available or empty string

                      final courseText = lecture.course ?? 'N/A';
                      final dateTimeText = '${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}';
                      final venueText = 'Venue: ${lecture.venue ?? 'N/A'}';

                      // Combine subtitle parts, filtering out empty ones
                      final subtitleParts = [courseText, yearSemesterText, dateTimeText, venueText]
                          .where((part) => part.isNotEmpty)
                          .toList();
                      final subtitleText = subtitleParts.join('\n');
                      // *** END MODIFICATION ***

                      // Check if this specific lecture is being deleted to show loading state on the card
                      final bool isThisLectureDeleting = _isDeleting && _deletingLectureId == lecture.id;

                      return Opacity( // Fade out slightly if deleting
                        opacity: isThisLectureDeleting ? 0.5 : 1.0,
                        child: Card(
                          margin: const EdgeInsets.symmetric(vertical: 6.0),
                          elevation: 1.5,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            // Disable tap while deleting this lecture
                            onTap: isThisLectureDeleting ? null : () {
                               // Navigate to the attendance screen for this lecture
                               Navigator.push( context, MaterialPageRoute( builder: (context) => LectureAttendanceScreen(lecture: lecture), ), );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                              child: Row(
                                children: [
                                  // Leading icon (e.g., school icon)
                                  CircleAvatar( backgroundColor: brandColor.withOpacity(0.1), child: Icon(Icons.school_outlined, size: 22, color: brandColor), ),
                                  const SizedBox(width: 16),
                                  // Lecture details (Unit Name, Code, Subtitle)
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text( '${lecture.unitName} (${lecture.unitCode})', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), ),
                                        const SizedBox(height: 4),
                                        Text( subtitleText, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3), ), // Use the combined subtitle
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8), // Space before action buttons

                                  // --- Action Buttons Column ---
                                  // Show loading indicator instead of buttons if deleting this specific lecture
                                  isThisLectureDeleting
                                    ? const SizedBox( width: 40, height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red)) )
                                    : Column( // Otherwise, show the action buttons
                                        mainAxisSize: MainAxisSize.min, // Take minimum vertical space
                                        children: [
                                          // Manual Check-in button
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18), label: const Text('Check-In'),
                                            // Disable if any global operation (QR scan or delete) is in progress
                                            onPressed: (_isCheckingInViaQr || _isDeleting) ? null : () => showCheckInDialog(lecture),
                                            style: ElevatedButton.styleFrom( backgroundColor: brandColor.withOpacity(0.15), foregroundColor: brandColor, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), ),
                                          ),
                                          const SizedBox(height: 4), // Space between check-in and icon buttons
                                          // Row for QR Scan and Delete icon buttons
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // QR Scan Button
                                              IconButton(
                                                icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scan Student QR Code', color: brandColor.withOpacity(0.8), iconSize: 26, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: BoxConstraints(),
                                                // Disable if any global operation is in progress
                                                onPressed: (_isCheckingInViaQr || _isDeleting) ? null : () => _scanQrCodeAndCheckIn(lecture),
                                              ),
                                              const SizedBox(width: 4), // Space between icons
                                              // Delete Button
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline), tooltip: 'Delete Lecture', color: Colors.red.withOpacity(0.7), iconSize: 26, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: BoxConstraints(),
                                                // Disable if any global operation is in progress
                                                onPressed: (_isCheckingInViaQr || _isDeleting) ? null : () => _showDeleteConfirmationDialog(lecture),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                  // --- End Action Buttons Column ---
                                ],
                              ),
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
