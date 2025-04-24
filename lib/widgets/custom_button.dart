// lib/widgets/custom_button.dart
import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final VoidCallback? onPressed; // Allow null for disabled state
  final String text;
  final Color? color;
  final Color? textColor;
  final double? width; // Optional width
  final double? height; // Optional height
  final Widget? icon; // Optional icon
  final bool isLoading; // Add loading state
  final double borderRadius; // Allow customizing border radius

  // Define the brand color locally or import from a constants file
  static const Color brandColor = Color(0xFF0175C2);

  const CustomButton({
    super.key,
    required this.onPressed,
    required this.text,
    this.color, // If provided, overrides brandColor
    this.textColor, // If provided, overrides white
    this.width,
    this.height = 52.0, // Match standard height
    this.icon,
    this.isLoading = false, // Default to not loading
    this.borderRadius = 30.0, // Match standard rounded corners
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final effectiveBackgroundColor = color ?? brandColor;
    final effectiveForegroundColor = textColor ?? Colors.white;

    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: effectiveBackgroundColor,
      foregroundColor: effectiveForegroundColor,
      minimumSize: Size(width ?? double.infinity, height ?? 52), // Default to full width
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12), // Standard padding
      textStyle: textTheme.titleMedium?.copyWith( // Consistent text style
        fontWeight: FontWeight.bold,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(borderRadius), // Use parameter or default
      ),
      elevation: 3, // Subtle elevation
      // Handle disabled state visually
      disabledBackgroundColor: effectiveBackgroundColor.withOpacity(0.5),
      disabledForegroundColor: effectiveForegroundColor.withOpacity(0.7),
    );

    // Determine the child widget based on loading state and icon presence
    Widget buttonChild;
    if (isLoading) {
      buttonChild = SizedBox(
        width: 24, // Standard size for indicator
        height: 24,
        child: CircularProgressIndicator(
          strokeWidth: 2.5,
          valueColor: AlwaysStoppedAnimation<Color>(effectiveForegroundColor),
        ),
      );
    } else if (icon != null) {
      // If icon is provided, use ElevatedButton.icon structure internally
      //  ElevatedButton.icon handles spacing automatically
      buttonChild = Row(
        mainAxisSize: MainAxisSize.min, // Don't stretch row
        children: [
          icon!,
          const SizedBox(width: 8), // Spacing between icon and text
          Text(text),
        ],
      );
    } else {
      buttonChild = Text(text);
    }

    return ElevatedButton(
      onPressed: isLoading ? null : onPressed, // Disable button when loading or if onPressed is null
      style: buttonStyle,
      child: buttonChild,
    );
  }
}
