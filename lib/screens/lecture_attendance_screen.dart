import 'dart:io';
import 'dart:async'; // Needed for TimeoutException
import 'dart:ui' as ui;

import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/models/attendance_record.dart'; // Ensure this path is correct
import 'package:checkmate/services/api_service.dart';
import 'package:checkmate/services/storage_service.dart'; // Import StorageService
import 'package:cloud_firestore/cloud_firestore.dart'; // Needed for Timestamp comparison
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart'; // Import path_provider
import 'package:url_launcher/url_launcher.dart'; // Import url_launcher
import 'package:share_plus/share_plus.dart'; // Import share_plus


class LectureAttendanceScreen extends StatefulWidget {
  final Lecture lecture;
  const LectureAttendanceScreen({super.key, required this.lecture});
  static const Color brandColor = Color(0xFF0175C2);

  @override
  State<LectureAttendanceScreen> createState() => _LectureAttendanceScreenState();
}

class _LectureAttendanceScreenState extends State<LectureAttendanceScreen> {
  final ApiService _apiService = ApiService();
  final StorageService _storageService = StorageService(); // Instantiate StorageService
  Future<List<AttendanceRecord>>? _attendanceFuture;
  final GlobalKey _qrKey = GlobalKey();
  bool _isProcessingExport = false; // Flag for export loading state

  // Store the sorted list after fetching for consistent export
  List<AttendanceRecord> _sortedAttendanceList = [];

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  void _loadAttendance() {
    if (!mounted) return;
    if (kDebugMode) print("[DEBUG] Fetching attendance (with percentages) for lecture ID: ${widget.lecture.id}");

    // Set loading state for _attendanceFuture, clear list for UI consistency during load
    setState(() {
      _sortedAttendanceList = []; 
      _attendanceFuture = null; // Explicitly nullify to ensure FutureBuilder shows loading
    });

    _attendanceFuture = _apiService.getLectureAttendance(widget.lecture.id)
        .then((records) {
          if (mounted) {
            _sortAttendanceList(records);
            // Update the state with the fetched and sorted records
            setState(() { 
              _sortedAttendanceList = records;
            });
            if (kDebugMode) print("[DEBUG] Attendance loaded and sorted. _sortedAttendanceList.length: ${_sortedAttendanceList.length}");
          }
          return records; // Return records for FutureBuilder
        })
        .catchError((error) {
           if (mounted) {
              setState(() { 
                _sortedAttendanceList = []; // Clear list on error
              });
           }
           if (kDebugMode) print("[DEBUG] Error caught in _loadAttendance chain: $error");
           throw error; // Re-throw for FutureBuilder
        });
    
    // Trigger a rebuild for FutureBuilder to pick up the new future instance.
    if (mounted) {
        setState(() {});
    }
  }

  // Helper function to sort the attendance list consistently
  void _sortAttendanceList(List<AttendanceRecord> list) {
    list.sort((a, b) {
       final bool aCheckedIn = a.checkedIn;
       final bool bCheckedIn = b.checkedIn;

       if (aCheckedIn && bCheckedIn) {
         final Timestamp? aTime = a.checkInTime;
         final Timestamp? bTime = b.checkInTime;
         if (aTime != null && bTime != null) return aTime.compareTo(bTime); // Earliest check-in first
         if (aTime == null && bTime != null) return 1; // Nulls last
         if (aTime != null && bTime == null) return -1; // Nulls last
         return 0; // Both null
       }
       else if (aCheckedIn && !bCheckedIn) { return -1; } // Checked in before joined
       else if (!aCheckedIn && bCheckedIn) { return 1; } // Joined after checked in
       else { return a.joinedAt.compareTo(b.joinedAt); } // Both joined, sort by join time (earliest first)
    });
     // Removed redundant log from here, handled in _loadAttendance.then
  }

