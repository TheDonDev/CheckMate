// lib/screens/lecturer_dashboard.dart
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/screens/lecture_attendance_screen.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:checkmate/services/api_service.dart';
import 'package:checkmate/widgets/create_lecture_dialog.dart';
import 'package:flutter/material.dart';
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/screens/welcome_screen.dart';
import 'package:provider/provider.dart';
import 'package:flutter/services.dart'; // Import for input formatters

// --- Import the QR Scanner Screen ---
import 'package:checkmate/screens/qr_scanner_screen.dart'; // Ensure this path is correct

// --- Custom Input Formatter to force uppercase input ---
// (Consider moving this to a shared 'utils' or 'widgets' folder if used elsewhere)
class UpperCaseTextFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue oldValue, TextEditingValue newValue) {
    return TextEditingValue(
      text: newValue.text.toUpperCase(), // Convert text to uppercase
      selection: newValue.selection,     // Keep cursor position
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
    // Show the dialog and wait for its result
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent dismissing by tapping outside
      builder: (BuildContext context) {
        // Pass the current user data to the dialog
        return CreateLectureDialog(currentUser: widget.currentUser);
      },
    );
    // If the dialog returned true (indicating success) and the widget is still mounted, refresh the lectures list
    if (result == true && mounted) {
      loadLectures(); // Refresh the list of lectures after creation
      showSnackBar('Lecture created successfully!', isError: false); // Show success message
    }
  }

  // --- Refactored Check-In Logic (Handles API call and feedback) ---
  Future<bool> _performCheckIn(String registrationNumber, Lecture lecture, BuildContext currentContext) async {
    // Validate allowed characters (safety check)
    if (!allowedRegNumChars.hasMatch(registrationNumber)) {
       // Use the provided context to show the snackbar
       if (currentContext.mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
             SnackBar(content: Text('Invalid registration number format: $registrationNumber'), backgroundColor: Colors.red)
          );
       }
       return false;
    }

    try {
      final AttendanceRecord checkedInRecord = await apiService.checkInStudent(
        lecture.id,
        registrationNumber, // Pass validated registration number
      );
      // Use the passed context (could be dialog or dashboard)
      if (!currentContext.mounted) return false; // Check context before using
      ScaffoldMessenger.of(currentContext).showSnackBar(
         SnackBar(
            content: Text('Student ${checkedInRecord.studentName} (${checkedInRecord.registrationNumber}) checked in!'),
            backgroundColor: Colors.green
         )
      );
      return true; // Indicate success
    } catch (e) {
       if (!currentContext.mounted) return false; // Check context before using
       String errorMessage = 'Check-in failed: An unknown error occurred.';
       if (e is Exception) {
          // Try to get a cleaner message from the exception
          errorMessage = 'Check-in failed: ${e.toString().replaceFirst("Exception: ", "")}';
       }
       ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red)
       );
       return false; // Indicate failure
    }
  }


  // --- Manual Check-In Dialog ---
  void showCheckInDialog(Lecture lecture) {
    final registrationNumberController = TextEditingController();
    bool isCheckingIn = false; // State specific to this dialog instance

    showDialog(
      context: context,
      barrierDismissible: false, // Don't dismiss easily during operation
      builder: (dialogContext) {
        return StatefulBuilder( // Use StatefulBuilder to update dialog state (for loading indicator)
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // Rounded corners
              title: Text('Manual Check-In: ${lecture.unitName}'),
              content: TextField(
                controller: registrationNumberController,
                decoration: InputDecoration( // Apply consistent decoration
                  labelText: 'Student Registration Number', // Updated label
                  hintText: 'e.g., SSTE/COM03/047/21', // Updated hint example
                  prefixIcon: Icon(Icons.badge_outlined, color: brandColor.withOpacity(0.7)), // Updated icon
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  enabledBorder: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(12),
                     borderSide: BorderSide(color: Colors.grey.shade400),
                  ),
                  focusedBorder: OutlineInputBorder(
                     borderRadius: BorderRadius.circular(12),
                     borderSide: BorderSide(color: brandColor, width: 1.5),
                  ),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                inputFormatters: [
                  UpperCaseTextFormatter(), // Ensure uppercase
                  FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9/-]')), // Allow only valid chars
                ],
                keyboardType: TextInputType.text, // Keep as text
                textCapitalization: TextCapitalization.characters, // Suggest uppercase (redundant with formatter but good UX)
                autofocus: true,
                // Submit on keyboard done action
                textInputAction: TextInputAction.done,
                onSubmitted: (_) async {
                   if (isCheckingIn) return; // Prevent submission while already processing
                   final registrationNumber = registrationNumberController.text.trim();
                   if (registrationNumber.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                         SnackBar(content: Text('Please enter a registration number.'), backgroundColor: Colors.red)
                      );
                      return;
                   }
                   setDialogState(() => isCheckingIn = true);
                   bool success = await _performCheckIn(registrationNumber, lecture, dialogContext);
                   if (success && dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                   } else if (dialogContext.mounted) {
                      setDialogState(() => isCheckingIn = false);
                   }
                },
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              actions: [
                TextButton(
                  // Disable cancel button while checking in
                  onPressed: isCheckingIn ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  // Disable button while checking in
                  onPressed: isCheckingIn ? null : () async {
                    final registrationNumber = registrationNumberController.text.trim();

                    if (registrationNumber.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(
                         SnackBar(content: Text('Please enter a registration number.'), backgroundColor: Colors.red)
                      );
                      return; // Keep dialog open
                    }
                    // Validation moved inside _performCheckIn, but basic empty check is good here

                    setDialogState(() => isCheckingIn = true); // Show loading indicator

                    // Call the refactored check-in logic, passing the dialog's context
                    bool success = await _performCheckIn(registrationNumber, lecture, dialogContext);

                    // Pop dialog ONLY on success
                    if (success && dialogContext.mounted) {
                       Navigator.of(dialogContext).pop();
                    } else if (dialogContext.mounted) {
                       // Reset loading state on failure if dialog is still mounted
                       setDialogState(() => isCheckingIn = false);
                    }
                  },
                  style: ElevatedButton.styleFrom( // Style primary action button
                     backgroundColor: brandColor,
                     foregroundColor: Colors.white,
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  child: isCheckingIn
                      ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Text('Check In'),
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
    if (!mounted || _isCheckingInViaQr) return; // Prevent if already scanning/checking in

    // Navigate to the scanner screen and wait for a result
    final String? scannedRegNum = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => const QrScannerScreen()),
    );

    if (!mounted) return; // Check again after await

    if (scannedRegNum != null && scannedRegNum.isNotEmpty) {
      print("Scanned Registration Number: $scannedRegNum"); // Debug log
      final String processedRegNum = scannedRegNum.trim().toUpperCase(); // Trim and uppercase

      // Show loading indicator on the dashboard
      setState(() { _isCheckingInViaQr = true; });

      // Perform check-in using the scanned number
      // Pass the main dashboard context for the snackbar
      await _performCheckIn(processedRegNum, lecture, context);

      // Hide loading indicator regardless of success/failure
      if (mounted) {
         setState(() { _isCheckingInViaQr = false; });
      }
    } else {
      // Optional: Show a message if scanning was cancelled or no data found
      // showSnackBar('QR code scanning cancelled or no data found.', isError: true);
      print("QR Scan cancelled or returned empty.");
    }
  }


  @override
  void dispose() {
    // No controllers defined directly in this state to dispose here.
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Lecturer Dashboard - ${widget.currentUser.name}', style: const TextStyle(fontSize: 18)),
        backgroundColor: brandColor, // Apply brand color
        foregroundColor: Colors.white, // Ensure text/icons are white
        elevation: 2.0, // Consistent elevation
        actions: [
          // --- Show loading indicator in AppBar if checking in via QR ---
          if (_isCheckingInViaQr)
             Padding(
               padding: const EdgeInsets.only(right: 15.0),
               child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
             ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Lectures',
            // Disable refresh while checking in via QR
            onPressed: _isCheckingInViaQr ? null : loadLectures,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            // Disable logout while checking in via QR
            onPressed: _isCheckingInViaQr ? null : () async {
              // Confirm logout action
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
              // If confirmed and widget is mounted, perform logout and navigate
              if (confirm == true && mounted) {
                await authService.logout();
                // Use pushAndRemoveUntil to clear navigation stack
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
          // Button to create a new lecture
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create New Lecture'),
              // Disable create button while checking in via QR
              onPressed: _isCheckingInViaQr ? null : showCreateLectureDialog,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52), // Full width, standard height
                backgroundColor: brandColor, // Use brand color
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), // Standard radius
                textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const Divider(thickness: 0.5, height: 1, indent: 16, endIndent: 16),
          // Title for the lectures list
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            child: Text(
              "Your Created Lectures",
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: brandColor), // Use brand color
              textAlign: TextAlign.center,
            ),
          ),
          // List of lectures
          Expanded(
            child: RefreshIndicator(
              color: brandColor, // Set refresh indicator color
              onRefresh: () async => loadLectures(), // Pull-to-refresh action
              child: FutureBuilder<List<Lecture>>(
                future: lecturesFuture, // Use the future defined in state
                builder: (context, snapshot) {
                  // Loading state
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: brandColor));
                  }
                  // Error state
                  if (snapshot.hasError) {
                    print("Error fetching lectures Future: ${snapshot.error}");
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
                            const SizedBox(height: 10),
                            Text(
                              'Error loading lectures.\nPlease check connection.', // Simplified error
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey.shade700),
                            ),
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
                  // Empty state
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return LayoutBuilder( // Use LayoutBuilder to allow SingleChildScrollView to fill height
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(), // Ensure refresh works even when empty
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight),
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
                  // Sort lectures, newest first based on lecture date and then start time
                  lectures.sort((a, b) {
                    // *** Corrected Sorting Logic for Nullable DateTimes ***
                    final aDate = a.lectureDate;
                    final bDate = b.lectureDate;

                    // Handle null dates (treat null as later/older for descending sort)
                    if (aDate == null && bDate == null) {
                      // Dates are both null, compare by start time
                    } else if (aDate == null) {
                      return 1; // a (null) comes after b (non-null)
                    } else if (bDate == null) {
                      return -1; // b (null) comes after a (non-null)
                    } else {
                      // Both dates are non-null, compare them descending
                      int dateComp = bDate.compareTo(aDate);
                      if (dateComp != 0) return dateComp;
                      // Dates are the same, proceed to compare by start time
                    }

                    // Compare start times (descending, nulls last)
                    final aTime = a.startTime;
                    final bTime = b.startTime;
                    if (aTime == null && bTime == null) {
                      return 0; // Both times null, equal
                    } else if (aTime == null) {
                      return 1; // a (null) comes after b (non-null)
                    } else if (bTime == null) {
                      return -1; // b (null) comes after a (non-null)
                    } else {
                      // Both times non-null, compare descending
                      return bTime.compareTo(aTime);
                    }
                  });

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(), // Ensure scroll physics for RefreshIndicator
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    itemCount: lectures.length,
                    itemBuilder: (context, index) {
                      final lecture = lectures[index];
                      // Format subtitle text using the model's getters
                      final subtitleText = '${lecture.course ?? 'N/A'}\n' // Handle potential null course
                                           '${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}\n'
                                           'Venue: ${lecture.venue}';

                      // Build card for each lecture
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: InkWell( // Make the whole card tappable to view attendance
                          borderRadius: BorderRadius.circular(10),
                          onTap: () {
                             Navigator.push(
                               context,
                               MaterialPageRoute(
                                 // Navigate to the attendance screen for this lecture
                                 builder: (context) => LectureAttendanceScreen(lecture: lecture),
                               ),
                             );
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                            child: Row(
                              children: [
                                // Leading icon
                                CircleAvatar(
                                  backgroundColor: brandColor.withOpacity(0.1),
                                  child: Icon(Icons.school_outlined, size: 22, color: brandColor),
                                ),
                                const SizedBox(width: 16),
                                // Lecture details (title, subtitle)
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${lecture.unitName} (${lecture.unitCode})',
                                        style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        subtitleText,
                                        style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // --- Action Buttons Column ---
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Check-in button - triggers the modified dialog
                                    ElevatedButton.icon(
                                      icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                                      label: const Text('Check-In'),
                                      // Disable manual check-in while QR check-in is processing
                                      onPressed: _isCheckingInViaQr ? null : () => showCheckInDialog(lecture),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: brandColor.withOpacity(0.15), // Lighter background
                                        foregroundColor: brandColor, // Brand color text
                                        elevation: 0, // No elevation
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // Pill shape
                                      ),
                                    ),
                                    const SizedBox(height: 4), // Space between buttons
                                    // --- QR Scan Button ---
                                    IconButton(
                                      icon: const Icon(Icons.qr_code_scanner),
                                      tooltip: 'Scan QR Code',
                                      color: brandColor.withOpacity(0.8),
                                      iconSize: 26,
                                      // Disable scan button while QR check-in is processing
                                      onPressed: _isCheckingInViaQr ? null : () => _scanQrCodeAndCheckIn(lecture),
                                    ),
                                  ],
                                ),
                                // --- End Action Buttons Column ---
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
