// lib/screens/lecture_attendance_screen.dart
import 'dart:io'; // For File operations
// For Uint8List
import 'dart:ui' as ui; // For Image rendering

import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/services/api_service.dart'; // Import ApiService
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'; // For RenderRepaintBoundary
import 'package:intl/intl.dart'; // For date formatting
import 'package:flutter/foundation.dart'; // Import for kDebugMode
import 'package:path_provider/path_provider.dart'; // For temporary directory
// import 'package:permission_handler/permission_handler.dart'; // Permission handler (optional but good practice)
import 'package:share_plus/share_plus.dart'; // For sharing

// --- Import QR Flutter ---
import 'package:qr_flutter/qr_flutter.dart'; // Import the QR code generator package

class LectureAttendanceScreen extends StatefulWidget {
  final Lecture lecture;

  const LectureAttendanceScreen({super.key, required this.lecture});

  // Define brand color statically within the Widget class
  static const Color brandColor = Color(0xFF0175C2);

  @override
  State<LectureAttendanceScreen> createState() => _LectureAttendanceScreenState();
}

class _LectureAttendanceScreenState extends State<LectureAttendanceScreen> {
  // Instantiate ApiService
  final ApiService _apiService = ApiService();
  // State variable for the Future
  Future<List<AttendanceRecord>>? _attendanceFuture;

  // GlobalKey to capture the QR code widget
  final GlobalKey _qrKey = GlobalKey();
  // Removed _isProcessingQrShare from here as it's managed locally in the dialog's StatefulBuilder

  @override
  void initState() {
    super.initState();
    // Initial load
    _loadAttendance();
  }

  // Helper to load/reload attendance
  void _loadAttendance() {
    if (!mounted) return; // Check if widget is still in the tree
    print("Fetching attendance for lecture ID: ${widget.lecture.id}"); // Debug log
    setState(() {
      // Fetch attendance records for the specific lecture ID using the correct method name
      _attendanceFuture = _apiService.getLectureAttendance(widget.lecture.id);
    });
  }

  // --- Function to Capture and Share/Save QR Code ---
  Future<void> _captureAndShareQrCode() async {
    // Loading state is managed by the dialog's StatefulBuilder

    try {
      // 1. Find the RenderRepaintBoundary
      if (_qrKey.currentContext == null) {
        throw Exception("QR Code context not found. Dialog might be closed.");
      }
      RenderRepaintBoundary boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;

      // 2. Convert to Image (increase pixelRatio for better quality)
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);

      // 3. Convert Image to ByteData (PNG format)
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) {
        throw Exception("Could not get byte data from QR code image.");
      }
      Uint8List pngBytes = byteData.buffer.asUint8List();

      // 4. Get Temporary Directory
      final tempDir = await getTemporaryDirectory();
      // Sanitize filename
      final safeUnitCode = widget.lecture.unitCode.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final safeUnitName = widget.lecture.unitName.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'QRCode_${safeUnitCode}_${safeUnitName}_$timestamp.png';
      final file = File('${tempDir.path}/$fileName');

      // 5. Write Bytes to Temporary File
      await file.writeAsBytes(pngBytes);
      print('QR Code saved temporarily to: ${file.path}'); // Debug log

      // 6. Share File using share_plus
      final xFile = XFile(file.path);
      final result = await Share.shareXFiles(
        [xFile],
        text: 'QR Code for ${widget.lecture.unitName} (${widget.lecture.unitCode}) lecture check-in.', // Updated text
        subject: 'Lecture Check-In QR Code: ${widget.lecture.unitCode}', // Updated subject
      );