  // --- CSV Export Logic ---
  String _escapeCsvField(String? field) {
    if (field == null || field.isEmpty) {
      return '';
    }
    String escaped = field.replaceAll('"', '""'); // Escape double quotes
    // Add quotes if field contains comma, newline, or double quote
    if (escaped.contains(',') || escaped.contains('\n') || escaped.contains('"')) {
      return '"$escaped"';
    }
    return escaped;
  }

  String _generateCsvData(List<AttendanceRecord> records) {
    final StringBuffer buffer = StringBuffer();
    final DateFormat timeFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');

    // Add Header Row
    buffer.writeln('No.,Registration Number,Student Name,Status,Timestamp,Overall Attendance (%)');

    // Add Data Rows
    for (int i = 0; i < records.length; i++) {
      final record = records[i];
      final String status = record.checkedIn ? 'Checked In' : 'Joined Only';
      // Use joinedAt as the timestamp if not checked in
      final Timestamp? relevantTimestamp = record.checkedIn ? record.checkInTime : record.joinedAt;
      final String formattedTime = relevantTimestamp != null
          ? timeFormatter.format(relevantTimestamp.toDate().toLocal())
          : 'N/A';
      final String percentage = record.percentage ?? 'N/A';

      final List<String> row = [
        (i + 1).toString(),
        record.registrationNumber,
        record.studentName,
        status,
        formattedTime,
        percentage,
      ];

      // Escape each field and join with commas
      buffer.writeln(row.map(_escapeCsvField).join(','));
    }
    if (kDebugMode) print("[DEBUG] Generated CSV Data (first 300 chars):\n${buffer.toString().substring(0, (buffer.length > 300 ? 300 : buffer.length))}...");
    return buffer.toString();
  }

  Future<String?> _exportAttendanceCsv() async {
    
    if (kDebugMode) print("[DEBUG] _exportAttendanceCsv called.");

    if (_isProcessingExport || _sortedAttendanceList.isEmpty) {
       if(kDebugMode) print("[DEBUG] Export skipped: Processing=$_isProcessingExport, ListEmpty=${_sortedAttendanceList.isEmpty}");
       return null;
    }

    if(kDebugMode) print("[DEBUG] Starting CSV export process...");
    setState(() { _isProcessingExport = true; });

    try {
     
      if (kDebugMode) print("[DEBUG] Generating CSV data...");
      // This call is now valid because _generateCsvData is defined above
      final String csvData = _generateCsvData(_sortedAttendanceList);

     
      if (kDebugMode) print("[DEBUG] Getting temporary directory...");
      final tempDir = await getTemporaryDirectory();
      final safeUnitCode = widget.lecture.unitCode.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final safeUnitName = widget.lecture.unitName.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final dateStamp = DateFormat('yyyyMMdd').format(widget.lecture.startTime?.toLocal() ?? DateTime.now());
      final fileName = 'Attendance_${safeUnitCode}_${safeUnitName}_$dateStamp.csv';
      final filePath = '${tempDir.path}/$fileName';
      final file = File(filePath);
      if (kDebugMode) print('[DEBUG] Target file path: $filePath');

      if (kDebugMode) print('[DEBUG] Writing CSV data to file...');
      await file.writeAsString(csvData, flush: true);
      final fileExists = await file.exists();
      final fileLength = fileExists ? await file.length() : -1;
      if (kDebugMode) print('[DEBUG] CSV file write complete. Exists: $fileExists, Length: $fileLength bytes');

      if (!fileExists || fileLength <= 0) {
          throw Exception("Failed to write CSV file or file is empty.");
      }

      if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(
           const SnackBar(content: Text('CSV file created. Uploading to cloud...'), duration: Duration(seconds: 3)),
         );
      }

      // Upload the file to Firebase Storage
      final String storagePath = 'attendance_records/${widget.lecture.id}'; // e.g., attendance_records/lectureId/filename.csv
      if (kDebugMode) print('[DEBUG] Uploading $fileName to $storagePath...');
      final String? downloadUrl = await _storageService.uploadFile(storagePath, fileName, await file.readAsBytes());

      if (downloadUrl != null) {
        if (kDebugMode) print("[DEBUG] File uploaded successfully. Download URL: $downloadUrl");
        if (mounted) {
           ScaffoldMessenger.of(context).showSnackBar(
             SnackBar(
                content: Text('Attendance CSV uploaded!'),
                backgroundColor: Colors.green.shade600,
                duration: const Duration(seconds: 5),
                action: SnackBarAction(
                  label: 'DOWNLOAD',
                  textColor: Colors.white,
                  onPressed: () async {
                    if (await canLaunchUrl(Uri.parse(downloadUrl))) {
                      await launchUrl(Uri.parse(downloadUrl));
                    } else {
                      if (kDebugMode) print('[DEBUG] Could not launch $downloadUrl');
                       ScaffoldMessenger.of(context).showSnackBar(
                         SnackBar(content: Text('Could not open download link.'), backgroundColor: Colors.red.shade400),
                       );
                    }
                  },
                ),
              ),
           );
        } else {
          if (kDebugMode) print("[DEBUG] File upload failed or downloadUrl is null.");
           if (mounted) {
             ScaffoldMessenger.of(context).showSnackBar(
               SnackBar(content: Text('Failed to upload attendance file.'), backgroundColor: Colors.red.shade600),
             );
           }
        }
        return downloadUrl; // Return the URL on success
      }
      return null; // Return null on failure to upload

    } catch (e, s) { // Catch stack trace as well
      if (kDebugMode) {
         print("[DEBUG] Error exporting attendance CSV: $e");
         print("[DEBUG] Stack trace: $s");
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error creating attendance file: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
      return null; // Return null on error
    } finally {
      if (mounted) {
        if (kDebugMode) print("[DEBUG] CSV export process finished.");
        setState(() { _isProcessingExport = false; });
      }
    }
  }
  // --- End CSV Export Logic ---

