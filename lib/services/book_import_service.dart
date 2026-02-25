import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Service for importing EPUB files into internal app storage.
class BookImportService {
  /// Opens the system file picker, lets the user select an .epub file,
  /// and copies it into the internal books directory.
  ///
  /// Returns the local [File] on success, or `null` if the user cancelled
  /// or an error occurred.
  Future<File?> importBook() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['epub'],
      );

      if (result == null || result.files.isEmpty) {
        return null; // User cancelled.
      }

      final pickedFile = result.files.single;
      final sourcePath = pickedFile.path;

      if (sourcePath == null) {
        return null; // No file path available.
      }

      // Get the internal books directory.
      final booksDir = await _getBooksDirectory();
      if (!await booksDir.exists()) {
        await booksDir.create(recursive: true);
      }

      // Build the destination path.
      final fileName = p.basename(sourcePath);
      final destPath = p.join(booksDir.path, fileName);

      // Prevent duplicate imports.
      final destFile = File(destPath);
      if (await destFile.exists()) {
        return destFile; // Already imported.
      }

      // Copy the file into internal storage.
      final sourceFile = File(sourcePath);
      return await sourceFile.copy(destPath);
    } catch (e) {
      // Log error only — no dialogs needed.
      // ignore: avoid_print
      print('BookImportService: import failed — $e');
      return null;
    }
  }

  /// Returns the internal books directory.
  Future<Directory> _getBooksDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    return Directory(p.join(appDir.path, 'books'));
  }
}
