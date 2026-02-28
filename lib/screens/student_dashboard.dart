// lib/screens/student_dashboard.dart
import 'package:checkmate/models/app_user.dart' as app_user;
import 'package:checkmate/models/lecture.dart'; 
import 'package:checkmate/models/attendance_record.dart';
import 'package:checkmate/services/api_service.dart';
import 'package:checkmate/services/auth_service.dart';
import 'package:checkmate/services/admin_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:checkmate/widgets/document_name_widget.dart';
import 'package:checkmate/screens/welcome_screen.dart';
import 'package:flutter/foundation.dart';
import 'package:checkmate/screens/qr_scanner_screen.dart';
import 'package:collection/collection.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async'; // Import for TimeoutException
import 'dart:ui';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shimmer/shimmer.dart';

class StudentDashboard extends StatefulWidget {
  final app_user.User currentUser;
  const StudentDashboard({super.key, required this.currentUser});

  @override
  State<StudentDashboard> createState() => _StudentDashboardState();
}

class _StudentDashboardState extends State<StudentDashboard> with SingleTickerProviderStateMixin {
  final ApiService apiService = ApiService();

  Stream<List<Lecture>>? _lecturesStream; // Changed from Future to Stream
  String? _processingLectureId;

  // User profile details
  String? fixedSchool;
  String? fixedDepartment;
  String? fixedCourse;
  String? fixedYearOfStudy;
  String? fixedSemester;

  // Name cache
  String? _yearOfStudyName;
  String? _semesterName;

  // Attendance summary state
  bool _isLoadingSummary = true;
  String? _summaryError;
  String? _attendancePercentage;
  int? _totalLectures;
  int? _attendedLectures;
  List<AttendanceRecord>? _summaryAttendanceRecords;

  // --- Ad State ---
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;
  late AnimationController _adController;
  late Animation<Offset> _offsetAnimation;

  // --- Interstitial Ad State ---
  InterstitialAd? _interstitialAd;
  int _numInterstitialLoadAttempts = 0;
  final int maxFailedLoadAttempts = 3;

  static const Color brandColor = Color(0xFF0175C2);

