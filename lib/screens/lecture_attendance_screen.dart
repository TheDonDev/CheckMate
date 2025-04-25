// lib/screens/lecture_attendance_screen.dart
import 'dart:io';
import 'dart:typed_data'; // Needed for Uint8List
import 'dart:async'; // Needed for TimeoutException
import 'dart:ui' as ui;

import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/models/attendance_record.dart'; // Ensure this path is correct
import 'package:checkmate/services/api_service.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Needed for Timestamp comparison
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:qr_flutter/qr_flutter.dart';


class LectureAttendanceScreen extends StatefulWidget {
  final Lecture lecture;
  const LectureAttendanceScreen({super.key, required this.lecture});
  static const Color brandColor = Color(0xFF0175C2);

  @override
  State<LectureAttendanceScreen> createState() => _LectureAttendanceScreenState();
}

class _LectureAttendanceScreenState extends State<LectureAttendanceScreen> {
  final ApiService _apiService = ApiService();
  // Correctly typed Future
  Future<List<AttendanceRecord>>? _attendanceFuture;
  final GlobalKey _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  void _loadAttendance() {
    if (!mounted) return;
    if (kDebugMode) print("Fetching attendance (with percentages) for lecture ID: ${widget.lecture.id}");
    setState(() {
      // Call the API service method that fetches lecture attendance
      // This method should return List<AttendanceRecord> where each record
      // potentially includes the 'percentage' field from the backend.
      _attendanceFuture = _apiService.getLectureAttendance(widget.lecture.id);
    });
  }

  // --- _captureAndShareQrCode ---
  Future<void> _captureAndShareQrCode() async {
    try {
      if (_qrKey.currentContext == null) { throw Exception("QR Code context not found."); }
      RenderRepaintBoundary boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0); // Increased pixelRatio for better quality
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) { throw Exception("Could not get byte data from QR code image."); }
      Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      // Sanitize file names more robustly
      final safeUnitCode = widget.lecture.unitCode.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final safeUnitName = widget.lecture.unitName.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'QRCode_${safeUnitCode}_${safeUnitName}_$timestamp.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);
      if (kDebugMode) print('QR Code saved temporarily to: ${file.path}');

      final xFile = XFile(file.path);
      final result = await Share.shareXFiles(
        [xFile],
        text: 'QR Code for ${widget.lecture.unitName} (${widget.lecture.unitCode}) lecture check-in.',
        subject: 'Lecture Check-In QR Code: ${widget.lecture.unitCode}',
      );

