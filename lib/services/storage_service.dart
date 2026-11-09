// lib/services/storage_service.dart
import 'dart:typed_data';

class StorageService {
  Future<String?> uploadFile(String path, String fileName, Uint8List file) async {
    throw UnsupportedError('File storage is not available in local development mode.');
  }

  Future<void> deleteFile(String fileUrl) async {
    throw UnsupportedError('File storage is not available in local development mode.');
  }

  Future<Uint8List?> downloadFile(String fileUrl) async {
    throw UnsupportedError('File storage is not available in local development mode.');
  }
}
