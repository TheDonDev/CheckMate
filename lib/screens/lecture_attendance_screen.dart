// lib/screens/lecture_attendance_screen.dart
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/services/api_service.dart'; // Import ApiService
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting

class LectureAttendanceScreen extends StatefulWidget {
  final Lecture lecture;

  const LectureAttendanceScreen({super.key, required this.lecture});

  @override
  State<LectureAttendanceScreen> createState() => _LectureAttendanceScreenState();
}

class _LectureAttendanceScreenState extends State<LectureAttendanceScreen> {
  // Instantiate ApiService
  final ApiService _apiService = ApiService();
  // State variable for the Future
  Future<List<AttendanceRecord>>? _attendanceFuture;

  // Define brand color locally or import from a constants file
  static const Color brandColor = Color(0xFF0175C2);

  @override
  void initState() {
    super.initState();
    // Initial load
    _loadAttendance();
  }

  // Helper to load/reload attendance
  void _loadAttendance() {
    if (!mounted) return; // Check if widget is still in the tree
    setState(() {
      _attendanceFuture = _apiService.getLectureAttendance(widget.lecture.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appBarSubtitle = '${widget.lecture.formattedDate} | ${widget.lecture.formattedStartTime} - ${widget.lecture.formattedEndTime} | ${widget.lecture.venue}';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lecture.unitName, style: const TextStyle(fontSize: 18)), // Slightly smaller title
        backgroundColor: brandColor, // Apply brand color
        foregroundColor: Colors.white, // Ensure text/icons are white
        elevation: 2.0, // Consistent elevation
        bottom: PreferredSize(
           preferredSize: const Size.fromHeight(25.0),
           child: Padding(
             padding: const EdgeInsets.only(bottom: 8.0, left: 16.0, right: 16.0), // Add horizontal padding
             child: Text(
               appBarSubtitle,
               style: TextStyle(
                 color: Colors.white.withOpacity(0.9), // Slightly brighter subtitle
                 fontSize: 13,
               ),
               textAlign: TextAlign.center,
               overflow: TextOverflow.ellipsis, // Prevent overflow
             ),
           ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Attendance',
            onPressed: _loadAttendance, // Call refresh method
          ),
        ],
      ),
      body: RefreshIndicator( // Add pull-to-refresh
        color: brandColor, // Set refresh indicator color
        onRefresh: () async => _loadAttendance(),
        child: FutureBuilder<List<AttendanceRecord>>(
          future: _attendanceFuture, // Use state variable
          builder: (context, snapshot) {
            // Handle Loading
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: brandColor)); // Use brand color
            }
            // Handle Error
            if (snapshot.hasError) {
               print("Error loading attendance: ${snapshot.error}");
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column( // Use Column for icon + text
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
                       const SizedBox(height: 10),
                       Text('Error loading attendance: ${snapshot.error}\nPull down to retry.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
                     ],
                  )
                )
              );
            }
            // Handle No Data
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              // Use LayoutBuilder and SingleChildScrollView for consistent pull-to-refresh behavior
              return LayoutBuilder(builder: (context, constraints) {
                 return SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: ConstrainedBox(
                       constraints: BoxConstraints(minHeight: constraints.maxHeight),
                       child: Center(
                         child: Padding(
                           padding: const EdgeInsets.all(20.0),
                           child: Column( // Use Column for icon + text
                             mainAxisAlignment: MainAxisAlignment.center,
                             children: [
                               Icon(Icons.people_outline, size: 50, color: Colors.grey.shade400),
                               const SizedBox(height: 10),
                               Text(
                                 'No students have joined or been checked in yet.\nPull down to refresh.',
                                 textAlign: TextAlign.center,
                                 style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                               ),
                             ],
                           ),
                         ),
                       ),
                    ),
                 );
              });
            }

            // --- Success: Display Attendance List ---
            final attendanceList = snapshot.data!;
            // Sort: Checked-in students first (by check-in time), then joined students (by name)
            attendanceList.sort((a, b) {
               final aCheckedIn = a.checkedInAt != null;
               final bCheckedIn = b.checkedInAt != null;
               if (aCheckedIn && bCheckedIn) {
                 // Sort checked-in by time (earliest first)
                 return a.checkedInAt!.compareTo(b.checkedInAt!);
               } else if (aCheckedIn) { return -1; } // Checked-in comes before joined
               else if (bCheckedIn) { return 1; } // Joined comes after checked-in
               else {
                 // Sort joined students alphabetically by name
                 return a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase());
               }
            });

            return ListView.separated(
              // Add physics for RefreshIndicator
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0), // Remove horizontal padding for full width divider
              itemCount: attendanceList.length,
              separatorBuilder: (context, index) => const Divider(height: 0.5, thickness: 0.5, indent: 72, endIndent: 16), // Indent divider past avatar
              itemBuilder: (context, index) {
                final record = attendanceList[index];
                final bool isCheckedIn = record.checkedInAt != null;
                final String statusText;
                final Color statusColor;
                final IconData statusIcon;
                final String timeString;

                if (isCheckedIn) {
                  // Format time like '5:08 PM'
                  timeString = DateFormat.jm().format(record.checkedInAt!.toDate().toLocal());
                  statusText = 'Checked In @ $timeString';
                  statusColor = Colors.green.shade700; // Darker green for checked in
                  statusIcon = Icons.check_circle;
                } else {
                  // Format time like '5:08 PM'
                  timeString = DateFormat.jm().format(record.joinedAt.toDate().toLocal());
                  statusText = 'Joined @ $timeString'; // Simplified status for joined
                  statusColor = Colors.orange.shade800; // Darker orange for joined but not checked in
                  statusIcon = Icons.hourglass_top_rounded; // Icon indicating waiting/pending check-in
                }

                return ListTile(
                  // Use index + 1 for numbering in the leading avatar
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withOpacity(0.12), // Subtle background based on status
                    foregroundColor: statusColor, // Icon/Text color based on status
                    child: Text(
                      (index + 1).toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  // Display Student Name and Registration Number clearly
                  title: Text(record.studentName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
                  // *** Updated Subtitle to show Registration Number ***
                  subtitle: Text(
                    'Reg #: ${record.registrationNumber} | Course: ${record.studentCourse}',
                    style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                  ),
                  // Use a Chip for status, making it more visually distinct
                  trailing: Chip(
                    avatar: Icon(statusIcon, color: statusColor, size: 16),
                    label: Text(
                      statusText,
                      style: TextStyle(fontSize: 11.5, color: statusColor, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis, // Prevent overflow on small screens
                    ),
                    backgroundColor: statusColor.withOpacity(0.1), // Subtle background
                    side: BorderSide.none, // Remove border
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    visualDensity: VisualDensity.compact, // Make chip smaller
                  ),
                  dense: true, // Make list tile slightly more compact
                );
              },
            );
          },
        ),
      ),
    );
  }
}
