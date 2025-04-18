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

class LecturerDashboard extends StatefulWidget {
  final app_user.User currentUser;
  const LecturerDashboard({super.key, required this.currentUser});

  @override
  State<LecturerDashboard> createState() => _LecturerDashboardState();
}

class _LecturerDashboardState extends State<LecturerDashboard> {
  final ApiService apiService = ApiService();
  late Future<List<Lecture>> lecturesFuture;

  // Define the brand color (consistent styling)
  static const Color brandColor = Color(0xFF0175C2);

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

  // Helper to show snackbar messages
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

  // --- Modified: Check-In Dialog uses Registration Number ---
  void showCheckInDialog(Lecture lecture) {
    final registrationNumberController = TextEditingController(); // Changed controller name
    bool isCheckingIn = false;

    showDialog(
      context: context,
      barrierDismissible: false, // Don't dismiss easily during operation
      builder: (dialogContext) {
        return StatefulBuilder( // Use StatefulBuilder to update dialog state (for loading indicator)
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // Rounded corners
              title: Text('Check-In: ${lecture.unitName}'),
              content: TextField(
                controller: registrationNumberController, // Use new controller
                decoration: InputDecoration( // Apply consistent decoration
                  labelText: 'Student Registration Number', // Updated label
                  hintText: 'e.g., SCT211-00XX/YYYY', // Updated hint
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
                keyboardType: TextInputType.text, // Allow text and symbols
                textCapitalization: TextCapitalization.characters, // Suggest uppercase
                autofocus: true,
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
                    final registrationNumber = registrationNumberController.text.trim().toUpperCase(); // Get reg number, trim, maybe uppercase
                    if (registrationNumber.isEmpty) {
                      // Show error using the main scaffold's snackbar
                      showSnackBar('Please enter a registration number.', isError: true);
                      return; // Keep dialog open
                    }
                    setDialogState(() => isCheckingIn = true); // Show loading indicator
                    try {
                      // Call API with registration number
                      final AttendanceRecord checkedInRecord = await apiService.checkInStudent(
                        lecture.id,
                        registrationNumber, // Pass registration number
                        widget.currentUser.id, // Pass lecturer ID
                      );
                      // Check if dialog context is still mounted before interacting with it
                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop(); // Close dialog on success
                      // Updated success message including student name and reg number
                      showSnackBar('Student ${checkedInRecord.studentName} (${checkedInRecord.registrationNumber}) checked in successfully!', isError: false);
                    } catch (e) {
                       // Check if dialog context is still mounted before showing snackbar
                       if (!dialogContext.mounted) return;
                       // Don't pop the dialog on error, show error message
                       showSnackBar('Check-in failed: ${e.toString()}', isError: true);
                    } finally {
                       // Ensure loading state is reset if dialog is still mounted
                       if (dialogContext.mounted) {
                          setDialogState(() => isCheckingIn = false);
                       }
                    }
                  },
                  style: ElevatedButton.styleFrom( // Style primary action button
                     backgroundColor: brandColor,
                     foregroundColor: Colors.white,
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  ),
                  // Show progress indicator or text based on isCheckingIn state
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

  @override
  void dispose() {
    // Dispose controllers if any were defined directly in this state
    // In this case, controllers are created within showCheckInDialog and should be disposed there if needed,
    // but they are local to the dialog build context.
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
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Lectures',
            onPressed: loadLectures, // Refresh action
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
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
      body: Column(
        children: [
          // Button to create a new lecture
          Padding(
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create New Lecture'),
              onPressed: showCreateLectureDialog, // Trigger the dialog
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
                              'Error loading lectures: ${snapshot.error}',
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
                     int dateComp = b.lectureDate.compareTo(a.lectureDate);
                     if (dateComp != 0) return dateComp;
                     return b.startTime.compareTo(a.startTime); // Sort by start time if dates are same
                  });

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(), // Ensure scroll physics for RefreshIndicator
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
                    itemCount: lectures.length,
                    itemBuilder: (context, index) {
                      final lecture = lectures[index];
                      // Format subtitle text
                      final subtitleText = '${lecture.course}\n'
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
                                // Check-in button - triggers the modified dialog
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                                  label: const Text('Check-In'),
                                  onPressed: () => showCheckInDialog(lecture), // Trigger check-in dialog
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: brandColor.withOpacity(0.15), // Lighter background
                                    foregroundColor: brandColor, // Brand color text
                                    elevation: 0, // No elevation
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), // Pill shape
                                  ),
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
