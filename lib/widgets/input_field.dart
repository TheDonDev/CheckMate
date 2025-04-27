// lib/widgets/input_field.dart
import 'package:flutter/material.dart';

class InputField extends StatelessWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText; // Optional hint text
  final TextInputType keyboardType;
  final bool obscureText;
  final Widget? prefixIcon; // Optional prefix icon
  final Widget? suffixIcon; // Optional suffix icon
  final FormFieldValidator<String>? validator; // Optional validator
  final ValueChanged<String>? onChanged; // Optional onChanged callback
  final int? maxLines; // Optional maxLines

  // Define the brand color locally or import from a constants file
  static const Color brandColor = Color(0xFF0175C2);

  const InputField({
    super.key,
    required this.controller,
    required this.labelText,
    this.hintText,
    this.keyboardType = TextInputType.text,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.onChanged,
    this.maxLines = 1, // Default to single line
  });

  @override
  Widget build(BuildContext context) {
    // consistent InputDecoration style
    final inputDecoration = InputDecoration(
      labelText: labelText,
      hintText: hintText,
      // Apply themed color to prefix icon if provided
      prefixIcon: prefixIcon != null
          ? IconTheme(
              data: IconThemeData(color: brandColor.withOpacity(0.7)),
              child: prefixIcon!,
            )
          : null,
      suffixIcon: suffixIcon, // Suffix icon usually handles its own color (like visibility toggle)
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        // Define borderSide if needed
        // borderSide: BorderSide(color: Colors.grey.shade400),
      ),
      enabledBorder: OutlineInputBorder( // Style for normal state
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      focusedBorder: OutlineInputBorder( // Style when focused
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: brandColor, width: 1.5), // Highlight with brand color
      ),
      filled: true,
      fillColor: Colors.grey[100], // Subtle background fill
      contentPadding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
    );

    return TextFormField( // TextFormField for validation
      controller: controller,
      decoration: inputDecoration,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator, // Pass validator
      onChanged: onChanged, // Pass onChanged
      maxLines: obscureText ? 1 : maxLines, // Ensure password fields are single line
    );
  }
}
