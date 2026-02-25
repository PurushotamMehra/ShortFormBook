import 'dart:convert';
import 'dart:io';

import 'package:epubx/epubx.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/book_metadata.dart';

/// Service managing persistent metadata for all imported books.
/// Creates a cached JSON registry and extracts cover images.
class BookMetadataService {
  // Singleton pattern
  static final BookMetadataService _instance = BookMetadataService._internal();

  factory BookMetadataService() {
    return _instance;
  }

  BookMetadataService._internal();

  static const String _metadataFileName = 'books_metadata.json';
  static const String _coversDirName = 'covers';

  Map<String, BookMetadata> _cache = {};
  bool _initialized = false;

  /// Ensure metadata registry is loaded into memory
  Future<void> init() async {
    if (_initialized) return;

    final file = await _getMetadataFile();
    if (await file.exists()) {
      try {
        final content = await file.readAsString();
        final Map<String, dynamic> data = json.decode(content);
        _cache = data.map(
          (key, value) => MapEntry(key, BookMetadata.fromMap(value)),
        );
      } catch (e) {
        debugPrint('BookMetadataService: Failed to load metadata: $e');
        _cache = {};
      }
    }
    _initialized = true;
  }

  /// Get metadata for a specific book ID (filename)
  BookMetadata? getMetadata(String bookId) {
    return _cache[bookId];
  }

  /// Update metadata for a book inside the cache (e.g. updating progress)
  Future<void> updateMetadata(BookMetadata metadata) async {
    _cache[metadata.id] = metadata;
    await _save();
  }

  /// Get all metadata sorted by lastReadTime descending
  List<BookMetadata> getAllSortedByLastRead() {
    final list = _cache.values.toList();
    list.sort((a, b) => b.lastReadTime.compareTo(a.lastReadTime));
    return list;
  }

  /// Extract metadata and cover image natively from an EPUB File
  /// Fallbacks to generating a clean filename if real title is not present.
  Future<BookMetadata> extractAndCacheMetadata(File epubFile) async {
    final bookId = p.basename(epubFile.path);
    final bytes = await epubFile.readAsBytes();
    final book = await EpubReader.readBook(bytes);

    String title = book.Title ?? '';
    if (title.isEmpty) {
      title = _cleanFileName(bookId);
    }

    final author = book.Author ?? 'Unknown Author';

    String? coverPath;
    final coverImage = book.CoverImage;
    if (coverImage != null) {
      // Save it locally
      final coversDir = await _getCoversDirectory();
      if (!await coversDir.exists()) {
        await coversDir.create(recursive: true);
      }
      final outPath = p.join(coversDir.path, '${bookId}_cover.png');
      final outFile = File(outPath);
      // Determine what format Image is, typically Image from package:image doesn't save raw png unless we encode it.
      // Easiest is to see if we can get byte content directly from EpubBook content.
      try {
        final coverKey = book.Content?.Images?.keys.firstWhere(
          (k) => k.toLowerCase().contains('cover'),
          orElse: () => '',
        );
        if (coverKey != null && coverKey.isNotEmpty) {
          final coverBytes = book.Content?.Images?[coverKey]?.Content;
          if (coverBytes != null) {
            await outFile.writeAsBytes(coverBytes);
            coverPath = outPath;
          }
        }
      } catch (e) {
        debugPrint('Failed to extract raw cover for $bookId: $e');
      }
    }

    final newMeta = BookMetadata(
      id: bookId,
      title: title,
      author: author,
      coverImagePath: coverPath,
      lastReadTime: DateTime.now().millisecondsSinceEpoch,
    );

    await updateMetadata(newMeta);
    return newMeta;
  }

  // --- Helpers ---

  Future<File> _getMetadataFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, _metadataFileName));
  }

  Future<Directory> _getCoversDirectory() async {
    final dir = await getApplicationDocumentsDirectory();
    return Directory(p.join(dir.path, _coversDirName));
  }

  Future<void> _save() async {
    final file = await _getMetadataFile();
    final data = _cache.map((key, value) => MapEntry(key, value.toMap()));
    await file.writeAsString(json.encode(data));
  }

  /// Cleans obscure filenames into presentable titles
  /// Example: "the_great_gatsby_v2.epub" -> "The Great Gatsby V2"
  String _cleanFileName(String filename) {
    var name = filename.replaceAll('.epub', '');
    // remove stuff in brackets
    name = name.replaceAll(RegExp(r'\[.*?\]'), '');
    name = name.replaceAll(RegExp(r'\(.*?\)'), '');
    name = name.replaceAll('_', ' ');
    name = name.replaceAll('-', ' ');
    name = name.trim();

    // Capitalize words
    if (name.isEmpty) return 'Unknown Title';
    return name
        .split(' ')
        .map((word) {
          if (word.isEmpty) return word;
          return word[0].toUpperCase() + word.substring(1);
        })
        .join(' ');
  }
}
