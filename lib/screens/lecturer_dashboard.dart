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
    if (!allowedRegNumChars.hasMatch(registrationNumber)) {
       if (currentContext.mounted) {
          ScaffoldMessenger.of(currentContext).showSnackBar(
             SnackBar(content: Text('Invalid registration number format: $registrationNumber'), backgroundColor: Colors.red)
          );
       }
       return false;
    }
    try {
      // *** Ensure checkInStudent exists and has correct signature in ApiService ***
      final AttendanceRecord checkedInRecord = await apiService.checkInStudent(
        lecture.id,
        registrationNumber,
      );
      if (!currentContext.mounted) return false;
      ScaffoldMessenger.of(currentContext).showSnackBar(
         SnackBar(content: Text('Student ${checkedInRecord.studentName} (${checkedInRecord.registrationNumber}) checked in!'), backgroundColor: Colors.green)
      );
      return true;
    } catch (e) {
       if (!currentContext.mounted) return false;
       String errorMessage = 'Check-in failed: ${e.toString().replaceFirst("Exception: ", "")}';
       ScaffoldMessenger.of(currentContext).showSnackBar(
          SnackBar(content: Text(errorMessage), backgroundColor: Colors.red)
       );
       return false;
    }
  }


  // --- Manual Check-In Dialog ---
  void showCheckInDialog(Lecture lecture) {
    // Prevent opening if another operation is in progress
    if (_isCheckingInViaQr || _isDeleting) return;

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
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: brandColor, width: 1.5)),
                  filled: true, fillColor: Colors.grey[50],
                ),
                inputFormatters: [ UpperCaseTextFormatter(), FilteringTextInputFormatter.allow(RegExp(r'[A-Z0-9/-]')), ],
                keyboardType: TextInputType.text, textCapitalization: TextCapitalization.characters, autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) async {
                   if (isCheckingIn) return;
                   final registrationNumber = registrationNumberController.text.trim();
                   if (registrationNumber.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Please enter a registration number.'), backgroundColor: Colors.red)); return;
                   }
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
                    if (registrationNumber.isEmpty) {
                      ScaffoldMessenger.of(dialogContext).showSnackBar(SnackBar(content: Text('Please enter a registration number.'), backgroundColor: Colors.red)); return;
                    }
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

  // --- Function to handle QR Code Scan Initiation ---
  Future<void> _scanQrCodeAndCheckIn(Lecture lecture) async {
    // Prevent opening if another operation is in progress
    if (!mounted || _isCheckingInViaQr || _isDeleting) return;

    final String? scannedRegNum = await Navigator.push<String>( context, MaterialPageRoute(builder: (context) => const QrScannerScreen()), );
    if (!mounted) return;

    if (scannedRegNum != null && scannedRegNum.isNotEmpty) {
      print("Scanned Registration Number: $scannedRegNum");
      final String processedRegNum = scannedRegNum.trim().toUpperCase();
      setState(() { _isCheckingInViaQr = true; });
      await _performCheckIn(processedRegNum, lecture, context);
      if (mounted) { setState(() { _isCheckingInViaQr = false; }); }
    } else {
      print("QR Scan cancelled or returned empty.");
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
                TextButton(
                  // Disable cancel while deleting
                  onPressed: isDialogDeleting ? null : () => Navigator.of(dialogContext).pop(false),
                  child: const Text('Cancel'),
                ),
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
                    // Set loading state for the main screen
                    setState(() { _isDeleting = true; _deletingLectureId = lecture.id; });

                    try {
                      // *** Ensure deleteLecture exists in ApiService ***
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
      loadLectures(); // Refresh the list
    }
  }
  // --- End Delete Confirmation Dialog ---


  @override
  void dispose() {
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
          // --- Show loading indicator in AppBar ---
          if (_isCheckingInViaQr || _isDeleting) // Show if either operation is in progress
             Padding(
               padding: const EdgeInsets.only(right: 15.0),
               child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))),
             ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Lectures',
            // Disable refresh while any operation is in progress
            onPressed: (_isCheckingInViaQr || _isDeleting) ? null : loadLectures,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            // Disable logout while any operation is in progress
            onPressed: (_isCheckingInViaQr || _isDeleting) ? null : () async {
              final confirm = await showDialog<bool>( context: context, builder: (context) => AlertDialog( shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), title: const Text('Confirm Logout'), content: const Text('Are you sure you want to log out?'), actions: [ TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')), TextButton( onPressed: () => Navigator.of(context).pop(true), style: TextButton.styleFrom(foregroundColor: Colors.red), child: const Text('Logout'), ), ], ), ) ?? false;
              if (confirm == true && mounted) { await authService.logout(); Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, ); }
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
              color: brandColor,
              onRefresh: () async => loadLectures(),
              child: FutureBuilder<List<Lecture>>(
                future: lecturesFuture,
                builder: (context, snapshot) {
                  // Loading state
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: brandColor));
                  }
                  // Error state
                  if (snapshot.hasError) {
                    print("Error fetching lectures Future: ${snapshot.error}");
                    return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.error_outline, color: Colors.red.shade400, size: 48), const SizedBox(height: 10),
                            Text( 'Error loading lectures.\nPlease check connection.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700), ),
                            const SizedBox(height: 15), ElevatedButton.icon( icon: const Icon(Icons.refresh), label: const Text('Retry'), onPressed: loadLectures, style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white), )
                          ], ), ) );
                  }
                  // Empty state
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return LayoutBuilder( builder: (context, constraints) { return SingleChildScrollView( physics: const AlwaysScrollableScrollPhysics(), child: ConstrainedBox( constraints: BoxConstraints(minHeight: constraints.maxHeight), child: Center( child: Padding( padding: const EdgeInsets.all(20.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
                                    Icon(Icons.event_note_outlined, size: 50, color: Colors.grey.shade400), const SizedBox(height: 10),
                                    Text( 'You have not created any lectures yet.\nTap "Create New Lecture" or pull down to refresh.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ),
                                  ], ), ), ), ), ); } );
                  }

                  // --- Success State: Display Lectures ---
                  final lectures = snapshot.data!;
                  // Sort lectures (logic remains the same)
                  lectures.sort((a, b) {
                     final aDate = a.lectureDate; final bDate = b.lectureDate;
                     if (aDate == null && bDate == null) {} else if (aDate == null) { return 1; } else if (bDate == null) { return -1; } else { int dateComp = bDate.compareTo(aDate); if (dateComp != 0) return dateComp; }
                     final aTime = a.startTime; final bTime = b.startTime;
                     if (aTime == null && bTime == null) { return 0; } else if (aTime == null) { return 1; } else if (bTime == null) { return -1; } else { return bTime.compareTo(aTime); }
                  });

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    itemCount: lectures.length,
                    itemBuilder: (context, index) {
                      final lecture = lectures[index];
                      final subtitleText = '${lecture.course ?? 'N/A'}\n${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}\nVenue: ${lecture.venue}';
                      // Check if this specific lecture is being deleted
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
                               Navigator.push( context, MaterialPageRoute( builder: (context) => LectureAttendanceScreen(lecture: lecture), ), );
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                              child: Row(
                                children: [
                                  // Leading icon
                                  CircleAvatar( backgroundColor: brandColor.withOpacity(0.1), child: Icon(Icons.school_outlined, size: 22, color: brandColor), ),
                                  const SizedBox(width: 16),
                                  // Lecture details
                                  Expanded( child: Column( crossAxisAlignment: CrossAxisAlignment.start, children: [
                                      Text( '${lecture.unitName} (${lecture.unitCode})', style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), ),
                                      const SizedBox(height: 4),
                                      Text( subtitleText, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3), ),
                                    ], ), ),
                                  const SizedBox(width: 8),

                                  // --- Action Buttons Column ---
                                  // Show loading indicator instead of buttons if deleting this lecture
                                  isThisLectureDeleting
                                    ? const SizedBox( width: 40, height: 40, child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: Colors.red)) )
                                    : Column( // Otherwise, show the buttons
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // Check-in button
                                          ElevatedButton.icon(
                                            icon: const Icon(Icons.person_add_alt_1_outlined, size: 18), label: const Text('Check-In'),
                                            // Disable if any operation is in progress
                                            onPressed: (_isCheckingInViaQr || _isDeleting) ? null : () => showCheckInDialog(lecture),
                                            style: ElevatedButton.styleFrom( backgroundColor: brandColor.withOpacity(0.15), foregroundColor: brandColor, elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), ),
                                          ),
                                          const SizedBox(height: 4),
                                          // Row for QR Scan and Delete buttons
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              // QR Scan Button
                                              IconButton(
                                                icon: const Icon(Icons.qr_code_scanner), tooltip: 'Scan Student QR Code', color: brandColor.withOpacity(0.8), iconSize: 26, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: BoxConstraints(),
                                                // Disable if any operation is in progress
                                                onPressed: (_isCheckingInViaQr || _isDeleting) ? null : () => _scanQrCodeAndCheckIn(lecture),
                                              ),
                                              const SizedBox(width: 4), // Space between icons
                                              // Delete Button
                                              IconButton(
                                                icon: const Icon(Icons.delete_outline), tooltip: 'Delete Lecture', color: Colors.red.withOpacity(0.7), iconSize: 26, visualDensity: VisualDensity.compact, padding: EdgeInsets.zero, constraints: BoxConstraints(),
                                                // Disable if any operation is in progress
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
