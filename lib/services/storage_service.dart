import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

/// Uploads a file to Firebase Storage and returns the download URL.
  Future<String?> uploadFile(String path, String fileName, Uint8List file) async {
    try {
      Reference ref = _storage.ref().child(path).child(fileName);
      SettableMetadata metadata = SettableMetadata(contentType: 'application/octet-stream');
      UploadTask uploadTask = ref.putData(file, metadata);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();
      print('File uploaded successfully: $downloadUrl');
      return downloadUrl;
    } on FirebaseException catch (e) {
      print('Firebase Storage Error uploading file: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('Error uploading file: $e');
      return null;
    }
  }

  Future<void> deleteFile(String fileUrl) async {
    try {
      Reference ref = _storage.refFromURL(fileUrl);
      await ref.delete();
      print('File deleted successfully: $fileUrl');
    } on FirebaseException catch (e) {
      print('Firebase Storage Error deleting file: ${e.code} - ${e.message}');
      if (e.code == 'object-not-found') {
        print('File to delete was not found.');
      }
    } catch (e) {
      print('Error deleting file: $e');
    }
  }

  Future<Uint8List?> downloadFile(String fileUrl) async {
    try {
      Reference ref = _storage.refFromURL(fileUrl);
      const oneMegabyte = 1024 * 1024;
      final Uint8List? data = await ref.getData(oneMegabyte * 5);
      print('File downloaded successfully: $fileUrl');
      return data;
    } on FirebaseException catch (e) {
      print('Firebase Storage Error downloading file: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      print('Error downloading file: $e');
      return null;
    }
  }
}
