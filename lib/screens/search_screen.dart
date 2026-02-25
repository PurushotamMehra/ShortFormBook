import 'package:flutter/material.dart';

import '../models/book_chunk.dart';
import '../models/reading_settings.dart';
import '../services/reading_settings_service.dart';

class SearchScreen extends StatefulWidget {
  final List<BookChunk> chunks;

  const SearchScreen({super.key, required this.chunks});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchResult {
  final BookChunk chunk;
  final String text;
  final List<TextSpan> highlights;

  const _SearchResult({
    required this.chunk,
    required this.text,
    required this.highlights,
  });
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _searchController = TextEditingController();
  final ReadingSettingsService _settingsService = ReadingSettingsService();
  ReadingSettings _settings = const ReadingSettings();

  List<_SearchResult> _results = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final s = await _settingsService.loadSettings();
    if (mounted) {
      setState(() => _settings = s);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _performSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);

    final cleanQuery = query.replaceAll(RegExp(r'[^\w\s]'), '').trim();
    if (cleanQuery.isEmpty) {
      setState(() {
        _results = [];
        _isSearching = false;
      });
      return;
    }

    // Create a flexible pattern: insert [^\w\s]* between each letter/space
    final patternBuf = StringBuffer();
    for (int i = 0; i < cleanQuery.length; i++) {
      patternBuf.write(RegExp.escape(cleanQuery[i]));
      if (i < cleanQuery.length - 1) {
        patternBuf.write(r'[^\w\s]*');
      }
    }

    final regex = RegExp(patternBuf.toString(), caseSensitive: false);

    final List<_SearchResult> found = [];

    final textColor = _settings.textColor;
    const matchColor = Color(0xFFE85D04);

    for (final chunk in widget.chunks) {
      if (chunk.type != BookChunkType.text) continue;
      final text = chunk.text ?? '';
      if (text.isEmpty) continue;

      final matches = regex.allMatches(text);
      if (matches.isNotEmpty) {
        final match = matches.first;
        final startIdx = match.start;
        final endIdx = match.end;

        final contextStart = (startIdx - 50).clamp(0, text.length);
        final contextEnd = (endIdx + 50).clamp(0, text.length);

        String snippet = text.substring(contextStart, contextEnd);

        final List<TextSpan> highlightSpans = [];
        final localStart = startIdx - contextStart;
        final localEnd = endIdx - contextStart;

        if (contextStart > 0) snippet = '...$snippet';
        if (contextEnd < text.length) snippet = '$snippet...';

        // Adjust local indices if '...' was prepended
        final offset = (contextStart > 0) ? 3 : 0;

        highlightSpans.add(
          TextSpan(
            text: snippet.substring(0, localStart + offset),
            style: TextStyle(color: textColor),
          ),
        );
        highlightSpans.add(
          TextSpan(
            text: snippet.substring(localStart + offset, localEnd + offset),
            style: const TextStyle(
              color: matchColor,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
        highlightSpans.add(
          TextSpan(
            text: snippet.substring(localEnd + offset),
            style: TextStyle(color: textColor),
          ),
        );

        found.add(
          _SearchResult(
            chunk: chunk,
            text: snippet,
            highlights: highlightSpans,
          ),
        );
      }
    }

    setState(() {
      _results = found;
      _isSearching = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _settings.backgroundColor,
      appBar: AppBar(
        backgroundColor: _settings.menuColor,
        foregroundColor: _settings.textColor,
        elevation: 0,
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: TextStyle(color: _settings.textColor),
          decoration: InputDecoration(
            hintText: 'Search within book...',
            hintStyle: TextStyle(color: _settings.mutedColor),
            border: InputBorder.none,
            suffixIcon: IconButton(
              icon: Icon(Icons.clear, color: _settings.textColor),
              onPressed: () {
                _searchController.clear();
                _performSearch('');
              },
            ),
          ),
          onChanged: _performSearch,
          onSubmitted: _performSearch,
        ),
      ),
      body: _isSearching
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE85D04)),
            )
          : _results.isEmpty && _searchController.text.isNotEmpty
          ? Center(
              child: Text(
                'No matches found.',
                style: TextStyle(color: _settings.textColor, fontSize: 16),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _results.length,
              separatorBuilder: (_, __) =>
                  Divider(color: _settings.mutedColor.withValues(alpha: 0.3)),
              itemBuilder: (context, index) {
                final res = _results[index];
                return InkWell(
                  onTap: () {
                    Navigator.pop(context, res.chunk.index);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: RichText(text: TextSpan(children: res.highlights)),
                  ),
                );
              },
            ),
    );
  }
}
