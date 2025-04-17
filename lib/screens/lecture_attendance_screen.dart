// lib/screens/lecture_attendance_screen.dart
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
// import 'package:checkmate/services/lecture_service.dart'; // Remove
import 'package:checkmate/services/api_service.dart'; // Import
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

// Convert to StatefulWidget for refresh functionality
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

  @override
  void initState() {
    super.initState();
    // Initial load
    _loadAttendance();
  }

  // Helper to load/reload attendance
  void _loadAttendance() {
    setState(() {
      _attendanceFuture = _apiService.getLectureAttendance(widget.lecture.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    final appBarSubtitle = '${widget.lecture.formattedDate} | ${widget.lecture.formattedStartTime} - ${widget.lecture.formattedEndTime} | ${widget.lecture.venue}';

    return Scaffold(
      appBar: AppBar(
        title: Text('Attendance: ${widget.lecture.unitName}'),
        bottom: PreferredSize(
           preferredSize: const Size.fromHeight(25.0),
           child: Padding(
             padding: const EdgeInsets.only(bottom: 8.0),
             child: Text(
               appBarSubtitle,
               style: TextStyle(
                 color: Theme.of(context).appBarTheme.foregroundColor?.withOpacity(0.85) ?? Colors.white.withOpacity(0.85),
                 fontSize: 13,
               ),
               textAlign: TextAlign.center,
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
        elevation: 1,
      ),
      // *** Use FutureBuilder ***
      body: RefreshIndicator( // Add pull-to-refresh
        onRefresh: () async => _loadAttendance(),
        child: FutureBuilder<List<AttendanceRecord>>(
          future: _attendanceFuture, // Use state variable
          builder: (context, snapshot) {
            // Handle Loading
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            // Handle Error
            if (snapshot.hasError) {
               print("Error loading attendance: ${snapshot.error}");
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text('Error loading attendance: ${snapshot.error}\nPull down to retry.', textAlign: TextAlign.center),
                )
              );
            }
            // Handle No Data
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Text(
                    'No students have joined or been checked in yet.\nPull down to refresh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ),
              );
            }

            // Handle Success (Data Available)
            final attendanceList = snapshot.data!;
            // Sorting logic remains the same
            attendanceList.sort((a, b) {
               if (a.checkedInAt != null && b.checkedInAt != null) {
                 return a.checkedInAt!.compareTo(b.checkedInAt!);
               } else if (a.checkedInAt != null) { return -1; }
               else if (b.checkedInAt != null) { return 1; }
               else { return a.studentName.compareTo(b.studentName); }
            });

            return ListView.separated(
              // Add physics for RefreshIndicator
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8.0),
              itemCount: attendanceList.length,
              separatorBuilder: (context, index) => const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final record = attendanceList[index];
                final bool isCheckedIn = record.checkedInAt != null;
                final String statusText;
                final Color statusColor;
                final IconData statusIcon;

                if (isCheckedIn) {
                  statusText = 'Checked In @ ${DateFormat.jm().format(record.checkedInAt!.toDate())}';
                  statusColor = Colors.green;
                  statusIcon = Icons.check_circle;
                } else {
                  statusText = 'Joined @ ${DateFormat.jm().format(record.joinedAt.toDate())} (Not Checked In)';
                  statusColor = Colors.orange;
                  statusIcon = Icons.hourglass_top_rounded;
                }

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withOpacity(0.15),
                    foregroundColor: statusColor,
                    child: Text((index + 1).toString()),
                  ),
                  title: Text(record.studentName, style: TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text('Visit #: ${record.visitNumber} | Course: ${record.studentCourse}'),
                  trailing: Chip(
                    avatar: Icon(statusIcon, color: statusColor, size: 18),
                    label: Text(statusText, style: TextStyle(fontSize: 12)),
                    backgroundColor: statusColor.withOpacity(0.1),
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    visualDensity: VisualDensity.compact,
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
