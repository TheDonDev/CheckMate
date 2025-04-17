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

  void loadLectures() {
    if (!mounted) return;
    setState(() {
      lecturesFuture = apiService.getLecturesForLecturer(widget.currentUser.id);
    });
  }

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

  void showCreateLectureDialog() async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return CreateLectureDialog(currentUser: widget.currentUser);
      },
    );
    if (result == true && mounted) {
      loadLectures();
    }
  }

  void showCheckInDialog(Lecture lecture) {
    final visitNumberController = TextEditingController();
    bool isCheckingIn = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), // Rounded corners
              title: Text('Check-In: ${lecture.unitName}'),
              content: TextField( // Use standard TextField, styling comes from theme or InputDecoration
                controller: visitNumberController,
                decoration: InputDecoration( // Apply consistent decoration
                  labelText: 'Student Visit Number',
                  hintText: 'e.g., 123456',
                  prefixIcon: Icon(Icons.confirmation_number_outlined, color: brandColor.withOpacity(0.7)),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  filled: true,
                  fillColor: Colors.grey[100],
                ),
                keyboardType: TextInputType.number,
                autofocus: true,
              ),
              actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              actions: [
                TextButton(
                  onPressed: isCheckingIn ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isCheckingIn ? null : () async {
                    final visitNumber = visitNumberController.text.trim();
                    if (visitNumber.isEmpty) {
                      showSnackBar('Please enter a visit number.', isError: true);
                      return;
                    }
                    setDialogState(() => isCheckingIn = true);
                    try {
                      final AttendanceRecord checkedInRecord = await apiService.checkInStudent(
                        lecture.id, visitNumber, widget.currentUser.id,
                      );
                      if (!dialogContext.mounted) return;
                      Navigator.of(dialogContext).pop();
                      showSnackBar('Student ${checkedInRecord.studentName} checked in successfully!', isError: false);
                    } catch (e) {
                       if (!dialogContext.mounted) return;
                       showSnackBar('Check-in failed: ${e.toString()}', isError: true);
                    } finally {
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
            onPressed: loadLectures,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Logout',
            onPressed: () async {
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
            padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 12.0), // Adjust padding
            child: ElevatedButton.icon(
              icon: const Icon(Icons.add_circle_outline),
              label: const Text('Create New Lecture'),
              onPressed: showCreateLectureDialog,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 52), // Match standard button height/width
                backgroundColor: brandColor, // Use brand color
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)), // Match standard radius
                textStyle: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const Divider(thickness: 0.5, height: 1, indent: 16, endIndent: 16),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            child: Text(
              "Your Created Lectures",
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: brandColor), // Use brand color
              textAlign: TextAlign.center,
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: brandColor, // Set refresh indicator color
              onRefresh: () async => loadLectures(),
              child: FutureBuilder<List<Lecture>>(
                future: lecturesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return Center(child: CircularProgressIndicator(color: brandColor)); // Use brand color
                  }
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
                  if (!snapshot.hasData || snapshot.data!.isEmpty) {
                    return LayoutBuilder(
                      builder: (context, constraints) {
                        return SingleChildScrollView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          child: ConstrainedBox(
                            constraints: BoxConstraints(minHeight: constraints.maxHeight),
                            child: Center(
                              child: Padding(
                                padding: const EdgeInsets.all(20.0),
                                child: Column( // Use column for icon + text
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

                  // --- Success State ---
                  final lectures = snapshot.data!;
                  lectures.sort((a, b) => b.startTime.compareTo(a.startTime)); // Newest first

                  return ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0), // Adjusted padding
                    itemCount: lectures.length,
                    itemBuilder: (context, index) {
                      final lecture = lectures[index];
                      final subtitleText = '${lecture.course}\n'
                                           '${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}\n'
                                           'Venue: ${lecture.venue}';

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 6.0),
                        elevation: 1.5,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        child: InkWell( // Make the whole card tappable
                          borderRadius: BorderRadius.circular(10), // Match card shape
                          onTap: () {
                             Navigator.push(
                               context,
                               MaterialPageRoute(
                                 builder: (context) => LectureAttendanceScreen(lecture: lecture),
                               ),
                             );
                          },
                          child: Padding( // Add padding inside InkWell
                            padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 16.0),
                            child: Row( // Use Row for more control over layout
                              children: [
                                CircleAvatar(
                                  backgroundColor: brandColor.withOpacity(0.1),
                                  child: Icon(Icons.school_outlined, size: 22, color: brandColor),
                                ),
                                const SizedBox(width: 16),
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
                                // Check-in button as a separate element
                                ElevatedButton.icon(
                                  icon: const Icon(Icons.person_add_alt_1_outlined, size: 18),
                                  label: const Text('Check-In'),
                                  onPressed: () => showCheckInDialog(lecture),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: brandColor.withOpacity(0.15), // Lighter background for secondary action
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
