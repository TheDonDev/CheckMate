// lib/screens/lecturer_dashboard.dart
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/screens/lecture_attendance_screen.dart'; // Ensure this screen exists and is correct
import 'package:checkmate/services/auth_service.dart';
import 'package:checkmate/services/api_service.dart'; // Use ApiService
import 'package:checkmate/widgets/create_lecture_dialog.dart';
import 'package:flutter/material.dart';
import 'package:checkmate/models/app_user.dart' as app_user;
// import 'package:checkmate/screens/login_screen.dart'; // Not needed directly if using Wrapper
import 'package:checkmate/screens/welcome_screen.dart'; // Import WelcomeScreen for logout
// Intl package is implicitly used via lecture.formattedDate etc.
// import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class LecturerDashboard extends StatefulWidget {
  final app_user.User currentUser;
  const LecturerDashboard({super.key, required this.currentUser});

  @override
  State<LecturerDashboard> createState() => _LecturerDashboardState();
}

class _LecturerDashboardState extends State<LecturerDashboard> {
  final ApiService apiService = ApiService();
  // State variable to hold the Future for the list, initialized in initState
  late Future<List<Lecture>> lecturesFuture;

  @override
  void initState() {
    super.initState();
    // Initial load of lectures when the widget is first created
    loadLectures();
  }

  // Method to fetch lectures from the API and update the Future state
  // This triggers the FutureBuilder to rebuild
  void loadLectures() {
    // Ensure the widget is still mounted before calling setState
    if (!mounted) return;
    setState(() {
      lecturesFuture = apiService.getLecturesForLecturer(widget.currentUser.id);
    });
  }

