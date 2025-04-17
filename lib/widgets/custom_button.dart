import 'package:flutter/material.dart';

class CustomButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String text;
  final Color? color;
  final Color? textColor;
  final double? width; // Optional width
  final double? height; // Optional height
  final Widget? icon; // Optional icon

  const CustomButton({
    super.key, // Use super.key
    required this.onPressed,
    required this.text,
    this.color,
    this.textColor,
    this.width,
    this.height = 48.0, // Default height
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final buttonStyle = ElevatedButton.styleFrom(
      backgroundColor: color ?? Theme.of(context).primaryColor,
      foregroundColor: textColor ?? Colors.white,
      minimumSize: Size(width ?? 88, height ?? 48), // Use width/height or defaults
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), // Adjusted padding
      textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500), // Adjusted style
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8), // Slightly smaller radius
      ),
      elevation: 2, // Add subtle elevation
    );

    // Use ElevatedButton.icon if icon is provided
    return icon != null
      ? ElevatedButton.icon(
          onPressed: onPressed,
          style: buttonStyle,
          icon: icon!,
          label: Text(text),
        )
      : ElevatedButton(
          onPressed: onPressed,
          style: buttonStyle,
          child: Text(text),
        );
  }
}
