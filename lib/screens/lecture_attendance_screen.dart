// lib/screens/lecture_attendance_screen.dart
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/services/api_service.dart'; // Import ApiService
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:flutter/foundation.dart'; // Import for kDebugMode

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
      // Fetch attendance records for the specific lecture ID
      _attendanceFuture = _apiService.getLectureAttendance(widget.lecture.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Construct subtitle safely, handling potential nulls from lecture model
    final appBarSubtitle = '${widget.lecture.formattedDate} | ${widget.lecture.formattedStartTime} - ${widget.lecture.formattedEndTime} | ${widget.lecture.venue}';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lecture.unitName, style: const TextStyle(fontSize: 18)),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        elevation: 2.0,
        bottom: PreferredSize(
           preferredSize: const Size.fromHeight(25.0),
           child: Padding(
             padding: const EdgeInsets.only(bottom: 8.0, left: 16.0, right: 16.0),
             child: Text(
               appBarSubtitle,
               style: TextStyle(
                 color: Colors.white.withOpacity(0.9),
                 fontSize: 13,
               ),
               textAlign: TextAlign.center,
               overflow: TextOverflow.ellipsis,
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
        color: brandColor,
        onRefresh: () async => _loadAttendance(),
        child: FutureBuilder<List<AttendanceRecord>>(
          future: _attendanceFuture,
          builder: (context, snapshot) {
            // Handle Loading
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: brandColor));
            }
            // Handle Error
            if (snapshot.hasError) {
               print("Error loading attendance: ${snapshot.error}");
               print("Error details: ${snapshot.error.runtimeType} ${snapshot.stackTrace}"); // More detailed error logging
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                     mainAxisAlignment: MainAxisAlignment.center,
                     children: [
                       Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
                       const SizedBox(height: 10),
                       Text('Error loading attendance list.\nPlease check your connection and pull down to retry.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
                       // Optionally show more error details in debug mode
                       // *** Added check for kDebugMode ***
                       if (kDebugMode) Text('\n${snapshot.error}', style: TextStyle(fontSize: 10, color: Colors.grey)),
                     ],
                  )
                )
              );
            }
            // Handle No Data
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return LayoutBuilder(builder: (context, constraints) {
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
               // Use the correct boolean field 'checkedIn'
               final bool aCheckedIn = a.checkedIn;
               final bool bCheckedIn = b.checkedIn;

               if (aCheckedIn && bCheckedIn) {
                 // Sort checked-in by time (earliest first)
                 // Use the correct field 'checkInTime' and handle potential nulls defensively
                 final aTime = a.checkInTime;
                 final bTime = b.checkInTime;
                 if (aTime != null && bTime != null) {
                    return aTime.compareTo(bTime);
                 } else if (aTime != null) {
                    return -1; // Treat null time as later
                 } else if (bTime != null) {
                    return 1; // Treat null time as later
                 } else {
                    return 0; // Both null, treat as equal for time sorting
                 }
               } else if (aCheckedIn) { return -1; } // Checked-in comes before joined
               else if (bCheckedIn) { return 1; } // Joined comes after checked-in
               else {
                 // Sort joined students alphabetically by name
                 return a.studentName.toLowerCase().compareTo(b.studentName.toLowerCase());
               }
            });

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
              itemCount: attendanceList.length,
              separatorBuilder: (context, index) => const Divider(height: 0.5, thickness: 0.5, indent: 72, endIndent: 16),
              itemBuilder: (context, index) {
                final record = attendanceList[index];
                // Use the correct boolean field 'checkedIn'
                final bool isCheckedIn = record.checkedIn;
                final String statusText;
                final Color statusColor;
                final IconData statusIcon;
                final String timeString;

                if (isCheckedIn) {
                  // Use the correct field 'checkInTime'
                  // Format time like '5:08 PM', handle potential null checkInTime
                  timeString = record.checkInTime != null
                      ? DateFormat.jm().format(record.checkInTime!.toDate().toLocal())
                      : 'N/A'; // Fallback if time is null despite checkedIn=true
                  statusText = 'Checked In @ $timeString';
                  statusColor = Colors.green.shade700;
                  statusIcon = Icons.check_circle;
                } else {
                  // Format joined time
                  timeString = DateFormat.jm().format(record.joinedAt.toDate().toLocal());
                  statusText = 'Joined @ $timeString';
                  statusColor = Colors.orange.shade800;
                  statusIcon = Icons.hourglass_top_rounded;
                }

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withOpacity(0.12),
                    foregroundColor: statusColor,
                    child: Text(
                      (index + 1).toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  title: Text(record.studentName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
                  // *** Corrected Subtitle: Removed studentCourse ***
                  subtitle: Text(
                    'Reg #: ${record.registrationNumber}', // Only show registration number
                    style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                  ),
                  trailing: Chip(
                    avatar: Icon(statusIcon, color: statusColor, size: 16),
                    label: Text(
                      statusText,
                      style: TextStyle(fontSize: 11.5, color: statusColor, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                    backgroundColor: statusColor.withOpacity(0.1),
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    visualDensity: VisualDensity.compact,
                  ),
                  dense: true,
                );
              },
            );
          },
        ),
      ),
    );
  }
}
