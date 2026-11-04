import 'dart:io';
import 'dart:async'; // Needed for TimeoutException
import 'dart:convert'; // For utf8.encode
import 'dart:ui' as ui;

import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/models/attendance_record.dart'; // Ensure this path is correct
import 'package:checkmate/services/api_service.dart';
import 'package:checkmate/widgets/document_name_widget.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Needed for Timestamp comparison
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart'; // Import path_provider
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
    if (_isProcessingExport || _sortedAttendanceList.isEmpty) return null;
    setState(() => _isProcessingExport = true);
    try {
      final csvBytes = Uint8List.fromList(utf8.encode(_generateCsvData(_sortedAttendanceList)));
      final safeUnitCode = widget.lecture.unitCode.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final safeUnitName = widget.lecture.unitName.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final dateStamp = DateFormat('yyyyMMdd').format(widget.lecture.startTime?.toLocal() ?? DateTime.now());
      final fileName = 'Attendance_${safeUnitCode}_${safeUnitName}_$dateStamp.csv';
      final XFile exportFile;

      if (kIsWeb) {
        exportFile = XFile.fromData(csvBytes, name: fileName, mimeType: 'text/csv');
      } else {
        final directory = await getTemporaryDirectory();
        final file = File('${directory.path}/$fileName');
        await file.writeAsBytes(csvBytes, flush: true);
        exportFile = XFile(file.path);
      }

      await Share.shareXFiles([exportFile], text: 'Attendance for ${widget.lecture.unitName} (${widget.lecture.unitCode})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Attendance CSV is ready to share.')));
      }
      return fileName;
    } catch (error) {
      if (mounted) _showErrorDialog('Export Error', 'Could not prepare the attendance file: $error');
      return null;
    } finally {
      if (mounted) setState(() => _isProcessingExport = false);
    }
  }
  // --- End CSV Export Logic ---

  // Helper to show a user-friendly error dialog
  void _showErrorDialog(String title, String content) {
    if (!mounted) return;
    showDialog(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: Row(children: [ Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error), const SizedBox(width: 10), Text(title), ]),
            content: Text(content),
            actions: <Widget>[ TextButton(child: const Text('OK'), onPressed: () => Navigator.of(dialogContext).pop()), ],
          );
        });
  }

  // --- _captureAndShareQrCode ---
  Future<void> _captureAndShareQrCode() async {
    try {
      if (_qrKey.currentContext == null) { throw Exception("QR Code context not found."); }
      RenderRepaintBoundary boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) { throw Exception("Could not get byte data from QR code image."); }
      Uint8List pngBytes = byteData.buffer.asUint8List();

      final safeUnitCode = widget.lecture.unitCode.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final safeUnitName = widget.lecture.unitName.replaceAll(RegExp(r'[^\w\.-]+'), '_');
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'QRCode_${safeUnitCode}_${safeUnitName}_$timestamp.png';

      final XFile xFile;
      if (kIsWeb) {
        if (kDebugMode) print('[DEBUG] Web platform: Creating XFile for QR code from data.');
        xFile = XFile.fromData(pngBytes, name: fileName, mimeType: 'image/png', lastModified: DateTime.now());
      } else {
        if (kDebugMode) print('[DEBUG] Native platform: Saving QR code to temporary file.');
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/$fileName');
        await file.writeAsBytes(pngBytes);
        if (kDebugMode) print('[DEBUG] QR Code saved temporarily to: ${file.path}');
        xFile = XFile(file.path);
      }

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
          _showErrorDialog('Share Incomplete', 'The share action could not be completed. Status: ${result.status}');
        }
      }
    } catch (e, s) { // Catch stack trace
      if (kDebugMode) {
         print("[DEBUG] Error capturing or sharing QR code: $e");
         print("[DEBUG] Stack trace: $s");
      }
      if (mounted) {
        _showErrorDialog('QR Code Error', 'An error occurred while preparing the QR code for sharing: ${e.toString()}');
      }
    }
  }

  // --- _showQrCodeDialog  ---
  void _showQrCodeDialog() {
    if (widget.lecture.id.isEmpty) {
       _showErrorDialog('QR Generation Failed', 'Cannot generate QR code because the Lecture ID is missing.');
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
                         'Venue: ', // Keep the label
                         style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700),
                         textAlign: TextAlign.center,
                      ),
                      DocumentNameWidget(
                        collection: 'venues', documentId: widget.lecture.venue,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700, fontWeight: FontWeight.w500),
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
                  onPressed: isDialogProcessingShare ? null : () { Navigator.of(dialogContext).pop(); },
                  child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
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
    final DateFormat dateTimeFormatter = DateFormat('yyyy-MM-dd HH:mm:ss');

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
            child: Text( '${widget.lecture.formattedDate} | ${widget.lecture.formattedStartTime} - ${widget.lecture.formattedEndTime}', style: TextStyle( color: Colors.white.withOpacity(0.9), fontSize: 13, ), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, ),
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
