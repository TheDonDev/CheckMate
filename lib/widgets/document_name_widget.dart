import 'package:checkmate/services/admin_service.dart';
import 'package:flutter/material.dart';

// A builder function that receives the context and the fetched name (String?)
typedef DocumentNameBuilder = Widget Function(BuildContext context, String? name);

class DocumentNameWidget extends StatelessWidget {
  final String collection;
  final String? documentId;
  final TextStyle? style;
  final DocumentNameBuilder? builder; // Optional custom builder

  const DocumentNameWidget({
    super.key,
    required this.collection,
    required this.documentId,
    this.style,
    this.builder,
  });

  @override
  Widget build(BuildContext context) {
    // Use a singleton or provided instance of AdminService if available
    final AdminService adminService = AdminService();

    if (documentId == null || documentId!.isEmpty) {
      // If a builder is provided, call it with null, otherwise return default text
      if (builder != null) {
        return builder!(context, 'N/A');
      }
      return Text('N/A', style: style); // Default behavior
    }

    return FutureBuilder<String>(
      future: adminService.getDocumentName(collection, documentId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          // Return a small placeholder or loading indicator
          if (builder != null) {
            return builder!(context, '...');
          }
          return Text('...', style: style); // Default behavior
        }
        // On error or success, get the data or a fallback
        final String name = snapshot.hasError ? 'Error' : (snapshot.data ?? documentId!);

        // If a builder is provided, use it to build the widget
        if (builder != null) {
          return builder!(context, name);
        }
        // Otherwise, return the default Text widget
        return Text(name, style: snapshot.hasError ? style?.copyWith(color: Colors.red) : style);
      },
    );
  }
}