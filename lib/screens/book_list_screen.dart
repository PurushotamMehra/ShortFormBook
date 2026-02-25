import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/reading_settings.dart';
import '../services/reading_settings_service.dart';
import '../services/book_import_service.dart';
import '../services/book_metadata_service.dart';
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
  final BookMetadataService _metadataService = BookMetadataService();
  final ReadingSettingsService _settingsService = ReadingSettingsService();

  bool _loading = true;
  List<File> _books = [];
  ReadingSettings _settings = const ReadingSettings();

  @override
  void initState() {
    super.initState();
    _refreshLibrary();
  }

  Future<void> _refreshLibrary() async {
    setState(() => _loading = true);

    // Load Settings
    final s = await _settingsService.loadSettings();
    setState(() => _settings = s);

    await _metadataService.init();
    final books = await _library.getLocalBooks();

    // Ensure metadata exists for all books
    for (final file in books) {
      final bookId = p.basename(file.path);
      if (_metadataService.getMetadata(bookId) == null) {
        await _metadataService.extractAndCacheMetadata(file);
      }
    }

    // Sort by lastReadTime descending
    books.sort((a, b) {
      final metaA = _metadataService.getMetadata(p.basename(a.path));
      final metaB = _metadataService.getMetadata(p.basename(b.path));
      final timeA = metaA?.lastReadTime ?? 0;
      final timeB = metaB?.lastReadTime ?? 0;
      return timeB.compareTo(timeA);
    });

    if (mounted) {
      setState(() {
        _books = books;
        _loading = false;
      });
    }
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
      builder: (_) => Center(
        child: Card(
          color: _settings.menuColor,
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(color: Color(0xFFE85D04)),
                const SizedBox(height: 16),
                Text(
                  'Parsing book…',
                  style: TextStyle(color: _settings.textColor, fontSize: 14),
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

      await Navigator.push(
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

      // Re-sort and refresh UI when returning from reading
      _refreshLibrary();
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
      backgroundColor: _settings.backgroundColor,
      appBar: AppBar(
        title: const Text('My Books'),
        centerTitle: true,
        backgroundColor: _settings.menuColor,
        foregroundColor: _settings.textColor,
        elevation: 0,
        iconTheme: IconThemeData(color: _settings.textColor),
      ),
      drawer: Drawer(
        backgroundColor: _settings.menuColor,
        child: Column(
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: _settings.backgroundColor),
              child: Container(
                width: double.infinity,
                alignment: Alignment.bottomLeft,
                child: Text(
                  'FlowRead',
                  style: TextStyle(
                    color: _settings.textColor,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            ListTile(
              leading: Icon(Icons.palette, color: _settings.textColor),
              title: Text(
                'Themes',
                style: TextStyle(color: _settings.textColor),
              ),
              onTap: () {
                Navigator.pop(context);
                _showThemesBottomModal();
              },
            ),
            ListTile(
              leading: Icon(Icons.library_books, color: _settings.textColor),
              title: Text(
                'Finished Books',
                style: TextStyle(color: _settings.textColor),
              ),
              onTap: () {
                // Placeholder
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: Icon(Icons.person, color: _settings.textColor),
              title: Text(
                'Authors',
                style: TextStyle(color: _settings.textColor),
              ),
              onTap: () {
                // Placeholder
                Navigator.pop(context);
              },
            ),
          ],
        ),
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

  void _showThemesBottomModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return Container(
              decoration: BoxDecoration(
                color: _settings.menuColor,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 24,
                    horizontal: 16,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'GLOBAL APP THEME',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.2,
                          color: _settings.mutedColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: AppTheme.values.map((theme) {
                            final isSelected = _settings.appTheme == theme;
                            final themeName = theme.name
                                .toUpperCase()
                                .replaceAll('SOFTLIGHT', 'SOFT LIGHT');

                            final dummySettings = ReadingSettings(
                              appTheme: theme,
                            );
                            final chipBgColor = dummySettings.backgroundColor;
                            final chipTextColor = dummySettings.textColor;

                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  themeName,
                                  style: TextStyle(
                                    color: chipTextColor,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: chipBgColor,
                                backgroundColor: chipBgColor,
                                showCheckmark: false,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isSelected
                                        ? const Color(0xFFE85D04)
                                        : Colors.grey.withValues(alpha: 0.3),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                onSelected: (val) {
                                  if (val) {
                                    final updated = _settings.copyWith(
                                      appTheme: theme,
                                    );
                                    setState(() => _settings = updated);
                                    _settingsService.saveSettings(updated);
                                    setModalState(() {});
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: Color(0xFFE85D04)),
      );
    }

    if (_books.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_rounded, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              'No books yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: _settings.textColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Import an EPUB to begin reading',
              style: TextStyle(fontSize: 14, color: _settings.mutedColor),
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
    final bookId = p.basename(file.path);
    final metadata = _metadataService.getMetadata(bookId);

    final title = metadata?.title ?? bookId.replaceAll('.epub', '');
    final author = metadata?.author ?? 'Unknown Author';
    final coverPath = metadata?.coverImagePath;

    final progress = (metadata != null && metadata.totalChunks > 0)
        ? (metadata.lastReadIndex / metadata.totalChunks).clamp(0.0, 1.0)
        : 0.0;

    return GestureDetector(
      onTap: () => _openBook(file),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _settings.menuColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            if (coverPath != null && File(coverPath).existsSync())
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.file(
                  File(coverPath),
                  width: 48,
                  height: 64,
                  fit: BoxFit.cover,
                  cacheWidth: 96, // decode at 2x for quality, saves memory
                ),
              )
            else
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _settings.textColor,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    author,
                    style: TextStyle(fontSize: 14, color: _settings.mutedColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 32,
              height: 32,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 4,
                backgroundColor: _settings.mutedColor.withValues(alpha: 0.2),
                color: const Color(0xFFE85D04),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
