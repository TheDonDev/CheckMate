import 'package:flutter/material.dart';
// Optional: Import your payment service if you have one
// import 'package:checkmate/services/payment_service.dart';
// Optional: Import user model if needed to tailor messages
// import 'package:checkmate/models/app_user.dart' as app_user;

class UpgradeScreen extends StatefulWidget {
  // Optional: Pass the current user if you need to tailor messages
  // final app_user.User currentUser;
  // const UpgradeScreen({super.key, required this.currentUser});

  const UpgradeScreen({super.key}); // Simpler constructor if user isn't needed

  @override
  State<UpgradeScreen> createState() => _UpgradeScreenState();
}

class _UpgradeScreenState extends State<UpgradeScreen> {
  static const Color brandColor = Color(0xFF0175C2);
  static const Color premiumColor = Colors.amber; // Color for premium elements

  bool _isProcessingPayment = false;

  // --- Placeholder for Payment Logic ---
  Future<void> _initiatePayment() async {
    if (_isProcessingPayment) return;

    setState(() {
      _isProcessingPayment = true;
    });

    // TODO: Implement payment gateway integration (M-Pesa STK Push, Stripe, etc.)
    // 1. Call your backend/payment service to initiate the transaction for KES 300.
    // 2. Handle the response from the payment gateway.
    // 3. If successful:
    //    - Update the user's status to premium on your backend.
    //    - Update the local user state (e.g., using Provider/AuthService).
    //    - Show a success message.
    //    - Navigate back to the dashboard (maybe pop until dashboard or pushReplacement).
    // 4. If failed:
    //    - Show an error message to the user.

    // --- Example Placeholder ---
    await Future.delayed(const Duration(seconds: 3)); // Simulate network call
    // Simulate success/failure
    bool paymentSuccess = true; // Change this to test failure

    if (!mounted) return; // Check if widget is still in the tree

    if (paymentSuccess) {
      // --- Simulate updating user status (Replace with actual logic) ---
      // Example: await Provider.of<AuthService>(context, listen: false).updateUserPremiumStatus(true);

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Upgrade Successful! Welcome to Premium.'),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      // Navigate back to the dashboard, potentially forcing a refresh
      // Option 1: Just pop
      // Navigator.of(context).pop(true); // Pass true to indicate success
      // Option 2: Pop until the dashboard (if you know its route name)
      // Navigator.of(context).popUntil(ModalRoute.withName('/dashboard')); // Adjust route name
      // Option 3: Replace the current screen (less common for upgrades)
      // Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => Dashboard(...)));
      Navigator.of(context).pop(true); // Simple pop, dashboard should refresh on resume/rebuild

    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment Failed. Please try again or contact support.'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    // --- End Example Placeholder ---

    if (mounted) {
      setState(() {
        _isProcessingPayment = false;
      });
    }
  }
  // --- End Payment Logic Placeholder ---


  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Upgrade to Premium'),
        backgroundColor: brandColor,
        foregroundColor: Colors.white,
        elevation: 2.0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch, // Make children stretch horizontally
          children: [
            // 1. Premium Icon
            Icon(
              Icons.workspace_premium_rounded,
              size: 80,
              color: premiumColor,
            ),
            const SizedBox(height: 16.0),

            // 2. Main Headline
            Text(
              'Unlock All Features!',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: brandColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8.0),
            Text(
              'Get unlimited access with CheckMate Premium.',
              style: textTheme.titleMedium?.copyWith(color: Colors.grey.shade700),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24.0),

            // 3. Price Box
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
              decoration: BoxDecoration(
                color: brandColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12.0),
                border: Border.all(color: brandColor.withOpacity(0.3)),
              ),
              child: Column(
                children: [
                  Text(
                    'One-Time Payment',
                    style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: brandColor),
                  ),
                  const SizedBox(height: 8.0),
                  Text(
                    'KES 300',
                    style: textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: brandColor,
                    ),
                  ),
                  const SizedBox(height: 4.0),
                  Text(
                    '(Pay once, enjoy forever)',
                    style: textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32.0),

            // 4. Benefits List
            Text(
              'Premium Benefits:',
              style: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12.0),
            _buildBenefitItem(
              icon: Icons.list_alt_rounded,
              text: 'View ALL available lectures (Students)',
            ),
            _buildBenefitItem(
              icon: Icons.add_circle_outline_rounded,
              text: 'Create UNLIMITED lectures (Lecturers)',
            ),
            _buildBenefitItem(
              icon: Icons.history_rounded,
              text: 'Access full attendance history (Coming Soon)', // Example future benefit
            ),
             _buildBenefitItem(
              icon: Icons.support_agent_rounded,
              text: 'Priority support', // Example future benefit
            ),
            const SizedBox(height: 32.0),

            // 5. Call to Action Button
            ElevatedButton.icon(
              icon: _isProcessingPayment
                  ? Container( // Replace icon with spinner
                      width: 20,
                      height: 20,
                      padding: const EdgeInsets.all(2.0),
                      child: const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Icon(Icons.lock_open_rounded), // Or Icons.payment_rounded
              label: Text(
                _isProcessingPayment ? 'Processing Payment...' : 'Upgrade Now & Pay KES 300',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amber[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(30.0), // More rounded
                ),
                elevation: 3,
              ),
              onPressed: _isProcessingPayment ? null : _initiatePayment, // Disable while processing
            ),
            const SizedBox(height: 12.0),

            // 6. Payment Method Info (Optional)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.security_rounded, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 6.0),
                Text(
                  'Secure payment via M-Pesa or Card.', // Adjust as needed
                  style: textTheme.bodySmall?.copyWith(color: Colors.grey.shade700),
                ),
              ],
            ),
            const SizedBox(height: 24.0), // Bottom padding
          ],
        ),
      ),
    );
  }

  // Helper widget for benefit items
  Widget _buildBenefitItem({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.green.shade600, size: 22),
          const SizedBox(width: 12.0),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