  // Helper to show snackbar messages, checking if the widget is still mounted
  void showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.redAccent : Colors.green,
        duration: const Duration(seconds: 3), // Give user time to read
      ),
    );
  }

  // Shows the dialog to create a new lecture
  void showCreateLectureDialog() async {
    // Await the result from the dialog (true if created successfully)
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false, // Prevent closing by tapping outside
      builder: (BuildContext context) {
        // Pass the current user to the dialog
        return CreateLectureDialog(currentUser: widget.currentUser);
      },
    );

    // If the dialog returned true, reload the lectures list
    if (result == true && mounted) {
      loadLectures();
    }
  }

  // Shows the dialog to check-in a student using their visit number
  void showCheckInDialog(Lecture lecture) {
    final visitNumberController = TextEditingController();
    // Use a local variable for loading state within the dialog
    bool isCheckingIn = false;

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent accidental dismissal
      builder: (dialogContext) { // Use a different context name for clarity
        // Use StatefulBuilder to manage the dialog's internal state (isCheckingIn)
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Check-In for ${lecture.unitName}'),
              content: TextField(
                controller: visitNumberController,
                decoration: const InputDecoration(
                  labelText: 'Enter Student Visit Number',
                  hintText: 'e.g., 123456',
                  // No need for border: OutlineInputBorder() if using global theme
                ),
                keyboardType: TextInputType.number,
                autofocus: true, // Focus the field immediately
              ),
              actions: [
                TextButton(
                  // Disable cancel button while processing
                  onPressed: isCheckingIn ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  // Disable button while processing, show loading indicator
                  onPressed: isCheckingIn ? null : () async {
                    final visitNumber = visitNumberController.text.trim();
                    if (visitNumber.isEmpty) {
                      // Show snackbar within the dialog's context if possible, or main context
                      showSnackBar('Please enter a visit number.', isError: true);
                      return; // Don't proceed if empty
                    }

                    // Update dialog state to show loading
                    setDialogState(() => isCheckingIn = true);
                    try {
                      // Call ApiService to check in the student
                      final AttendanceRecord checkedInRecord = await apiService.checkInStudent(
                        lecture.id,
                        visitNumber,
                        widget.currentUser.id, // Pass the lecturer's ID
                      );

                      // Check if the dialog context is still valid before proceeding
                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop(); // Close the dialog
                      showSnackBar('Student ${checkedInRecord.studentName} checked in successfully!');
                      // Note: Attendance screen will refresh itself when opened/refreshed
                    } catch (e) {
                       // Check if the dialog context is still valid
                       if (!dialogContext.mounted) return;
                       // Show specific error from ApiService (ApiException) or generic error
                       showSnackBar('Check-in failed: ${e.toString()}', isError: true);
                    } finally {
                       // Ensure dialog context is valid before updating state
                       if (dialogContext.mounted) {
                          setDialogState(() => isCheckingIn = false); // Hide loading
                       }
                    }
                  },
                  // Show loading indicator or text based on state
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
    // Dispose any controllers if they were part of the state (like visitNumberController if it wasn't local to the dialog)
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Access AuthService using Provider for logout functionality
    final authService = Provider.of<AuthService>(context, listen: false);

    return Scaffold(
      appBar: AppBar(
        title: Text('Lecturer Dashboard - ${widget.currentUser.name}'),
        actions: [
          // Refresh button
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Lectures',
            onPressed: loadLectures, // Trigger lecture reload
          ),
          // Logout button
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
              // Show confirmation dialog before logging out
              final confirm = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Confirm Logout'),
                  content: const Text('Are you sure you want to log out?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false), // Return false on cancel
                      child: const Text('Cancel'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(true), // Return true on confirm
                      child: const Text('Logout'),
                    ),
                  ],
                ),
              ) ?? false; // Handle null case (dialog dismissed)

              // If confirmed, perform logout and navigate
              if (confirm == true) {
                await authService.logout();
                // Check if the widget is still mounted before navigating
                if (mounted) {
                  // Navigate to WelcomeScreen and remove all previous routes
                  Navigator.pushAndRemoveUntil(
                    context,
                    MaterialPageRoute(builder: (context) => const WelcomeScreen()),
                    (Route<dynamic> route) => false,
                  );
                }
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Button to create a new lecture
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create New Lecture'),
              onPressed: showCreateLectureDialog,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50), // Make button wide
              ),
            ),
          ),
          const Divider(thickness: 1, height: 1), // Thinner divider
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            child: Text(
              "Your Created Lectures",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
          ),
          // List of lectures using FutureBuilder and RefreshIndicator
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async => loadLectures(), // Pull-to-refresh action
              child: FutureBuilder<List<Lecture>>(
                future: lecturesFuture, // Provide the future from state
                builder: (context, snapshot) {
                  // --- Handle different states of the Future ---

                  // 1. Loading State
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  // 2. Error State
                  if (snapshot.hasError) {
                    print("Error fetching lectures Future: ${snapshot.error}");
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column( // Use column for better layout
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
                            const SizedBox(height: 10),
                            Text(
                              'Error loading lectures: ${snapshot.error}',
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                            const SizedBox(height: 10),
                            ElevatedButton.icon( // Add a retry button
                               icon: const Icon(Icons.refresh),
                               label: const Text('Retry'),
                               onPressed: loadLectures,
                            )
                          ],
                        ),
                      )
                    );
                  }

                  // 3. No Data State (Success, but empty list)
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return LayoutBuilder( // Use LayoutBuilder to ensure RefreshIndicator works
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight),
                            child: const Center(
                              child: Padding(
                                padding: EdgeInsets.all(20.0),
                                child: Text(
                                  'You have not created any lectures yet.\nTap "Create New Lecture" or pull down to refresh.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 16, color: Colors.grey),
                                ),
                              ),
                            ),
                          ),
                        );
                      }
                    );
                  }

                  // 4. Success State (Data Available)
                  final lectures = snapshot.data!;
                  // Sort lectures (e.g., newest first by start time)
                  lectures.sort((a, b) => b.startTime.compareTo(a.startTime));

                  return ListView.builder(
                    // Ensure physics allows scrolling for RefreshIndicator
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.only(bottom: 16.0, left: 8.0, right: 8.0), // Add horizontal padding
                    itemCount: lectures.length,
                    itemBuilder: (context, index) {
                      final lecture = lectures[index];
                      // Use formatting getters from Lecture model
                      final subtitleText = '${lecture.course}\n'
                                           '${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}\n'
                                           'Venue: ${lecture.venue}';

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6), // Adjust vertical margin
                        elevation: 2,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)), // Rounded corners for card
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: Theme.of(context).primaryColorLight,
                            child: Icon(Icons.school_outlined, size: 20, color: Theme.of(context).primaryColorDark),
                          ),
                          title: Text(
                            '${lecture.unitName} (${lecture.unitCode})',
                            style: const TextStyle(fontWeight: FontWeight.w500),
                          ),
                          subtitle: Text(subtitleText),
                          isThreeLine: true, // Ensure space for three lines
                          trailing: ElevatedButton.icon(
                            icon: const Icon(Icons.person_add_alt_1, size: 18),
                            label: const Text('Check-In'),
                            onPressed: () => showCheckInDialog(lecture),
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), // Smaller padding
                              textStyle: const TextStyle(fontSize: 13), // Smaller text
                            ),
                          ),
                          onTap: () {
                             // Navigate to the attendance screen for this lecture
                             Navigator.push(
                               context,
                               MaterialPageRoute(
                                 // Pass the lecture object to the attendance screen
                                 builder: (context) => LectureAttendanceScreen(lecture: lecture),
                               ),
                             );
                          },
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
