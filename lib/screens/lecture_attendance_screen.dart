// lib/screens/lecture_attendance_screen.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/models/lecture.dart';
import 'package:checkmate/services/api_service.dart';
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
  Future<List<AttendanceRecord>>? _attendanceFuture;
  final GlobalKey _qrKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _loadAttendance();
  }

  void _loadAttendance() {
    if (!mounted) return;
    print("Fetching attendance for lecture ID: ${widget.lecture.id}");
    setState(() {
      _attendanceFuture = _apiService.getLectureAttendance(widget.lecture.id);
    });
  }

  Future<void> _captureAndShareQrCode() async {
    try {
      if (_qrKey.currentContext == null) { throw Exception("QR Code context not found."); }
      RenderRepaintBoundary boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) { throw Exception("Could not get byte data from QR code image."); }
      Uint8List pngBytes = byteData.buffer.asUint8List();
      final tempDir = await getTemporaryDirectory();
      final safeUnitCode = widget.lecture.unitCode.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final safeUnitName = widget.lecture.unitName.replaceAll(RegExp(r'[^\w\.-]'), '_');
      final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
      final fileName = 'QRCode_${safeUnitCode}_${safeUnitName}_$timestamp.png';
      final file = File('${tempDir.path}/$fileName');
      await file.writeAsBytes(pngBytes);
      print('QR Code saved temporarily to: ${file.path}');

      final xFile = XFile(file.path);
      final result = await Share.shareXFiles( [xFile], text: 'QR Code for ${widget.lecture.unitName} (${widget.lecture.unitCode}) lecture check-in.', subject: 'Lecture Check-In QR Code: ${widget.lecture.unitCode}', );

      if (result.status == ShareResultStatus.success) { print('QR Code shared/saved successfully.'); }
      else if (result.status == ShareResultStatus.dismissed) { print('Share sheet dismissed.'); }
      else { print('Sharing status: ${result.status}'); if (mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Could not complete action: ${result.status}'), backgroundColor: Colors.orange), ); } }
    } catch (e) {
      print("Error capturing or sharing QR code: $e");
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar( SnackBar(content: Text('Error preparing QR code: ${e.toString()}'), backgroundColor: Colors.red), ); }
    }
  }

  void _showQrCodeDialog() {
    if (widget.lecture.id.isEmpty) {
       ScaffoldMessenger.of(context).showSnackBar( const SnackBar(content: Text('Error: Lecture ID is missing.'), backgroundColor: Colors.red), ); return;
    }
    final screenWidth = MediaQuery.of(context).size.width;
    final double dialogContentWidth = screenWidth * 0.8 > 400 ? 400 : screenWidth * 0.8;
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
              title: const Row( children: [ Icon(Icons.qr_code_2, color: LectureAttendanceScreen.brandColor, size: 26), SizedBox(width: 10), Expanded(child: Text('Check-In QR Code', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold))), ], ),
              content: SizedBox( width: dialogContentWidth,
                child: SingleChildScrollView(
                  child: Column( mainAxisSize: MainAxisSize.min, children: [
                      Text( '${widget.lecture.unitName} (${widget.lecture.unitCode})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600), textAlign: TextAlign.center, ),
                      const SizedBox(height: 6),
                       // --- REVERTED FORMATTING ---
                       Text( '${widget.lecture.formattedDate} | ${widget.lecture.formattedStartTime} - ${widget.lecture.formattedEndTime}', // Use DateTime formatters
                         style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700), textAlign: TextAlign.center, ),
                       // --- END REVERSION ---
                       const SizedBox(height: 4),
                       Text( 'Venue: ${widget.lecture.venue}', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade700), textAlign: TextAlign.center, ),
                       const SizedBox(height: 20),
                      RepaintBoundary( key: _qrKey,
                        child: Container( decoration: BoxDecoration( color: Colors.white, border: Border.all(color: Colors.grey.shade300, width: 1), borderRadius: BorderRadius.circular(8), ), padding: const EdgeInsets.all(8),
                          child: QrImageView( data: widget.lecture.id, version: QrVersions.auto, size: qrSize, gapless: false, backgroundColor: Colors.white, eyeStyle: const QrEyeStyle( eyeShape: QrEyeShape.square, color: Colors.black), dataModuleStyle: const QrDataModuleStyle( dataModuleShape: QrDataModuleShape.square, color: Colors.black),
                            errorStateBuilder: (cxt, err) { print("QR Generation Error: $err"); return Container( width: qrSize, height: qrSize, color: Colors.grey.shade200, child: const Center( child: Padding( padding: EdgeInsets.all(8.0), child: Text( "Error generating QR code.", textAlign: TextAlign.center, style: TextStyle(color: Colors.red), ), ), ), ); },
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      const Text( 'Students: Scan this code with the Checkmate app *after joining* to CHECK IN for this lecture.', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, color: Colors.black54), ),
                    ],
                  ),
                ),
              ),
              actionsAlignment: MainAxisAlignment.center,
              actions: <Widget>[
                ElevatedButton.icon( icon: isDialogProcessingShare ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: LectureAttendanceScreen.brandColor)) : const Icon(Icons.download_outlined, size: 20), label: Text(isDialogProcessingShare ? 'Processing...' : 'Download'), style: ElevatedButton.styleFrom( foregroundColor: LectureAttendanceScreen.brandColor, backgroundColor: LectureAttendanceScreen.brandColor.withOpacity(0.1), elevation: 0, padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), ),
                  onPressed: isDialogProcessingShare ? null : () async {
                     setDialogState(() { isDialogProcessingShare = true; });
                     try { await _captureAndShareQrCode(); }
                     finally { if (dialogContext.mounted) { setDialogState(() { isDialogProcessingShare = false; }); } }
                  },
                ),
                TextButton( style: TextButton.styleFrom( foregroundColor: Colors.grey.shade700, padding: const EdgeInsets.symmetric(horizontal: 25, vertical: 10), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)), ), child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  onPressed: isDialogProcessingShare ? null : () { Navigator.of(dialogContext).pop(); },
                ),
              ],
            );
          }
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // --- REVERTED FORMATTING ---
    final appBarSubtitle = '${widget.lecture.formattedDate} | ${widget.lecture.formattedStartTime} - ${widget.lecture.formattedEndTime} | ${widget.lecture.venue}'; // Use DateTime formatters
    // --- END REVERSION ---
    final dateTimeFormatter = DateFormat('MMM d, hh:mm a');

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.lecture.unitName, style: const TextStyle(fontSize: 18)),
        backgroundColor: LectureAttendanceScreen.brandColor, foregroundColor: Colors.white, elevation: 2.0,
        bottom: PreferredSize( preferredSize: const Size.fromHeight(25.0), child: Padding( padding: const EdgeInsets.only(bottom: 8.0, left: 16.0, right: 16.0), child: Text( appBarSubtitle, style: TextStyle( color: Colors.white.withOpacity(0.9), fontSize: 13, ), textAlign: TextAlign.center, overflow: TextOverflow.ellipsis, ), ), ),
        actions: [
          IconButton( icon: const Icon(Icons.qr_code_2), tooltip: 'Show Lecture Check-In QR Code', onPressed: _showQrCodeDialog, ),
          IconButton( icon: const Icon(Icons.refresh), tooltip: 'Refresh Attendance', onPressed: _loadAttendance, ),
        ],
      ),
      body: RefreshIndicator( color: LectureAttendanceScreen.brandColor, onRefresh: () async => _loadAttendance(),
        child: FutureBuilder<List<AttendanceRecord>>(
          future: _attendanceFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) { return Center(child: CircularProgressIndicator(color: LectureAttendanceScreen.brandColor)); }
            if (snapshot.hasError) { print("Error loading attendance: ${snapshot.error}"); print("Error details: ${snapshot.error.runtimeType} ${snapshot.stackTrace}"); return Center( child: Padding( padding: const EdgeInsets.all(16.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.error_outline, color: Colors.red.shade400, size: 48), const SizedBox(height: 10), Text('Error loading attendance list.\nPlease check your connection and pull down to retry.', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade700)), if (kDebugMode) Text('\n${snapshot.error}', style: TextStyle(fontSize: 10, color: Colors.grey)), ], ) ) ); }
            if (!snapshot.hasData || snapshot.data!.isEmpty) { return LayoutBuilder(builder: (context, constraints) { return SingleChildScrollView( physics: const AlwaysScrollableScrollPhysics(), child: ConstrainedBox( constraints: BoxConstraints(minHeight: constraints.maxHeight), child: Center( child: Padding( padding: const EdgeInsets.all(20.0), child: Column( mainAxisAlignment: MainAxisAlignment.center, children: [ Icon(Icons.people_outline, size: 50, color: Colors.grey.shade400), const SizedBox(height: 10), Text( 'No students have joined or been checked in yet.\nPull down to refresh.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ), ], ), ), ), ), ); }); }

            final attendanceList = snapshot.data!;
            attendanceList.sort((a, b) {
               final bool aCheckedIn = a.checkedIn; final bool bCheckedIn = b.checkedIn;
               if (aCheckedIn && bCheckedIn) { final aTime = a.checkInTime; final bTime = b.checkInTime; if (aTime != null && bTime != null) return aTime.compareTo(bTime); if (aTime == null && bTime != null) return 1; if (aTime != null && bTime == null) return -1; return 0; }
               else if (aCheckedIn && !bCheckedIn) { return -1; } else if (!aCheckedIn && bCheckedIn) { return 1; }
               else { final aJoined = a.joinedAt; final bJoined = b.joinedAt; if (aJoined != null && bJoined != null) return aJoined.compareTo(bJoined); if (aJoined == null && bJoined != null) return 1; if (aJoined != null && bJoined == null) return -1; return 0; }
            });

            return ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 0), itemCount: attendanceList.length,
              separatorBuilder: (context, index) => const Divider(height: 0.5, thickness: 0.5, indent: 72, endIndent: 16),
              itemBuilder: (context, index) {
                final record = attendanceList[index];
                final bool isCheckedIn = record.checkedIn;
                final String statusText; final Color statusColor; final IconData statusIcon; final String timeString;
                if (isCheckedIn) { timeString = record.checkInTime != null ? dateTimeFormatter.format(record.checkInTime!.toDate().toLocal()) : 'N/A'; statusText = 'Checked In @ $timeString'; statusColor = Colors.green.shade700; statusIcon = Icons.check_circle; }
                else { timeString = record.joinedAt != null ? dateTimeFormatter.format(record.joinedAt!.toDate().toLocal()) : 'N/A'; statusText = 'Joined @ $timeString'; statusColor = Colors.orange.shade800; statusIcon = Icons.hourglass_top_rounded; }
                return ListTile(
                  leading: CircleAvatar( backgroundColor: statusColor.withOpacity(0.12), foregroundColor: statusColor, child: Text( (index + 1).toString(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), ), ),
                  title: Text(record.studentName, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w500)),
                  subtitle: Text( 'Reg #: ${record.registrationNumber}', style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700), ),
                  trailing: Chip( avatar: Icon(statusIcon, color: statusColor, size: 16), label: Text( statusText, style: TextStyle(fontSize: 11.5, color: statusColor, fontWeight: FontWeight.w500), overflow: TextOverflow.ellipsis, ), backgroundColor: statusColor.withOpacity(0.1), side: BorderSide.none, padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3), visualDensity: VisualDensity.compact, ),
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
