import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../services/book_import_service.dart';
import '../services/epub_parser.dart';
import '../services/library_service.dart';
import 'reader_screen.dart';

/// Screen 1 — displays the list of available books + import button.
class BookListScreen extends StatefulWidget {
  const BookListScreen({super.key});

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  final LibraryService _library = LibraryService();
  final BookImportService _importer = BookImportService();
  final EpubParserService _parser = EpubParserService();

  bool _loading = true;
  List<File> _books = [];

  @override
  void initState() {
    super.initState();
    _refreshLibrary();
  }

  Future<void> _refreshLibrary() async {
    setState(() => _loading = true);
    final books = await _library.getLocalBooks();
    setState(() {
      _books = books;
      _loading = false;
    });
  }

  Future<void> _importBook() async {
    final imported = await _importer.importBook();
    if (imported != null) {
      await _refreshLibrary();
    }
  }

  Future<void> _openBook(File file) async {
    // Show a loading indicator while parsing.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: Color(0xFF2C2C2C)),
                SizedBox(height: 16),
                Text(
                  'Parsing book…',
                  style: TextStyle(color: Color(0xFF757575), fontSize: 14),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final result = await _parser.loadAndParseFromFile(file);

      if (!mounted) return;
      Navigator.pop(context); // dismiss loading dialog

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReaderScreen(
            title: result.title,
            bookId: p.basename(file.path),
            chunks: result.chunks,
            anchorMap: result.anchorMap,
            chapters: result.chapters,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context); // dismiss loading dialog

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to open book: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFAF8F5),
      appBar: AppBar(
        title: const Text('My Books'),
        centerTitle: true,
        backgroundColor: const Color(0xFFFAF8F5),
        foregroundColor: const Color(0xFF2C2C2C),
        elevation: 0,
      ),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _importBook,
        backgroundColor: const Color(0xFFE85D04),
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Import EPUB'),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFF2C2C2C)),
      );
    }

    if (_books.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book_rounded, size: 64, color: Color(0xFFBDBDBD)),
            SizedBox(height: 16),
            Text(
              'No books yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2C2C2C),
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Import an EPUB to begin reading',
              style: TextStyle(fontSize: 14, color: Color(0xFF9E9E9E)),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      itemCount: _books.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) => _buildBookCard(_books[index]),
    );
  }

  Widget _buildBookCard(File file) {
    final fileName = p.basename(file.path).replaceAll('.epub', '');

    return GestureDetector(
      onTap: () => _openBook(file),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFF4A6741),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.menu_book_rounded,
                color: Colors.white,
                size: 24,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                fileName,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2C2C2C),
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.chevron_right, color: Color(0xFFBDBDBD)),
          ],
        ),
      ),
    );
  }
}