      // Handle share result
      if (result.status == ShareResultStatus.success) {
        print('QR Code shared/saved successfully.');
      } else if (result.status == ShareResultStatus.dismissed) {
         print('Share sheet dismissed.');
      } else {
        print('Sharing status: ${result.status}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not complete action: ${result.status}'), backgroundColor: Colors.orange),
          );
        }
      }

    } catch (e) {
      print("Error capturing or sharing QR code: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error preparing QR code: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    }
    // Loading state reset is handled by the StatefulBuilder's finally block in the dialog.
  }
  // --- End Capture and Share Function ---


  // --- Function to Show QR Code Dialog (Updated Text) ---
  void _showQrCodeDialog() {
    // Ensure lecture ID is available
    if (widget.lecture.id.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar(
         const SnackBar(content: Text('Error: Lecture ID is missing.'), backgroundColor: Colors.red),
       );
       return;
    }

    // Calculate sizes *before* showing the dialog
    final screenWidth = MediaQuery.of(context).size.width;
    final double dialogContentWidth = screenWidth * 0.8 > 400 ? 400 : screenWidth * 0.8;
    final double qrSize = dialogContentWidth * 0.7;

    showDialog(
      context: context,
      // Use StatefulBuilder to manage the loading state of the share button
      builder: (BuildContext dialogContext) {
        // Local state variable for the dialog's share button loading state
        bool isDialogProcessingShare = false;

        return StatefulBuilder( // Add StatefulBuilder here
          builder: (context, setDialogState) { // Use context from StatefulBuilder
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
                width: dialogContentWidth,
                child: SingleChildScrollView(
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
                      // --- QR Code Widget wrapped in RepaintBoundary ---
                      RepaintBoundary( // Wrap the QR code container
                        key: _qrKey, // Assign the GlobalKey
                        child: Container(
                          decoration: BoxDecoration(
                             color: Colors.white, // Ensure white background for capture
                             border: Border.all(color: Colors.grey.shade300, width: 1),
                             borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: QrImageView(
                            // *** Data remains Lecture ID ***
                            data: widget.lecture.id,
                            version: QrVersions.auto,
                            size: qrSize,
                            gapless: false,
                            backgroundColor: Colors.white, // Explicit white background
                            eyeStyle: const QrEyeStyle(
                               eyeShape: QrEyeShape.square, color: Colors.black),
                            dataModuleStyle: const QrDataModuleStyle(
                               dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                            errorStateBuilder: (cxt, err) {
                              print("QR Generation Error: $err");
                              return Container(
                                width: qrSize, height: qrSize, color: Colors.grey.shade200,
                                child: const Center( child: Padding( padding: EdgeInsets.all(8.0), child: Text( "Error generating QR code.", textAlign: TextAlign.center, style: TextStyle(color: Colors.red), ), ), ),
                              );
                            },
                          ),
                        ),
                      ),
                      // --- End QR Code Widget ---
                      const SizedBox(height: 20),
                      // --- *** UPDATED INSTRUCTIONAL TEXT *** ---
                      const Text(
                        'Students: Scan this code with the Checkmate app *after joining* to CHECK IN for this lecture.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.black54),
                      ),
                      // --- *** END TEXT UPDATE *** ---
                    ],
                  ),
                ),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: <Widget>[
                // --- Download/Share Button ---
                ElevatedButton.icon(
                  icon: isDialogProcessingShare
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: LectureAttendanceScreen.brandColor))
                      : const Icon(Icons.download_outlined, size: 20),
                  label: Text(isDialogProcessingShare ? 'Processing...' : 'Download'),
                  style: ElevatedButton.styleFrom(
                     foregroundColor: LectureAttendanceScreen.brandColor,
                     backgroundColor: LectureAttendanceScreen.brandColor.withOpacity(0.1),
                     elevation: 0,
                     padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  onPressed: isDialogProcessingShare ? null : () async {
                     setDialogState(() { isDialogProcessingShare = true; });
                     try {
                        await _captureAndShareQrCode();
                     } finally {
                        if (context.mounted) { // Use the context from StatefulBuilder
                           setDialogState(() { isDialogProcessingShare = false; });
                        }
                     }
                  },
                ),
                // --- Close Button ---
                TextButton(
                  style: TextButton.styleFrom(
                     foregroundColor: Colors.grey.shade700,
                     padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10),
                     shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: isDialogProcessingShare ? null : () {
                    Navigator.of(dialogContext).pop();
                  },
                ),
              ],
            );
          } // End StatefulBuilder builder
        ); // End StatefulBuilder
      }, // End showDialog builder
    ); // End showDialog
  }
  // --- End QR Code Dialog Function ---


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appBarSubtitle = '${widget.lecture.formattedDate} | ${widget.lecture.formattedStartTime} - ${widget.lecture.formattedEndTime} | ${widget.lecture.venue}';

    // --- Date and Time Formatter ---
    // Example format: Aug 20, 09:30 AM
    // Adjust the pattern as needed (e.g., 'dd/MM/yy, HH:mm' for 20/08/24, 14:30)
    final dateTimeFormatter = DateFormat('MMM d, hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lecture.unitName, style: const TextStyle(fontSize: 18)),
        backgroundColor: LectureAttendanceScreen.brandColor,
        foregroundColor: Colors.white,
        elevation: 2.0,
        bottom: PreferredSize(
           preferredSize: const Size.fromHeight(25.0),
           child: Padding(
             padding: const EdgeInsets.only(bottom: 8.0, left: 16.0, right: 16.0),
             child: Text(
               appBarSubtitle,
               style: TextStyle( color: Colors.white.withOpacity(0.9), fontSize: 13, ),
               textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
             ),
           ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            // *** Updated tooltip ***
            tooltip: 'Show Lecture Check-In QR Code',
            onPressed: _showQrCodeDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Attendance',
            onPressed: _loadAttendance,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: LectureAttendanceScreen.brandColor,
        onRefresh: () async => _loadAttendance(),
        child: FutureBuilder<List<AttendanceRecord>>(
          future: _attendanceFuture,
          builder: (context, snapshot) {
            // Handle Loading
            if (snapshot.connectionState == ConnectionState.waiting) {
              return Center(child: CircularProgressIndicator(color: LectureAttendanceScreen.brandColor));
            }
            // Handle Error
            if (snapshot.hasError) {
               print("Error loading attendance: ${snapshot.error}");
               print("Error details: ${snapshot.error.runtimeType} ${snapshot.stackTrace}");
              return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
                       Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
                       const SizedBox(height: 10),
                       Text('Error loading attendance list.\nPlease check your connection and pull down to retry.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)),
                       if (kDebugMode) Text('\n${snapshot.error}', style: TextStyle(fontSize: 10, color: Colors.grey)),
                     ], ) ) );
            }
            // Handle No Data
            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return LayoutBuilder(builder: (context, constraints) {
                 return SingleChildScrollView( physics: const AlwaysScrollableScrollPhysics(), child: ConstrainedBox( constraints: BoxConstraints(minHeight: constraints.maxHeight), child: Center( child: Padding( padding: const EdgeInsets.all(20.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [
                               Icon(Icons.people_outline, size: 50, color: Colors.grey.shade400),
                               const SizedBox(height: 10),
                               Text( 'No students have joined or been checked in yet.\nPull down to refresh.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ),
                             ], ), ), ), ), ); });
            }

            // --- Success: Display Attendance List (Updated Time Formatting & Sorting) ---
            final attendanceList = snapshot.data!;
            // Sort: Checked In first (by time), then Joined (by time)
            attendanceList.sort((a, b) {
               // *** Use checkedIn instead of isCheckedIn ***
               final bool aCheckedIn = a.checkedIn;
               final bool bCheckedIn = b.checkedIn;

               // If both checked in, sort by checkInTime (earlier first, nulls last)
               if (aCheckedIn && bCheckedIn) {
                 final aTime = a.checkInTime; final bTime = b.checkInTime;
                 if (aTime != null && bTime != null) return aTime.compareTo(bTime);
                 if (aTime == null && bTime != null) return 1; // Nulls last
                 if (aTime != null && bTime == null) return -1; // Nulls last
                 return 0; // Both null (shouldn't happen if checkedIn is true)
               }
               // If only 'a' is checked in, it comes first
               else if (aCheckedIn && !bCheckedIn) { return -1; }
               // If only 'b' is checked in, it comes first
               else if (!aCheckedIn && bCheckedIn) { return 1; }
               // If both joined (but not checked in), sort by joinedAt (earlier first)
               else { // (!aCheckedIn && !bCheckedIn)
                 return a.joinedAt.compareTo(b.joinedAt);
               }
            });

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
              itemCount: attendanceList.length,
              separatorBuilder: (context, index) => const Divider(height: 0.5, thickness: 0.5, indent: 72, endIndent: 16),
              itemBuilder: (context, index) {
                final record = attendanceList[index];
                // *** Use checkedIn instead of isCheckedIn ***
                final bool isCheckedIn = record.checkedIn;
                final String statusText; final Color statusColor; final IconData statusIcon; final String timeString;

                if (isCheckedIn) {
                  // Use checkInTime if available, format with date and time
                  timeString = record.checkInTime != null
                      ? dateTimeFormatter.format(record.checkInTime!.toDate().toLocal()) // Format Date & Time
                      : 'N/A'; // Fallback if checkInTime is null despite checkedIn=true (data inconsistency)
                  statusText = 'Checked In @ $timeString';
                  statusColor = Colors.green.shade700;
                  statusIcon = Icons.check_circle;
                } else {
                  // Use joinedAt time, format with date and time
                  timeString = dateTimeFormatter.format(record.joinedAt.toDate().toLocal()); // Format Date & Time
                  statusText = 'Joined @ $timeString';
                  statusColor = Colors.orange.shade800;
                  statusIcon = Icons.hourglass_top_rounded; // Icon indicating waiting for check-in
                }

                return ListTile(
                  leading: CircleAvatar(
                     backgroundColor: statusColor.withOpacity(0.12),
                     foregroundColor: statusColor,
                     child: Text( (index + 1).toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), ),
                  ),
                  title: Text(record.studentName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
                  subtitle: Text( 'Reg #: ${record.registrationNumber}', style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700), ),
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