  // --- _captureAndShareQrCode --- 
  Future<void> _captureAndShareQrCode() async {
    try {
      if (_qrKey.currentContext == null) { throw Exception("QR Code context not found."); }
      RenderRepaintBoundary boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) { throw Exception("Could not get byte data from QR code image."); }
      Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final safeUnitCode = widget.lecture.unitCode.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final safeUnitName = widget.lecture.unitName.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'QRCode_${safeUnitCode}_${safeUnitName}_$timestamp.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);
      if (kDebugMode) print('[DEBUG] QR Code saved temporarily to: ${file.path}');

      final xFile = XFile(file.path);
      final result = await Share.shareXFiles(
        [xFile],
        text: 'QR Code for ${widget.lecture.unitName} (${widget.lecture.unitCode}) lecture check-in.',
        subject: 'Lecture Check-In QR Code: ${widget.lecture.unitCode}',
      );

      if (result.status == ShareResultStatus.success) {
        if (kDebugMode) print('[DEBUG] QR Code shared/saved successfully.');
      } else if (result.status == ShareResultStatus.dismissed) {
        if (kDebugMode) print('[DEBUG] Share sheet dismissed.');
      } else {
        if (kDebugMode) print('[DEBUG] Sharing status: ${result.status}, Raw: ${result.raw}');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not complete share action: ${result.status}'), backgroundColor: Colors.orange),
          );
        }
      }
    } catch (e, s) { // Catch stack trace
      if (kDebugMode) {
         print("[DEBUG] Error capturing or sharing QR code: $e");
         print("[DEBUG] Stack trace: $s");
      }
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
    final double dialogContentWidth = (screenWidth * 0.8).clamp(280.0, 400.0);
    final double qrSize = dialogContentWidth * 0.7;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        bool isDialogProcessingShare = false;
        return StatefulBuilder(
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
                      RepaintBoundary(
                        key: _qrKey,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            border: Border.all(color: Colors.grey.shade300, width: 1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.all(8),
                          child: QrImageView(
                            data: widget.lecture.id,
                            version: QrVersions.auto,
                            size: qrSize,
                            gapless: false,
                            backgroundColor: Colors.white,
                            eyeStyle: const QrEyeStyle( eyeShape: QrEyeShape.square, color: Colors.black, ),
                            dataModuleStyle: const QrDataModuleStyle( dataModuleShape: QrDataModuleShape.square, color: Colors.black, ),
                            errorStateBuilder: (cxt, err) {
                              if (kDebugMode) print("[DEBUG] QR Generation Error: $err");
                              return Container( width: qrSize, height: qrSize, color: Colors.grey.shade200, child: const Center( child: Padding( padding: EdgeInsets.all(8.0), child: Text( "Error generating QR code.", textAlign: TextAlign.center, style: TextStyle(color: Colors.red), ), ), ), );
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
                  style: ElevatedButton.styleFrom( foregroundColor: LectureAttendanceScreen.brandColor, backgroundColor: LectureAttendanceScreen.brandColor.withOpacity(0.1), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), ),
                  onPressed: isDialogProcessingShare ? null : () async {
                     setDialogState(() { isDialogProcessingShare = true; });
                     try { await _captureAndShareQrCode(); }
                     finally { if (dialogContext.mounted) { setDialogState(() { isDialogProcessingShare = false; }); } }
                  },
                ),
                TextButton(
                  style: TextButton.styleFrom( foregroundColor: Colors.grey.shade700, padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), ),
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: isDialogProcessingShare ? null : () { Navigator.of(dialogContext).pop(); },
                ),
              ],
            );
          }
        );
      },
    );
  }

  // --- _buildPercentageWidget ---
  Widget _buildPercentageWidget(String? percentageString) {
    if (percentageString == null || percentageString == "N/A" || percentageString.isEmpty) {
      return Tooltip( message: 'Overall percentage unavailable', child: Icon(Icons.percent_outlined, color: Colors.grey.shade400, size: 16), );
    }
    double? percentageValue;
    try { percentageValue = double.parse(percentageString); }
    catch (e) { if (kDebugMode) print("[DEBUG] Warning: Could not parse percentage string '$percentageString': $e"); return Tooltip( message: 'Invalid percentage data', child: Icon(Icons.error_outline, color: Colors.red.shade300, size: 16), ); }
    if (percentageValue < 0 || percentageValue.isNaN || percentageValue.isInfinite) { if (kDebugMode) print("[DEBUG] Warning: Invalid percentage value: $percentageValue"); return Tooltip( message: 'Invalid percentage data', child: Icon(Icons.error_outline, color: Colors.red.shade300, size: 16), ); }
    final Color percColor = percentageValue >= 75 ? Colors.green.shade700 : percentageValue >= 50 ? Colors.orange.shade800 : Colors.red.shade700;
    return Text( '$percentageString%', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: percColor), );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appBarSubtitle = '${widget.lecture.formattedDate} | ${widget.lecture.formattedStartTime} - ${widget.lecture.formattedEndTime} | ${widget.lecture.venue}';
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
            child: Text( appBarSubtitle, style: TextStyle( color: Colors.white.withOpacity(0.9), fontSize: 13, ), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, ),
          ),
        ),
        actions: [
          // --- Export Button ---
          IconButton(
            icon: _isProcessingExport
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.download_outlined),
            tooltip: 'Export Attendance (CSV)',
            // Enable if NOT processing export AND the sorted list is NOT empty
            onPressed: (_isProcessingExport || _sortedAttendanceList.isEmpty)
                       ? null
                       : () { // Wrap in lambda to add logging
                           if (kDebugMode) print("[DEBUG] Export button tapped!");
                           _exportAttendanceCsv().then((url) {
                              if (url == null && mounted) {
                                // Optionally show a generic failure message if not handled by specific errors in _exportAttendanceCsv
                              }
                           });
                         },
          ),
          // --- End Export Button ---
          IconButton(
            icon: const Icon(Icons.qr_code_2),
            tooltip: 'Show Lecture Check-In QR Code',
            onPressed: _isProcessingExport ? null : _showQrCodeDialog, // Disable while exporting
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Attendance',
            onPressed: _isProcessingExport ? null : _loadAttendance, // Disable while exporting
          ),
        ],
      ),
      body: RefreshIndicator(
        color: LectureAttendanceScreen.brandColor,
        onRefresh: () async => _loadAttendance(),
        child: FutureBuilder<List<AttendanceRecord>>(
          future: _attendanceFuture,
          builder: (context, snapshot) {
            // --- Loading State ---
            if (snapshot.connectionState == ConnectionState.waiting && _sortedAttendanceList.isEmpty) {
              return const Center(child: CircularProgressIndicator(color: LectureAttendanceScreen.brandColor));
            }

            // --- Error State ---
            if (snapshot.hasError && _sortedAttendanceList.isEmpty) {
              final error = snapshot.error;
              final stackTrace = snapshot.stackTrace;
              if (kDebugMode) { print("[DEBUG] Error loading attendance: $error"); print("[DEBUG] Stack trace: $stackTrace"); }
              String displayMessage = 'Error loading attendance list.';
              if (error is ApiException) { displayMessage = error.message; }
              else if (error is TimeoutException) { displayMessage = 'Request timed out.'; }
              else { displayMessage = 'An unexpected error occurred.'; }
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, color: Colors.red.shade400, size: 48),
                      const SizedBox(height: 10),
                      Text( '$displayMessage\nPlease pull down to retry.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700) ),
                      if (kDebugMode) Padding( padding: const EdgeInsets.only(top: 8.0), child: Text('\nDetails: $error', style: TextStyle(fontSize: 10, color: Colors.grey)), ),
                    ],
                  )
                )
              );
            }

            // --- Empty State ---
            if (_sortedAttendanceList.isEmpty) {
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
                            Text( 'No students have joined or been checked in yet.\nPull down to refresh.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              });
            }

            // --- Success State - Display List ---
            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0),
              itemCount: _sortedAttendanceList.length,
              separatorBuilder: (context, index) => const Divider( height: 0.5, thickness: 0.5, indent: 72, endIndent: 16, ),
              itemBuilder: (context, index) {
                final record = _sortedAttendanceList[index];
                final bool isCheckedIn = record.checkedIn;
                final String statusText;
                final Color statusColor;
                final IconData statusIcon;
                String timeString = 'N/A';

                if (isCheckedIn) {
                  final checkInTimestamp = record.checkInTime;
                  if (checkInTimestamp != null) { timeString = dateTimeFormatter.format(checkInTimestamp.toDate().toLocal()); }
                  statusText = 'Checked In @ $timeString';
                  statusColor = Colors.green.shade700;
                  statusIcon = Icons.check_circle;
                } else {
                  timeString = dateTimeFormatter.format(record.joinedAt.toDate().toLocal());
                  statusText = 'Joined @ $timeString';
                  statusColor = Colors.orange.shade800;
                  statusIcon = Icons.hourglass_top_rounded;
                }

                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: statusColor.withOpacity(0.12),
                    foregroundColor: statusColor,
                    child: Text( (index + 1).toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), ),
                  ),
                  title: Text( record.studentName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500) ),
                  subtitle: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible( child: Text( 'Reg #: ${record.registrationNumber}', style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700), overflow: TextOverflow.ellipsis, ), ),
                      const SizedBox(width: 8),
                      _buildPercentageWidget(record.percentage),
                    ],
                  ),
                  trailing: Chip(
                    avatar: Icon(statusIcon, color: statusColor, size: 16),
                    label: Text( statusText, style: TextStyle(fontSize: 11.5, color: statusColor, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, ),
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