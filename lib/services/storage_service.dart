import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  /// Uploads a file (Uint8List) to Firebase Storage.
  ///
  /// [path]: The folder path in the bucket (e.g., 'user_avatars').
  /// [fileName]: The desired name for the file in storage.
  /// [file]: The file content as Uint8List.
  /// Returns the download URL upon successful upload, or null on failure.
  Future<String?> uploadFile(String path, String fileName, Uint8List file) async {
    try {
      // Create a reference to the location you want to upload to
      Reference ref = _storage.ref().child(path).child(fileName);

      // Upload the file via putData
      UploadTask uploadTask = ref.putData(file);

      // Await the task to complete
      TaskSnapshot snapshot = await uploadTask;

      // Get the download URL
      String downloadUrl = await snapshot.ref.getDownloadURL();
      print('File uploaded successfully: $downloadUrl');
      return downloadUrl;

    } on FirebaseException catch (e) {
      // Handle Firebase specific errors
      print('Firebase Storage Error uploading file: ${e.code} - ${e.message}');
      return null;
    } catch (e) {
      // Handle other errors
      print('Error uploading file: $e');
      return null;
    }
  }

  /// Deletes a file from Firebase Storage using its download URL.
  ///
  /// [fileUrl]: The full download URL of the file to delete.
  Future<void> deleteFile(String fileUrl) async {
    try {
      // Get reference from the URL
      Reference ref = _storage.refFromURL(fileUrl);

      // Delete the file
      await ref.delete();
      print('File deleted successfully: $fileUrl');

    } on FirebaseException catch (e) {
      // Handle errors, e.g., object-not-found, unauthorized
      print('Firebase Storage Error deleting file: ${e.code} - ${e.message}');
      // Optionally re-throw or handle specific codes
      if (e.code == 'object-not-found') {
        print('File to delete was not found.');
      }
    } catch (e) {
      print('Error deleting file: $e');
    }
  }

  /// Downloads a file from Firebase Storage as Uint8List using its download URL.
  ///
  /// [fileUrl]: The full download URL of the file to download.
  /// Returns the file data as Uint8List, or null on failure.
  Future<Uint8List?> downloadFile(String fileUrl) async {
    try {
      // Get reference from the URL
      Reference ref = _storage.refFromURL(fileUrl);

      // Get the data (consider size limits with getData)
      // For large files, consider downloadToFile or getDownloadURL + http package
      const oneMegabyte = 1024 * 1024;
      final Uint8List? data = await ref.getData(oneMegabyte * 5); // Example: Limit to 5MB

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