      // Handle share result
      if (result.status == ShareResultStatus.success) {
        if (kDebugMode) print('QR Code shared/saved successfully.');
      } else if (result.status == ShareResultStatus.dismissed) {
        if (kDebugMode) print('Share sheet dismissed.');
      } else {
        if (kDebugMode) print('Sharing status: ${result.status}, Raw: ${result.raw}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not complete share action: ${result.status}'), backgroundColor: Colors.orange),
          );
        }
      }
    } catch (e) {
      if (kDebugMode) print("Error capturing or sharing QR code: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error preparing QR code: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- _showQrCodeDialog  ---
  void _showQrCodeDialog() {
    if (widget.lecture.id.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Error: Lecture ID is missing.'), backgroundColor: Colors.red),
       );
       return;
    }
    final screenWidth = MediaQuery.of(context).size.width;
    // Ensure dialog width is reasonable on different screen sizes
    final double dialogContentWidth = (screenWidth * 0.8).clamp(280.0, 400.0);
    final double qrSize = dialogContentWidth * 0.7; // Adjust QR size relative to dialog

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        bool isDialogProcessingShare = false;
        return StatefulBuilder( // Use StatefulBuilder to manage dialog state
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
              contentPadding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
              title: const Row(
                children: [
                  Icon(Icons.qr_code_2, color: LectureAttendanceScreen.brandColor, size: 26),
                  SizedBox(width: 10),
                  Expanded(child: Text('Check-In QR Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))),
                ],
              ),
              content: SizedBox(
                width: dialogContentWidth, // Constrain width
                child: SingleChildScrollView( // Allow content to scroll if needed
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${widget.lecture.unitName} (${widget.lecture.unitCode})',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                         '${widget.lecture.formattedDate} | ${widget.lecture.formattedStartTime} - ${widget.lecture.formattedEndTime}',
                         style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                         textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 4),
                      Text(
                         'Venue: ${widget.lecture.venue}',
                         style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                         textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      // Ensure QR code is captured correctly
                      RepaintBoundary(
                        key: _qrKey,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white, // Ensure background is white for QR capture
                            border: Border.all(color: Colors.grey.shade300, width: 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(8), // Padding around QR
                          child: QrImageView(
                            data: widget.lecture.id, // The data for the QR code
                            version: QrVersions.auto,
                            size: qrSize,
                            gapless: false, // Recommended for better scanning
                            backgroundColor: Colors.white, // Explicit white background
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Colors.black,
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Colors.black,
                            ),
                            errorStateBuilder: (cxt, err) {
                              if (kDebugMode) print("QR Generation Error: $err");
                              return Container(
                                width: qrSize, height: qrSize,
                                color: Colors.grey.shade200,
                                child: const Center(
                                  child: Padding(
                                    padding: EdgeInsets.all(8.0),
                                    child: Text(
                                      "Error generating QR code.",
                                      textAlign: TextAlign.center,
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                         'Students: Scan this code with the Checkmate app *after joining* to CHECK IN for this lecture.',
                         textAlign: TextAlign.center,
                         style: TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                    ],
                  ),
                ),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: <Widget>[
                ElevatedButton.icon(
                  icon: isDialogProcessingShare
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: LectureAttendanceScreen.brandColor))
                      : const Icon(Icons.share_outlined, size: 20),
                  label: Text(isDialogProcessingShare ? 'Processing...' : 'Share / Save'),
                  style: ElevatedButton.styleFrom(
                    foregroundColor: LectureAttendanceScreen.brandColor,
                    backgroundColor: LectureAttendanceScreen.brandColor.withOpacity(0.1),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  // Disable button while processing
                  onPressed: isDialogProcessingShare ? null : () async {
                     setDialogState(() { isDialogProcessingShare = true; }); // Update dialog state
                     try {
                       await _captureAndShareQrCode();
                       // Optionally close dialog after successful share, or keep it open
                       // if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                     } finally {
                       // Ensure state is reset even if share fails or dialog is closed prematurely
                       if (dialogContext.mounted) {
                         setDialogState(() { isDialogProcessingShare = false; });
                       }
                     }
                  },
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  // Disable button while processing share
                  onPressed: isDialogProcessingShare ? null : () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          }
        );
      },
    );
  }

  // --- _buildPercentageWidget ---
  // Helper widget to display the percentage with appropriate color and tooltip
  Widget _buildPercentageWidget(String? percentageString) {
    // Handle null, "N/A", or empty strings
    if (percentageString == null || percentageString == "N/A" || percentageString.isEmpty) {
      return Tooltip(
        message: 'Overall percentage unavailable',
        child: Icon(Icons.percent_outlined, color: Colors.grey.shade400, size: 16),
      );
    }

    double? percentageValue;
    try {
      percentageValue = double.parse(percentageString);
    } catch (e) {
      // Handle parsing errors (e.g., if backend sent something unexpected)
      if (kDebugMode) print("Warning: Could not parse percentage string '$percentageString': $e");
      return Tooltip(
        message: 'Invalid percentage data',
        child: Icon(Icons.error_outline, color: Colors.red.shade300, size: 16),
      );
    }

    // Handle invalid numeric values (though backend should ideally prevent this)
    if (percentageValue < 0 || percentageValue.isNaN || percentageValue.isInfinite) {
      if (kDebugMode) print("Warning: Invalid percentage value: $percentageValue");
      return Tooltip(
        message: 'Invalid percentage data',
        child: Icon(Icons.error_outline, color: Colors.red.shade300, size: 16),
      );
    }

    // Determine color based on percentage value
    final Color percColor = percentageValue >= 75 ? Colors.green.shade700 :
                             percentageValue >= 50 ? Colors.orange.shade800 :
                             Colors.red.shade700;

    // Display the percentage text
    return Text(
      '$percentageString%',
      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: percColor),
    );
  }
  // --- End Helper Widget ---

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Format subtitle safely
    final appBarSubtitle = '${widget.lecture.formattedDate} | ${widget.lecture.formattedStartTime} - ${widget.lecture.formattedEndTime} | ${widget.lecture.venue}';
    // Formatter for displaying timestamps in the list
    final dateTimeFormatter = DateFormat('MMM d, hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lecture.unitName, style: const TextStyle(fontSize: 18)),
        backgroundColor: LectureAttendanceScreen.brandColor,
        foregroundColor: Colors.white,
        elevation: 2.0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(25.0), // Adjust height as needed
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8.0, left: 16.0, right: 16.0),
            child: Text(
              appBarSubtitle,
              style: TextStyle(
                color: Colors.white.withOpacity(0.9),
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis, // Handle long subtitles
            ),
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Show Lecture Check-In QR Code',
            onPressed: _showQrCodeDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Attendance',
            onPressed: _loadAttendance, // Call the refresh method
          ),
        ],
      ),
      body: RefreshIndicator(
        color: LectureAttendanceScreen.brandColor,
        onRefresh: () async => _loadAttendance(), // Enable pull-to-refresh
        // Use FutureBuilder to handle the asynchronous loading of attendance data
        child: FutureBuilder<List<AttendanceRecord>>(
          future: _attendanceFuture, // The future fetching the data
          builder: (context, snapshot) { // *** START OF FutureBuilder builder ***
            // --- Loading State ---
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: LectureAttendanceScreen.brandColor));
            }

            // --- Error State ---
            if (snapshot.hasError) {
              // Log the error for debugging
              final error = snapshot.error;
              final stackTrace = snapshot.stackTrace;
              if (kDebugMode) {
                print("Error loading attendance: $error");
                print("Stack trace: $stackTrace");
              }
              // Display a user-friendly error message
              String displayMessage = 'Error loading attendance list.';
              if (error is ApiException) {
                displayMessage = error.message; // Use message from ApiException
              } else if (error is TimeoutException) {
                displayMessage = 'Request timed out. Please check your connection.';
              } else {
                // Generic message for other types of errors
                displayMessage = 'An unexpected error occurred.';
              }

              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
                      const SizedBox(height: 10),
                      Text(
                        '$displayMessage\nPlease pull down to retry.', // Added retry instruction
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade700)
                      ),
                      // Optionally show detailed error in debug mode
                      if (kDebugMode)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text('\nDetails: $error', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        ),
                    ],
                  )
                )
              );
            }
            // *** END UPDATED ERROR HANDLING BLOCK ***

            // --- Empty State ---
            // Handle cases where data is null or the list is empty
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              // Use LayoutBuilder and SingleChildScrollView to make the empty state refreshable
              return LayoutBuilder(builder: (context, constraints) {
                return SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(), // Ensure refresh works
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: constraints.maxHeight), // Fill height
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

            // --- Success State - Display List ---
            final attendanceList = snapshot.data!;

            // Sort the list: Checked-in first (by check-in time), then Joined (by joined time)
            attendanceList.sort((a, b) {
               final bool aCheckedIn = a.checkedIn;
               final bool bCheckedIn = b.checkedIn;

               if (aCheckedIn && bCheckedIn) {
                 // Both checked in: Sort by checkInTime (ascending, earliest first)
                 final Timestamp? aTime = a.checkInTime;
                 final Timestamp? bTime = b.checkInTime;
                 if (aTime != null && bTime != null) return aTime.compareTo(bTime);
                 if (aTime == null && bTime != null) return 1; // Nulls last
                 if (aTime != null && bTime == null) return -1; // Nulls last
                 return 0; // Both null (unlikely but handle)
               }
               else if (aCheckedIn && !bCheckedIn) {
                 return -1; // Checked in students come before joined students
               } else if (!aCheckedIn && bCheckedIn) {
                 return 1; // Joined students come after checked in students
               }
               else { // Neither are checked in (both just joined)
                 // Sort by joinedAt (ascending, earliest first)
                 // joinedAt is non-nullable in the model
                 return a.joinedAt.compareTo(b.joinedAt);
               }
            });

            // Use ListView.separated for dividers
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(), // Ensure scrollable for refresh
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0), // Adjust padding
              itemCount: attendanceList.length,
              separatorBuilder: (context, index) => const Divider(
                height: 0.5, // Thinner divider
                thickness: 0.5,
                indent: 72, // Indent from the leading avatar
                endIndent: 16, // Padding on the right
              ),
              itemBuilder: (context, index) {
                final record = attendanceList[index];
                final bool isCheckedIn = record.checkedIn;
                final String statusText;
                final Color statusColor;
                final IconData statusIcon;
                String timeString = 'N/A'; // Default timeString

                // Determine status text, color, and icon based on check-in status
                if (isCheckedIn) {
                  final checkInTimestamp = record.checkInTime; // Nullable Timestamp?
                  if (checkInTimestamp != null) {
                    timeString = dateTimeFormatter.format(checkInTimestamp.toDate().toLocal());
                  }
                  statusText = 'Checked In @ $timeString';
                  statusColor = Colors.green.shade700;
                  statusIcon = Icons.check_circle;
                } else {
                  // joinedAt is non-nullable Timestamp
                  timeString = dateTimeFormatter.format(record.joinedAt.toDate().toLocal());
                  statusText = 'Joined @ $timeString';
                  statusColor = Colors.orange.shade800;
                  statusIcon = Icons.hourglass_top_rounded; // Icon for 'Joined'
                }

                // Build the ListTile for each attendance record
                return ListTile(
                  // Leading avatar with index number
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withOpacity(0.12),
                    foregroundColor: statusColor,
                    child: Text(
                      (index + 1).toString(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                  // Student Name
                  title: Text(
                    record.studentName, // Non-nullable
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)
                  ),
                  // Subtitle with Registration Number and Percentage
                  subtitle: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween, // Space between Reg# and %
                    children: [
                      Flexible( // Allow Reg# to shrink if needed
                        child: Text(
                          'Reg #: ${record.registrationNumber}', // Non-nullable
                          style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                          overflow: TextOverflow.ellipsis, // Prevent overflow
                        ),
                      ),
                      const SizedBox(width: 8), // Spacer
                      // Display the overall percentage using the helper widget
                      _buildPercentageWidget(record.percentage), // Pass the percentage string
                    ],
                  ),
                  // Trailing chip showing check-in/joined status and time
                  trailing: Chip(
                    avatar: Icon(statusIcon, color: statusColor, size: 16),
                    label: Text(
                      statusText,
                      style: TextStyle(fontSize: 11.5, color: statusColor, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis, // Prevent overflow
                    ),
                    backgroundColor: statusColor.withOpacity(0.1),
                    side: BorderSide.none,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    visualDensity: VisualDensity.compact, // Make chip smaller
                  ),
                  dense: true, // Make ListTile more compact
                );
              },
            );
          }, // *** END OF FutureBuilder builder ***
        ),
      ),
    );
  }
}