  @override
  void initState() {
    super.initState();
    fixedSchool = widget.currentUser.school;
    fixedDepartment = widget.currentUser.department;
    fixedCourse = widget.currentUser.course;
    fixedYearOfStudy = widget.currentUser.yearOfStudy;
    fixedSemester = widget.currentUser.semester;

    _adController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0.0, 1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _adController, curve: Curves.easeOutQuart));

    _loadNames();
    // Load the banner ad
    _loadBannerAd();
    // Load the interstitial ad
    _createInterstitialAd();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
        _showMissingRegNumError();
      } else if (fixedYearOfStudy == null || fixedYearOfStudy!.isEmpty || fixedSemester == null || fixedSemester!.isEmpty) {
        _showMissingYearSemesterError();
      } else {
        loadLectures();
        _loadAttendanceSummary();
      }
    });
  }

  @override
  void dispose() {
    _bannerAd?.dispose();
    _adController.dispose();
    _interstitialAd?.dispose();
    super.dispose();
  }

  // --- Dialogs ---
  void _showMissingRegNumError() {
     // Ensure context and builder are correctly passed
     showDialog(
        context: context, // Pass the current BuildContext
        barrierDismissible: false,
        builder: (BuildContext dialogContext) { // Use a different context name for builder
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Row(
               children: [ Icon(Icons.error_outline, color: Colors.red), SizedBox(width: 10), Text('Registration Incomplete'), ],
            ),
            content: const Text('Your student registration number is missing.\nPlease contact support or update your profile to use attendance features.'),
            actions: [
              TextButton(
                onPressed: () async {
                   Navigator.of(dialogContext).pop(); // Use dialogContext
                   // Use context from the State, not dialogContext for Provider
                   await Provider.of<AuthService>(context, listen: false).logout();
                   if (mounted) {
                      // Use context from the State for navigation
                      Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, );
                   }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Logout'),
              ),
            ],
          );
        } // End builder
     );
  }

  void _showMissingYearSemesterError() {
     // Ensure context and builder are correctly passed
     showDialog(
        context: context, // Pass the current BuildContext
        barrierDismissible: false,
        builder: (BuildContext dialogContext) { // Use a different context name for builder
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            title: const Row(
               children: [ Icon(Icons.error_outline, color: Colors.orange), SizedBox(width: 10), Text('Profile Incomplete'), ],
            ),
            content: const Text('Your Year of Study or Semester is missing.\nPlease contact support or update your profile.'),
            actions: [
              TextButton(
                onPressed: () async {
                   Navigator.of(dialogContext).pop(); // Use dialogContext
                   // Use context from the State, not dialogContext for Provider
                   await Provider.of<AuthService>(context, listen: false).logout();
                   if (mounted) {
                      // Use context from the State for navigation
                      Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, );
                   }
                },
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Logout'),
              ),
            ],
          );
        } // End builder
     );
  }

  // --- Data Loading ---
  void loadLectures() {
    if (fixedSchool == null || fixedDepartment == null || fixedCourse == null || fixedYearOfStudy == null || fixedSemester == null) {
      if (kDebugMode) print("Cannot load lectures: Missing fixed user details.");
      if (mounted) { setState(() { _lecturesStream = Stream<List<Lecture>>.value(<Lecture>[]); }); } // Set to empty stream
      return;
    }
    if (!mounted) return;

    setState(() {
      // Use a stream to get real-time updates for lectures.
      // This stream combines lectures the student has joined with currently available lectures.
      _lecturesStream = apiService.getStudentLecturesStream(
        userId: widget.currentUser.id,
        schoolId: fixedSchool!,
        departmentId: fixedDepartment!,
        courseId: fixedCourse!,
        yearId: fixedYearOfStudy!,
        semesterId: fixedSemester!,
      );
    });
  }
  Future<void> _loadAttendanceSummary() async {
    if (!mounted || widget.currentUser.id.isEmpty) return;
    if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
        setState(() { _isLoadingSummary = false; _summaryError = "Registration number missing."; _summaryAttendanceRecords = null; });
        return;
    }
     if (fixedYearOfStudy == null || fixedSemester == null) {
        setState(() { _isLoadingSummary = false; _summaryError = "Year/Semester missing."; _summaryAttendanceRecords = null; });
        return;
    }

    setState(() { _isLoadingSummary = true; _summaryError = null; });
    try {
      final summaryData = await apiService.getStudentAttendanceSummary(
          widget.currentUser.id,
          year: fixedYearOfStudy,
          semester: fixedSemester
      );

      if (!mounted) return;
      setState(() {
        _attendancePercentage = summaryData['percentage'] as String?;
        _totalLectures = summaryData['totalLectures'] as int?;
        _attendedLectures = summaryData['attendedLectures'] as int?;
        _summaryAttendanceRecords = summaryData['attendanceRecords'] as List<AttendanceRecord>?;
        _isLoadingSummary = false;
      });
      if (kDebugMode) print("Attendance Summary Loaded for $fixedYearOfStudy/$fixedSemester: $_attendancePercentage% ($_attendedLectures/$_totalLectures). Records: ${_summaryAttendanceRecords?.length ?? 0}");
    } catch (e) {
      if (!mounted) return;
      if (kDebugMode) print("Error loading attendance summary for $fixedYearOfStudy/$fixedSemester: $e");
      setState(() {
        _summaryError = e is ApiException ? e.message : "An error occurred";
        _isLoadingSummary = false;
        _attendancePercentage = null; _totalLectures = null; _attendedLectures = null; _summaryAttendanceRecords = null;
      });
    }
  }

  Future<void> _loadNames() async {
    final adminService = AdminService();
    if (fixedYearOfStudy != null && fixedYearOfStudy!.isNotEmpty) {
      try {
        final name = await adminService.getDocumentName('years_of_study', fixedYearOfStudy!);
        if (mounted) setState(() => _yearOfStudyName = name);
      } catch (e) {
        if (kDebugMode) print("Error loading year of study name: $e");
      }
    }
    if (fixedSemester != null && fixedSemester!.isNotEmpty) {
      try {
        final name = await adminService.getDocumentName('semesters', fixedSemester!);
        if (mounted) setState(() => _semesterName = name);
      } catch (e) {
        if (kDebugMode) print("Error loading semester name: $e");
      }
    }
  }

  // --- Ad Loading ---
  void _loadBannerAd() {
    if (kIsWeb) return; // Prevent loading on Web
    String adUnitId;
    if (kDebugMode) {
      adUnitId = defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/6300978111' // Android Test ID
          : 'ca-app-pub-3940256099942544/2934735716'; // iOS Test ID
    } else {
      adUnitId = defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/6300978111' // Replace with your Android Production ID
          : 'ca-app-pub-3940256099942544/2934735716'; // Replace with your iOS Production ID
    }

    _bannerAd = BannerAd(
      adUnitId: adUnitId,
      request: const AdRequest(),
      size: AdSize.banner,
      listener: BannerAdListener(
        onAdLoaded: (Ad ad) {
          if (kDebugMode) {
            print('BannerAd loaded.');
          }
          if (mounted) {
            setState(() {
              _isBannerAdLoaded = true;
            });
            _adController.forward();
          }
        },
        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          if (kDebugMode) {
            print('BannerAd failed to load: $error');
          }
          ad.dispose();
        },
      ),
    )..load();
  }

  void _createInterstitialAd() {
    if (kIsWeb) return; // Prevent loading on Web
    String adUnitId;
    if (kDebugMode) {
      adUnitId = defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/1033173712' // Android Test ID
          : 'ca-app-pub-3940256099942544/4411468910'; // iOS Test ID
    } else {
      adUnitId = defaultTargetPlatform == TargetPlatform.android
          ? 'ca-app-pub-3940256099942544/1033173712' // Replace with your Android Production ID
          : 'ca-app-pub-3940256099942544/4411468910'; // Replace with your iOS Production ID
    }

    InterstitialAd.load(
        adUnitId: adUnitId,
        request: const AdRequest(),
        adLoadCallback: InterstitialAdLoadCallback(
          onAdLoaded: (InterstitialAd ad) {
            if (kDebugMode) print('$ad loaded');
            _interstitialAd = ad;
            _numInterstitialLoadAttempts = 0;
            _interstitialAd!.setImmersiveMode(true);
          },
          onAdFailedToLoad: (LoadAdError error) {
            if (kDebugMode) print('InterstitialAd failed to load: $error.');
            _numInterstitialLoadAttempts += 1;
            _interstitialAd = null;
            if (_numInterstitialLoadAttempts < maxFailedLoadAttempts) {
              _createInterstitialAd();
            }
          },
        ));
  }

  void _showInterstitialAd() {
    if (_interstitialAd == null) {
      if (kDebugMode) print('Warning: attempt to show interstitial before loaded.');
      return;
    }
    _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (InterstitialAd ad) {
        ad.dispose();
        _createInterstitialAd();
      },
      onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
        ad.dispose();
        _createInterstitialAd();
      },
    );
    _interstitialAd!.show();
    _interstitialAd = null;
  }

  Future<void> _dismissAd() async {
    try {
      await _adController.reverse();
    } catch (e) {
      // Ignore if controller is disposed during animation
    }
    if (mounted) {
      setState(() {
        _isBannerAdLoaded = false;
      });
      _bannerAd?.dispose();
      _bannerAd = null;
    }
  }

  // --- Helpers ---
  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString.trim());
    final Uri launchUri = url.hasScheme ? url : Uri.parse('https://$urlString');
    try {
      if (!await launchUrl(launchUri, mode: LaunchMode.externalApplication)) {
        throw Exception('Could not launch URL');
      }
    } catch (e) {
      if (mounted) {
        _showErrorDialog('Action Failed', 'Could not open the link: $urlString');
      }
      if (kDebugMode) print('Error launching URL $launchUri: $e');
    }
  }

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

  void showSnackBar(String message, {bool isError = false}) {
      if (!mounted) return;
     ScaffoldMessenger.of(context).showSnackBar(
       SnackBar(
         content: Text(message),
         backgroundColor: isError ? Theme.of(context).colorScheme.error : Colors.green.shade600,
         behavior: SnackBarBehavior.floating,
         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
         margin: const EdgeInsets.all(10),
       ),
     );
  }

  // --- Percentage Widget ---
  Widget _buildPercentageWidget(String? percentageString) {
    // Use context safely within the State class
    final headlineStyle = Theme.of(context).textTheme.headlineSmall;

    // Handle null, "N/A", or empty strings
    if (percentageString == null || percentageString == "N/A" || percentageString.isEmpty) {
      return Text(
        'N/A',
        style: headlineStyle?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.grey.shade500,
        ),
      );
    }

    double? percentageValue;
    try {
      percentageValue = double.parse(percentageString);
    } catch (e) {
      if (kDebugMode) print("Warning: Could not parse percentage string '$percentageString': $e");
      return Text(
        'ERR',
        style: headlineStyle?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.red.shade700,
        ),
      );
    }

    // Handle invalid numeric values
    if (percentageValue < 0 || percentageValue.isNaN || percentageValue.isInfinite) {
      if (kDebugMode) print("Warning: Invalid percentage value: $percentageValue");
      return Text(
        'ERR',
        style: headlineStyle?.copyWith(
          fontWeight: FontWeight.bold,
          color: Colors.red.shade700,
        ),
      );
    }

    // Determine color based on percentage value
    final Color percColor = percentageValue >= 75 ? Colors.green.shade600 :
                             percentageValue >= 50 ? Colors.orange.shade700 :
                             Colors.red.shade700;

    // Display the percentage text
    return Text(
      '$percentageString%',
      style: headlineStyle?.copyWith(
        fontWeight: FontWeight.bold,
        color: percColor,
      ),
    );
  }


  // --- Actions ---

  // Join Lecture
  Future<void> _handleStudentJoin(Lecture lecture) async {
    final studentRegNum = widget.currentUser.registrationNumber;
    if (studentRegNum == null || studentRegNum.isEmpty) {
      _showErrorDialog('Action Failed', 'Your registration number is missing. Cannot join lecture.'); return;
    }
    if (_processingLectureId != null) return;

    setState(() { _processingLectureId = lecture.id; });
    try {
      await apiService.joinLecture(lecture.id);
      if (!mounted) return;

      await _loadAttendanceSummary();
      showSnackBar('Successfully joined ${lecture.unitName}!', isError: false);

      // Show Interstitial Ad immediately after joining
      _showInterstitialAd();

      if (lecture.venue.toLowerCase() == 'online' &&
          lecture.onlineLink != null &&
          lecture.onlineLink!.trim().isNotEmpty) {
        if (kDebugMode) print("Attempting to auto-launch online link after join: ${lecture.onlineLink}");
        await Future.delayed(const Duration(milliseconds: 300));
        if (mounted) {
            await _launchURL(lecture.onlineLink!);
        }
      }

    } catch (e) {
      if (!mounted) return;
      if (e is ApiException && e.statusCode == 409) {
         showSnackBar('You have already joined ${lecture.unitName}.', isError: false);
         await _loadAttendanceSummary();
      } else {
         _showErrorDialog('Join Failed', e is ApiException ? e.message : 'An unexpected error occurred. Please try again.');
      }
    } finally {
      if (mounted) { setState(() { _processingLectureId = null; }); }
    }
  }

  Future<void> showJoinLectureDialog(Lecture lecture) async {
     final studentRegNum = widget.currentUser.registrationNumber;
    if (studentRegNum == null || studentRegNum.isEmpty) {
      _showErrorDialog('Action Failed', 'Your registration number is missing. Cannot join lecture.'); return;
    }
    if (_processingLectureId != null) return;

    final currentRecord = _summaryAttendanceRecords?.firstWhereOrNull((r) => r.lectureId == lecture.id);
    if (currentRecord != null) {
       showSnackBar(currentRecord.checkedIn ? 'You are already checked in for this lecture.' : 'You have already joined this lecture.', isError: false);
       return;
    }

    final confirmed = await showDialog<bool>(
      context: context, // Use the State's context
      barrierDismissible: false,
      builder: (BuildContext dialogContext) { // Use a different context name
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
          title: Text('Confirm Join: ${lecture.unitName}'),
          content: Column(
            mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('You are about to join this lecture using your registered number:'),
              const SizedBox(height: 10),
              InputChip(
                label: Text(studentRegNum, style: TextStyle(fontWeight: FontWeight.bold, color: brandColor)),
                avatar: Icon(Icons.badge_outlined, color: brandColor),
                backgroundColor: brandColor.withOpacity(0.1),
                side: BorderSide.none,
                isEnabled: false,
              ),
              const SizedBox(height: 15),
              Text('Date: ${lecture.formattedDate}'),
              Text('Time: ${lecture.formattedStartTime} - ${lecture.formattedEndTime}'),
              Row(
                children: [
                  const Text('Venue: '),
                  DocumentNameWidget(
                    collection: 'venues',
                    documentId: lecture.venue,
                  ),
                ],
              ),
              if (lecture.venue.toLowerCase() == 'online' && lecture.onlineLink != null && lecture.onlineLink!.isNotEmpty) ...[
                 const SizedBox(height: 8),
                 SelectableText(
                    'Link: ${lecture.onlineLink}',
                    style: TextStyle(color: Colors.blue.shade800),
                    maxLines: 1,
                 ),
              ]
            ],
          ),
          actionsPadding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          actions: [
            TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')),
            ElevatedButton.icon(
              icon: const Icon(Icons.login),
              label: const Text('Confirm Join'),
              style: ElevatedButton.styleFrom(backgroundColor: brandColor, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        );
      },
    );
    if (confirmed == true && mounted) { await _handleStudentJoin(lecture); }
  }

  // Scan QR and Check In
  Future<void> _scanLectureQrAndCheckIn() async {
     if (widget.currentUser.registrationNumber == null || widget.currentUser.registrationNumber!.isEmpty) {
       _showErrorDialog('Action Failed', 'Your registration number is missing. Cannot check in via QR.'); return;
    }
    if (_processingLectureId != null) return;

    final String? scannedLectureId = await Navigator.push<String>( context, MaterialPageRoute(builder: (context) => const QrScannerScreen()), );
    if (!mounted || scannedLectureId == null || scannedLectureId.isEmpty) {
        if (kDebugMode && scannedLectureId != null) print("QR Scan cancelled or returned empty lecture ID.");
        return;
    }

    if (kDebugMode) print("Scanned Lecture ID for Check-In: $scannedLectureId");

    // Frontend Time Check
    Lecture? scannedLecture;
    if (_lecturesStream != null) {
        try {
            final lectures = await _lecturesStream!.first;
            scannedLecture = lectures.firstWhereOrNull((l) => l.id == scannedLectureId);
        } catch (e) {
            if (kDebugMode) print("Error accessing lectures stream during QR scan check: $e");
        }
    }

    if (scannedLecture != null) {
        final lectureEndTime = scannedLecture.endTime;
        if (lectureEndTime != null && DateTime.now().isAfter(lectureEndTime)) {
            if (kDebugMode) print("Frontend Check: Lecture ${scannedLecture.unitName} has ended. Aborting check-in API call.");
            _showErrorDialog('Check-in Failed', 'Cannot check in: Lecture "${scannedLecture.unitName}" has already ended.');
            return;
        } else {
             if (kDebugMode) print("Frontend Check: Lecture ${scannedLecture.unitName} end time (${lectureEndTime ?? 'null'}) is in the future or null. Proceeding.");
        }
    } else {
        if (kDebugMode) print("Warning: Could not find lecture details locally for QR time check. Proceeding with API call (backend will verify time).");
    }

    // Proceed with API call
    setState(() { _processingLectureId = scannedLectureId; });
    try {
      await apiService.checkInViaLectureQr(scannedLectureId);
      if (!mounted) return;
      await _loadAttendanceSummary();

      String lectureName = scannedLecture?.unitName ?? "the lecture";
      showSnackBar('Successfully checked in for \'$lectureName\'!', isError: false);

    } catch (e) {
      if (!mounted) return;
      if (e is ApiException) {
          if (e.statusCode == 400 && e.message.toLowerCase().contains("lecture has already ended")) {
              _showErrorDialog('Check-in Failed', 'The lecture has already ended.');
          } else if (e.statusCode == 400 || e.statusCode == 404) {
              _showErrorDialog('Check-in Failed', 'You must join the lecture first before you can check in.');
          } else if (e.statusCode == 409) {
              showSnackBar('Check-in failed: You are already checked in.', isError: true);
              await _loadAttendanceSummary();
          } else {
              _showErrorDialog('QR Check-in Failed', e.message);
          }
      } else {
          _showErrorDialog('QR Check-in Failed', 'An unexpected error occurred. Please try again.');
      }
      if (kDebugMode) print("Error during checkInViaLectureQr API call: $e");
    } finally {
      if (mounted) { setState(() { _processingLectureId = null; }); }
    }
  }

  // --- UI Building ---

  Widget _buildShimmerLoading() {
    return ListView.builder(
      padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 80),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Card(
          margin: const EdgeInsets.symmetric(vertical: 6.0),
          elevation: 1.5,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
            child: Shimmer.fromColors(
              baseColor: Colors.grey.shade300,
              highlightColor: Colors.grey.shade100,
              child: Row(
                children: [
                  const CircleAvatar(backgroundColor: Colors.white, radius: 24),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(width: double.infinity, height: 16, color: Colors.white),
                        const SizedBox(height: 8),
                        Container(width: 150, height: 12, color: Colors.white),
                        const SizedBox(height: 8),
                        Container(width: 100, height: 12, color: Colors.white),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  Container(width: 60, height: 30, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15))),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // Summary Card
  Widget _buildAttendanceSummaryCard() {
    if (_isLoadingSummary) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 20.0, horizontal: 16.0),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: brandColor)),
      );
    }
    if (_summaryError != null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        color: Colors.red.shade50, elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade700),
              const SizedBox(width: 12),
              Expanded( child: Text( 'Could not load attendance summary: $_summaryError', style: TextStyle(color: Colors.red.shade900), ), ),
              IconButton( icon: Icon(Icons.refresh, color: Colors.red.shade700), tooltip: 'Retry Loading Summary', onPressed: _loadAttendanceSummary, padding: EdgeInsets.zero, constraints: const BoxConstraints(), )
            ],
          ),
        ),
      );
    }
    // Check if data is available AFTER loading and no error
    if (_attendancePercentage == null || _attendedLectures == null || _totalLectures == null) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), elevation: 1, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.info_outline, color: Colors.grey.shade500),
              const SizedBox(width: 10),
              Text( 'Attendance summary is currently unavailable.', style: TextStyle(color: Colors.grey.shade600), textAlign: TextAlign.center, ),
            ],
          ),
        ),
      );
    }

    // Calculate progress bar values
    double percentageValue = double.tryParse(_attendancePercentage!) ?? 0.0;
    double progressValue = (percentageValue / 100.0).clamp(0.0, 1.0);
    Color progressColor = percentageValue >= 75 ? Colors.green.shade600 : (percentageValue >= 50 ? Colors.orange.shade700 : Colors.red.shade600);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text( 'Attendance Summary (${_yearOfStudyName ?? fixedYearOfStudy} - ${_semesterName ?? fixedSemester})', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: brandColor), ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible( child: Text( _totalLectures == 0 ? '0 / 0 Lectures Attended' : '$_attendedLectures / $_totalLectures Lectures Attended', style: Theme.of(context).textTheme.bodyMedium, overflow: TextOverflow.ellipsis, ), ),
                const SizedBox(width: 10),
                _buildPercentageWidget(_attendancePercentage), // Use helper
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progressValue,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                minHeight: 8,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final textTheme = Theme.of(context).textTheme;
    final bool canPerformActions = widget.currentUser.registrationNumber != null &&
                                   widget.currentUser.registrationNumber!.isNotEmpty &&
                                   fixedYearOfStudy != null && fixedYearOfStudy!.isNotEmpty &&
                                   fixedSemester != null && fixedSemester!.isNotEmpty;

    return Scaffold(
      appBar: AppBar(
         title: Text('Student Dashboard - ${widget.currentUser.name}', style: const TextStyle(fontSize: 18)),
         backgroundColor: brandColor, foregroundColor: Colors.white, elevation: 2.0,
         actions: [
            if (_processingLectureId != null)
              const Padding( padding: EdgeInsets.only(right: 15.0), child: Center(child: SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))), ),
            IconButton(
              icon: Icon(Icons.refresh, color: canPerformActions ? Colors.white : Colors.white54),
              tooltip: 'Refresh Lectures & Summary',
              onPressed: canPerformActions && _processingLectureId == null ? () async { loadLectures(); await _loadAttendanceSummary(); } : null,
            ),
            IconButton(
              icon: const Icon(Icons.logout),
              tooltip: 'Logout',
              onPressed: (_processingLectureId != null) ? null : () async {
                 // Ensure context and builder are correctly passed
                 final confirm = await showDialog<bool>(
                    context: context, // Pass the current BuildContext
                    builder: (BuildContext dialogContext) { // Use a different context name
                      return AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        title: const Text('Confirm Logout'),
                        content: const Text('Are you sure you want to log out?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancel')), // Use dialogContext
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(true), // Use dialogContext
                            style: TextButton.styleFrom(foregroundColor: Colors.red),
                            child: const Text('Logout'),
                          ),
                        ],
                      );
                    } // End builder
                 ) ?? false; // Handle null case if dialog is dismissed
                 if (confirm && mounted) {
                    await authService.logout();
                    // Use context from the State for navigation
                    Navigator.pushAndRemoveUntil( context, MaterialPageRoute(builder: (context) => const WelcomeScreen()), (Route<dynamic> route) => false, );
                 }
              },
            ),
         ],
      ),
      floatingActionButton: canPerformActions ? FloatingActionButton.extended(
        onPressed: (_processingLectureId != null) ? null : _scanLectureQrAndCheckIn,
        label: const Text('Scan QR'),
        icon: const Icon(Icons.qr_code_scanner),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        tooltip: 'Scan Lecture QR Code to Check-In',
      ) : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      body: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canPerformActions) _buildAttendanceSummaryCard(),

              if (canPerformActions) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 8.0),
              child: Text( "Available Lectures", style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w500, color: brandColor), ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 4.0),
              child: Wrap(
                spacing: 8.0, runSpacing: 4.0,
                children: [                  
                  Chip(
                    label: DocumentNameWidget(
                      collection: 'years_of_study',
                      documentId: fixedYearOfStudy,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    backgroundColor: brandColor.withOpacity(0.1), side: BorderSide.none), // End children
                  Chip(
                    label: DocumentNameWidget(
                      collection: 'semesters',
                      documentId: fixedSemester,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    backgroundColor: brandColor.withOpacity(0.1), side: BorderSide.none),
                  Chip(
                    label: DocumentNameWidget(
                      collection: 'courses',
                      documentId: fixedCourse,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                    backgroundColor: Colors.grey.shade200, side: BorderSide.none),
                ], // End children
              ),
            ),
            const Divider(height: 1, indent: 16, endIndent: 16, thickness: 0.5),
          ],

          Expanded(
            child: canPerformActions
                ? RefreshIndicator(
                    color: brandColor,
                    onRefresh: () async { loadLectures(); await _loadAttendanceSummary(); }, // Keep manual refresh
                    child: StreamBuilder<List<Lecture>>( // Changed from FutureBuilder to StreamBuilder
                      stream: _lecturesStream,
                      builder: (context, snapshot) { // *** START OF FutureBuilder builder ***
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return _buildShimmerLoading();
                        }

                        // ***  ERROR HANDLING BLOCK ***
                        if (snapshot.hasError) {
                           // Log the error for debugging
                           final error = snapshot.error;
                           final stackTrace = snapshot.stackTrace;
                           if (kDebugMode) {
                             print("Error loading lectures: $error");
                             print("Stack trace: $stackTrace");
                           }
                           // Display a user-friendly error message
                           String displayMessage = 'Error loading lectures.';
                           if (error is ApiException) {
                             displayMessage = error.message; // Use message from ApiException
                           } else if (error is TimeoutException) {
                             displayMessage = 'Request timed out. Please check your connection.';
                           } else {
                             displayMessage = 'An unexpected error occurred.';
                           }

                           return Center(
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.cloud_off_outlined, color: Colors.orange.shade700, size: 48),
                                  const SizedBox(height: 10),
                                  Text(
                                    '$displayMessage\n(Year: $fixedYearOfStudy, Sem: $fixedSemester)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.grey.shade700),
                                  ),
                                  const SizedBox(height: 15),
                                  ElevatedButton.icon(
                                    icon: const Icon(Icons.refresh),
                                    label: const Text('Retry'),
                                    onPressed: loadLectures, // Retry loading lectures
                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                                  ),
                                   if (kDebugMode)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Text('\nDetails: $error', style: TextStyle(fontSize: 10, color: Colors.grey)),
                                    ),
                                ],
                              ),
                            )
                          );
                        }
                        // *** END  ERROR HANDLING BLOCK ***

                        if (!snapshot.hasData || snapshot.data!.isEmpty) {
                           return LayoutBuilder( builder: (context, constraints) {
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
                                        Icon(Icons.event_busy_outlined, size: 50, color: Colors.grey.shade400),
                                        const SizedBox(height: 10),
                                        Text( 'No lectures found for ${_yearOfStudyName ?? fixedYearOfStudy}, ${_semesterName ?? fixedSemester}.\nPull down to refresh.', textAlign: TextAlign.center, style: TextStyle(fontSize: 16, color: Colors.grey.shade600), ),
                                      ],
                                    )
                                  ),
                                ),
                              ),
                            );
                          });
                        }

                        // --- Success State ---
                        final allLectures = snapshot.data!;

                        // --- FILTERING LOGIC: Only show lectures for today ---
                        final now = DateTime.now();
                        final today = DateTime(now.year, now.month, now.day);

                        final todaysLectures = allLectures.where((lecture) {
                          if (lecture.lectureDate == null) return false;
                          // Normalize lectureDate to midnight for accurate comparison
                          final lectureDay = DateTime(lecture.lectureDate!.year, lecture.lectureDate!.month, lecture.lectureDate!.day);
                          return lectureDay.isAtSameMomentAs(today);
                        }).toList();

                        todaysLectures.sort((a, b) {
                           final aDate = a.lectureDate; final bDate = b.lectureDate;
                           if (aDate != null && bDate != null) {
                             int dateComp = aDate.compareTo(bDate);
                             if (dateComp != 0) return dateComp;
                           } else if (aDate == null && bDate != null) { return 1; }
                             else if (aDate != null && bDate == null) { return -1; }

                           final aTime = a.startTime; final bTime = b.startTime;
                           if (aTime != null && bTime != null) { return aTime.compareTo(bTime); }
                           else if (aTime == null && bTime != null) { return 1; }
                             else if (aTime != null && bTime == null) { return -1; }
                             else { return 0; }
                        });

                        return todaysLectures.isEmpty ? Center(
                          child: Text('No lectures scheduled for today.', style: TextStyle(fontSize: 16, color: Colors.grey.shade600)),
                        ) : ListView.builder(
                           physics: const AlwaysScrollableScrollPhysics(),
                           padding: const EdgeInsets.only(left: 12, right: 12, top: 8, bottom: 80), // Added bottom padding for FAB
                           itemCount: todaysLectures.length,
                           itemBuilder: (context, index) {
                              final lecture = todaysLectures[index];
                              final attendanceRecord = _summaryAttendanceRecords?.firstWhereOrNull((r) => r.lectureId == lecture.id);
                              final bool isJoined = attendanceRecord != null && !attendanceRecord.checkedIn;
                              final bool isCheckedIn = attendanceRecord != null && attendanceRecord.checkedIn;
                              final bool isCurrentlyProcessing = _processingLectureId == lecture.id;

                              final lectureEndTime = lecture.endTime;
                              final bool hasEnded = lectureEndTime != null && DateTime.now().isAfter(lectureEndTime);

                              return Card(
                                margin: const EdgeInsets.symmetric(vertical: 6.0),
                                elevation: 1.5,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 12.0, horizontal: 16.0),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start, // Align to top
                                    children: [
                                      // Use a builder to dynamically set the icon based on venue name
                                      DocumentNameWidget(
                                        collection: 'venues', documentId: lecture.venue,
                                        builder: (context, venueName) {
                                          final bool isOnline = venueName?.toLowerCase() == 'online';
                                          return CircleAvatar(
                                            backgroundColor: brandColor.withOpacity(0.1),
                                            child: Icon(
                                              (hasEnded && !isCheckedIn) ? Icons.event_busy_outlined :
                                              isCheckedIn ? Icons.check_circle_outline_rounded :
                                              (isJoined ? Icons.hourglass_bottom_rounded : (isOnline ? Icons.videocam_outlined : Icons.schedule_outlined)),
                                              color: (hasEnded && !isCheckedIn) ? Colors.grey.shade600 : brandColor, size: 24,
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${lecture.unitName} (${lecture.unitCode})',
                                              style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)
                                            ),
                                            const SizedBox(height: 4),
                                            Text('Lecturer: ${lecture.lecturerName}', style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3)),
                                            Text('${lecture.formattedDate} | ${lecture.formattedStartTime} - ${lecture.formattedEndTime}', style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3)),
                                            Row(
                                              children: [
                                                Text('Venue: ', style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3)),
                                                // Use DocumentNameWidget with a builder to show the link
                                                DocumentNameWidget(
                                                  collection: 'venues',
                                                  documentId: lecture.venue,
                                                  style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3),
                                                  builder: (context, venueName) {
                                                    final bool isOnline = venueName?.toUpperCase() == 'ONLINE';
                                                    final bool hasLink = lecture.onlineLink != null && lecture.onlineLink!.trim().isNotEmpty;

                                                    // If online with a link, show the link button
                                                    if (isOnline && hasLink) {
                                                      return Column(
                                                        crossAxisAlignment: CrossAxisAlignment.start,
                                                        children: [
                                                          Text(venueName ?? lecture.venue, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3)),
                                                          const SizedBox(height: 4),
                                                          TextButton.icon(
                                                            icon: Icon(Icons.open_in_browser_outlined, size: 18, color: brandColor),
                                                            label: Text('Open Online Link', style: TextStyle(fontSize: 13, color: brandColor, fontWeight: FontWeight.w500)),
                                                            style: TextButton.styleFrom(
                                                              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                              tapTargetSize: MaterialTapTargetSize.shrinkWrap, visualDensity: VisualDensity.compact, alignment: Alignment.centerLeft,
                                                            ),
                                                            // Show link if not ended, or if already checked in
                                                            onPressed: (_processingLectureId != null || (hasEnded && !isCheckedIn)) ? null : () => _launchURL(lecture.onlineLink!),
                                                          ),
                                                        ],
                                                      );
                                                    }
                                                    // Otherwise, just show the venue name
                                                    return Text(venueName ?? lecture.venue, style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700, height: 1.3));
                                                  },
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      // --- Trailing Widget Logic (No longer in an Expanded) ---
                                      if (hasEnded && !isCheckedIn)
                                        Chip(
                                          avatar: Icon(Icons.event_busy, size: 18, color: Colors.grey.shade700),
                                          label: Text('Ended', style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w500)),
                                          backgroundColor: Colors.grey.shade200,
                                          side: BorderSide.none,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        )
                                      else if (isCheckedIn)
                                        Chip(
                                          avatar: Icon(Icons.check_circle, size: 18, color: Colors.green.shade800),
                                          label: Text('Checked In', style: TextStyle(color: Colors.green.shade900, fontWeight: FontWeight.w500)),
                                          backgroundColor: Colors.green.shade100,
                                          side: BorderSide.none,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        )
                                      else if (isJoined)
                                        Chip(
                                          avatar: Icon(Icons.hourglass_bottom_rounded, size: 18, color: Colors.orange.shade800),
                                          label: Text('Joined', style: TextStyle(color: Colors.orange.shade900, fontWeight: FontWeight.w500)),
                                          backgroundColor: Colors.orange.shade100,
                                          side: BorderSide.none,
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        )
                                      else // Not joined, not checked in, not ended
                                        ElevatedButton(
                                          onPressed: (_processingLectureId != null || !canPerformActions) ? null : () => showJoinLectureDialog(lecture),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: brandColor,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                            textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                            minimumSize: const Size(80, 36),
                                          ),
                                          child: isCurrentlyProcessing
                                              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                              : const Text('Join'),
                                        ),
                                    ],
                                  ),
                                ),
                              );
                           },
                        );
                      }, // *** END OF FutureBuilder builder ***
                    ),
                  )
                : Center( // Placeholder when canPerformActions is false
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 50,
                            color: Colors.orange.shade600,
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'Cannot load lectures.\nYour profile might be incomplete (missing registration number, year, or semester).\nPlease contact support.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
            ],
          ),
          // --- AD BANNER WIDGET ---
          if (_bannerAd != null && _isBannerAdLoaded)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: SlideTransition(
                position: _offsetAnimation,
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                    child: Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.7),
                        border: Border(
                          top: BorderSide(color: Colors.white.withOpacity(0.5), width: 1.5),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, -5),
                          ),
                        ],
                      ),
                      child: SafeArea(
                        top: false,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8.0),
                              child: SizedBox(
                                width: _bannerAd!.size.width.toDouble(),
                                height: _bannerAd!.size.height.toDouble(),
                                child: AdWidget(ad: _bannerAd!),
                              ),
                            ),
                            Positioned(
                              right: 16,
                              top: 0,
                              bottom: 0,
                              child: Center(
                                child: IconButton(
                                  icon: const Icon(Icons.close, size: 20, color: Colors.black54),
                                  onPressed: _dismissAd,
                                  tooltip: 'Close',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}