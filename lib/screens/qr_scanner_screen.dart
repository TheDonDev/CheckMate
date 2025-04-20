// lib/screens/qr_scanner_screen.dart
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController(
    // Optional: Configure detection speed, facing direction etc.
    // detectionSpeed: DetectionSpeed.normal,
    // facing: CameraFacing.back,
  );
  bool _isProcessing = false; // Flag to prevent multiple scans

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _handleDetection(BarcodeCapture capture) {
    if (_isProcessing) return; // Don't process if already processing

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isNotEmpty) {
      final String? scannedValue = barcodes.first.rawValue;

      if (scannedValue != null && scannedValue.isNotEmpty) {
        setState(() {
          _isProcessing = true; // Set flag
        });
        print("QR Code Detected: $scannedValue"); // Debug log

        // Stop the camera and pop the screen with the result
        _scannerController.stop();
        // Pop with the scanned value (will be received by LecturerDashboard)
        Navigator.of(context).pop(scannedValue);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Get screen size for overlay dimensions
    final screenWidth = MediaQuery.of(context).size.width;
    final scanAreaSize = screenWidth * 0.7; // Example: 70% of screen width

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Student QR Code'),
        backgroundColor: const Color(0xFF0175C2), // Use brand color
        foregroundColor: Colors.white,
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _handleDetection,
            // Optional: Add overlay/scan window
            // scanWindow: Rect.fromCenter(
            //   center: MediaQuery.of(context).size.center(Offset.zero),
            //   width: 250,
            //   height: 250,
            // ),
          ),
          // --- Centered Scan Area Overlay ---
          Center(
            child: Container(
              width: scanAreaSize,
              height: scanAreaSize,
              decoration: BoxDecoration(
                border: Border.all(
                  color: Colors.red.withOpacity(0.7), // Visible border color
                  width: 3,
                ),
                borderRadius: BorderRadius.circular(12), // Optional rounded corners
              ),
            ),
          ),
          // --- Optional: Instruction Text ---
          Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              padding: const EdgeInsets.all(20),
              color: Colors.black.withOpacity(0.5),
              child: const Text(
                'Position the student\'s registration QR code within the frame.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
