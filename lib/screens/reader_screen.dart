import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book_chunk.dart';
import '../models/bookmark.dart';
import '../models/reading_settings.dart';
import '../services/bookmark_service.dart';
import '../services/reading_settings_service.dart';
import '../widgets/navigation_panel.dart';
import '../widgets/reading_card.dart';

/// Screen 2 — fullscreen vertical-swipe reader with progress tracking,
/// overlay menu (scrubber + navigation), and bookmark management.
class ReaderScreen extends StatefulWidget {
  final String title;
  final String bookId;
  final List<BookChunk> chunks;
  final Map<String, int> anchorMap;
  final List<ChapterInfo> chapters;

  const ReaderScreen({
    super.key,
    required this.title,
    required this.bookId,
    required this.chunks,
    required this.anchorMap,
    required this.chapters,
  });

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin {
  PageController? _pageController;
  late BookmarkService _bookmarkService;
  late AnimationController _overlayAnimController;
  late Animation<double> _overlayAnim;

  bool _ready = false;
  int _currentPage = 0;
  int _targetOriginalIndex = 0;
  Size? _lastScreenSize;

  // Overlay
  bool _overlayVisible = false;

  // Bookmarks
  List<Bookmark> _bookmarks = [];
  int? _tempBookmarkIndex;
  
  // Rendered Chunks
  final List<BookChunk> _displayChunks = [];
  final List<List<int>> _displayToOriginal = [];
  final Map<int, int> _originalToDisplay = {};

  // Settings
  final _settingsService = ReadingSettingsService();
  ReadingSettings _settings = const ReadingSettings();

  @override
  void initState() {
    super.initState();
    _bookmarkService = BookmarkService(bookId: widget.bookId);

    _overlayAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    _overlayAnim = CurvedAnimation(
      parent: _overlayAnimController,
      curve: Curves.easeInOut,
    );

    _initReadingPosition();
  }

  @override
  void dispose() {
    _overlayAnimController.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  // ─── Initialization ──────────────────────────────────────────────────

  Future<void> _initReadingPosition() async {
    if (widget.chunks.isEmpty) {
      setState(() => _ready = true);
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final key = 'last_read_${widget.bookId}';
    final lastIndex = prefs.getInt(key) ?? 0;
    _targetOriginalIndex = lastIndex.clamp(0, widget.chunks.length - 1);

    final bookmarks = await _bookmarkService.load();
    final settings = await _settingsService.loadSettings();

    setState(() {
      _bookmarks = bookmarks;
      _settings = settings;
      _ready = true;
    });
  }

  void _rebuildDisplayChunks(Size screenSize) {
    _displayChunks.clear();
    _displayToOriginal.clear();
    _originalToDisplay.clear();

    if (widget.chunks.isEmpty) return;

    // 1. Determine multipliers
    double densityMultiplier;
    switch (_settings.contentDensity) {
      case ContentDensity.low:
        densityMultiplier = 0.35;
        break;
      case ContentDensity.medium:
        densityMultiplier = 0.55;
        break;
      case ContentDensity.high:
        densityMultiplier = 0.75;
        break;
      case ContentDensity.fullPage:
        densityMultiplier = 1.0; 
        break;
    }

    // Available width = screen width - 2*24 horizontal padding
    final availableWidth = screenSize.width - 48.0;
    
    // Max height constraint based on density settings
    final fullBoundsHeight = screenSize.height - 110.0;
    final maxHeight = fullBoundsHeight * densityMultiplier;

    // Helper: Test exact painted dimensions of text line
    double measureTextHeight(String text, bool isHeading) {
      final style = _settings.getTextStyle(context, isHeading: isHeading);
      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        textAlign: isHeading 
            ? TextAlign.center 
            : _settings.textAlign == ReaderTextAlign.center 
                ? TextAlign.center 
                : _settings.textAlign == ReaderTextAlign.right 
                    ? TextAlign.right 
                    : _settings.textAlign == ReaderTextAlign.justify 
                        ? TextAlign.justify 
                        : TextAlign.left,
      );
      tp.layout(maxWidth: availableWidth);
      return tp.height;
    }

    // Helper: Chunk Splitting exactly as wide as bounds
    List<BookChunk> splitChunkByHeight(BookChunk original) {
      if (original.type != BookChunkType.text || original.isHeading) {
        return [original];
      }
      final text = original.text ?? '';
      if (text.isEmpty) return [original];
      
      final totalH = measureTextHeight(text, false);
      if (totalH <= maxHeight) return [original];

      // Slicing algorithm strictly extracts full strings up to punctuation.
      final RegExp safeRe = RegExp(r'.*?[.!?](?:\s+|$)|.+');
      final matches = safeRe.allMatches(text);
      final sentences = matches.map((m) => m.group(0)?.trim() ?? '').where((s) => s.isNotEmpty).toList();
      
      if (sentences.isEmpty) return [original];

      final subChunks = <BookChunk>[];
      StringBuffer currentText = StringBuffer();
      int currentStartOffset = 0;

      void flushSubChunk(int endOffset) {
        if (currentText.isEmpty) return;
        final subText = currentText.toString().trim();
        
        List<LinkMetadata>? subLinks;
        if (original.links != null && original.links!.isNotEmpty) {
          subLinks = [];
          for (final link in original.links!) {
             if (link.start >= currentStartOffset && link.start < endOffset) {
               subLinks.add(
                 LinkMetadata(
                    start: link.start - currentStartOffset, 
                    end: link.end - currentStartOffset, 
                    url: link.url
                 )
               );
             }
          }
        }

        subChunks.add(
          BookChunk(
            index: original.index,
            type: BookChunkType.text,
            section: original.section,
            sourceFile: original.sourceFile,
            isHeading: false,
            text: subText,
            links: subLinks,
          )
        );
        
        currentText.clear();
        currentStartOffset = endOffset;
      }

      int charOffset = 0;
      for (final sentence in sentences) {
         final testText = currentText.isEmpty ? sentence : '${currentText.toString()} $sentence';
         final testHeight = measureTextHeight(testText, false);
         
         if (testHeight > maxHeight && currentText.isNotEmpty) {
           flushSubChunk(charOffset);
         }
         
         if (currentText.isNotEmpty) currentText.write(' ');
         currentText.write(sentence);
         charOffset += sentence.length;
      }
      flushSubChunk(text.length);

      return subChunks.isNotEmpty ? subChunks : [original];
    }

    BookChunk? pending;
    List<int> pendingOriginals = [];

    void flush() {
      if (pending != null) {
        final dIdx = _displayChunks.length;
        _displayChunks.add(pending!);
        _displayToOriginal.add(pendingOriginals);
        for (final oIdx in pendingOriginals) {
          _originalToDisplay[oIdx] = dIdx;
        }
        pending = null;
        pendingOriginals = [];
      }
    }

    for (int i = 0; i < widget.chunks.length; i++) {
        final originalChunk = widget.chunks[i];
        final subChunks = splitChunkByHeight(originalChunk);

        for (final chunk in subChunks) {
          if (chunk.type != BookChunkType.text) {
            flush();
            pending = chunk;
            pendingOriginals = [chunk.index];
            flush();
            continue;
          }

          final text = chunk.text ?? '';
          if (text.isEmpty) {
            _originalToDisplay[chunk.index] = _displayChunks.length;
            continue;
          }

          if (pending == null) {
            pending = chunk;
            pendingOriginals = [chunk.index];
            continue;
          }

          final pendingText = pending!.text ?? '';
          final testMergeText = '$pendingText\n\n$text';

          if (pending!.section == chunk.section &&
              pending!.sourceFile == chunk.sourceFile &&
              pending!.isHeading == chunk.isHeading &&
              measureTextHeight(testMergeText, pending!.isHeading) <= maxHeight) {
            // Merge perfectly fits layout bounds!
            pending = BookChunk(
               index: pending!.index,
               type: BookChunkType.text,
               section: pending!.section,
               sourceFile: pending!.sourceFile,
               isHeading: pending!.isHeading,
               text: testMergeText,
               links: [
                 ...?pending!.links,
                 ...?(chunk.links?.map((l) => LinkMetadata(
                   start: l.start + pendingText.length + 2,
                   end: l.end + pendingText.length + 2,
                   url: l.url,
                 )).toList()),
               ],
            );
            if (!pendingOriginals.contains(chunk.index)) {
              pendingOriginals.add(chunk.index);
            }
          } else {
            flush();
            pending = chunk;
            pendingOriginals = [chunk.index];
          }
        }
    }
    flush();
  }

  // ─── Reading position persistence ────────────────────────────────────

  Future<void> _saveReadingPosition(int index) async {
    setState(() => _currentPage = index);
    
    final originals = _displayToOriginal[index];
    if (originals.isEmpty) return;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_read_${widget.bookId}', originals.first);
  }

  // ─── Internal link navigation ────────────────────────────────────────

  void _onLinkTap(String url) {
    String anchor = url;
    final hashIndex = url.indexOf('#');
    if (hashIndex != -1) {
      anchor = url.substring(hashIndex + 1);
    }

    final originalIndex = widget.anchorMap[anchor];
    if (originalIndex != null) {
      final targetIndex = _originalToDisplay[originalIndex];
      if (targetIndex != null) {
        _pageController?.jumpToPage(targetIndex);
      }
    } else {
      debugPrint('Anchor not found: $anchor');
    }
  }

  // ─── Overlay toggle ──────────────────────────────────────────────────

  void _toggleOverlay() {
    setState(() => _overlayVisible = !_overlayVisible);
    if (_overlayVisible) {
      _overlayAnimController.forward();
    } else {
      _overlayAnimController.reverse();
    }
  }

  // ─── Bookmark actions ────────────────────────────────────────────────

  Future<void> _onBookmarkTap(int displayIndex) async {
    final originals = _displayToOriginal[displayIndex];
    if (originals.isEmpty) return;
    final chunkIndex = originals.first;

    final isMarked = _bookmarkService.isBookmarked(_bookmarks, chunkIndex);

    if (!isMarked) {
      // Create new bookmark
      final updated = await _bookmarkService.add(chunkIndex);
      setState(() => _bookmarks = updated);
    } else {
      // Already bookmarked → remove
      final updated = await _bookmarkService.remove(chunkIndex);
      setState(() => _bookmarks = updated);
    }
  }

  Future<void> _onBookmarkLongPress(int displayIndex) async {
    final originals = _displayToOriginal[displayIndex];
    if (originals.isEmpty) return;
    final chunkIndex = originals.first;

    final isMarked = _bookmarkService.isBookmarked(_bookmarks, chunkIndex);
    if (!isMarked) return;

    _showRenameDialog(chunkIndex);
  }

  void _showRenameDialog(int chunkIndex) {
    final bookmark = _bookmarks.firstWhere(
      (b) => b.chunkIndex == chunkIndex,
    );
    final controller = TextEditingController(text: bookmark.name);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFFFAF8F5),
        title: const Text('Rename Bookmark'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Bookmark name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () async {
              final name = controller.text.trim();
              if (name.isNotEmpty) {
                final updated =
                    await _bookmarkService.rename(chunkIndex, name);
                setState(() => _bookmarks = updated);
              }
              if (ctx.mounted) Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFE85D04),
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ─── Navigation (with temp bookmark) ─────────────────────────────────

  void _navigateTo(int targetIndex) {
    // Save current position as temp bookmark BEFORE jumping
    setState(() => _tempBookmarkIndex = _currentPage);
    _pageController?.jumpToPage(targetIndex);
  }

  void _openNavigationPanel() {
    NavigationPanel.show(
      context,
      bookmarks: _bookmarks,
      tempBookmarkIndex: _tempBookmarkIndex,
      chapters: widget.chapters,
      currentPage: _currentPage,
      onNavigate: (originalIndex) {
         // The navigation panel returns an original index!
         // Temp bookmarks jump needs to convert to display index
         final targetDIndex = _originalToDisplay[originalIndex];
         if (targetDIndex != null) {
            _navigateTo(targetDIndex);
         }
      },
    );
  }

  // ─── Build ───────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_displayChunks.isEmpty && widget.chunks.isNotEmpty) {
      // Re-measure Layout natively prior to painting!
      final screenSize = MediaQuery.sizeOf(context);
      if (_lastScreenSize != screenSize) {
        _lastScreenSize = screenSize;
        // Schedule synchronously rebuild inline so Flutter layout immediately displays the exact chunk.
        _rebuildDisplayChunks(screenSize);
        final newDisplayIndex = _originalToDisplay[_targetOriginalIndex] ?? 0;
        _currentPage = newDisplayIndex;
        _pageController?.dispose();
        _pageController = PageController(initialPage: newDisplayIndex);
      }
    }

    if (_displayChunks.isEmpty) {
      return Scaffold(
        backgroundColor: _settings.backgroundColor(context),
        body: Center(
          child: Text('No readable content found in this book.',
            style: TextStyle(color: _settings.textColor(context)),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: _settings.backgroundColor(context),
      body: Stack(
        children: [
          // ── PageView (always present) ──
          PageView.builder(
            scrollDirection: Axis.vertical,
            controller: _pageController!,
            itemCount: _displayChunks.length,
            physics: const BouncingScrollPhysics(),
            onPageChanged: _saveReadingPosition,
            itemBuilder: (context, index) {
              final mappedOriginals = _displayToOriginal[index];
              final chunkIndex = mappedOriginals.isNotEmpty ? mappedOriginals.first : -1;
               
              return ReadingCard(
                chunk: _displayChunks[index],
                settings: _settings,
                onLinkTap: _onLinkTap,
                isBookmarked:
                    _bookmarkService.isBookmarked(_bookmarks, chunkIndex),
                onBookmarkTap: () => _onBookmarkTap(index),
                onBookmarkLongPress: () => _onBookmarkLongPress(index),
              );
            },
          ),

          // ── Fixed Boundaries for Density Visualization ──
          Positioned(
            top: 50,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Container(
                height: 1,
                color: _settings.mutedColor(context).withValues(alpha: 0.3),
              ),
            ),
          ),
          Positioned(
            bottom: 60,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Container(
                height: 1,
                color: _settings.mutedColor(context).withValues(alpha: 0.3),
              ),
            ),
          ),

          // ── Center tap detector for overlay toggle ──
          // Only covers the center third — bookmark icon at top-right stays tappable.
          Builder(
            builder: (context) {
              final screenH = MediaQuery.of(context).size.height;
              final third = screenH / 3;
              return Positioned(
                top: third,
                left: 0,
                right: 0,
                height: third,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onTap: _toggleOverlay,
                ),
              );
            },
          ),

          // ── Top menu placeholder ──
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_overlayVisible,
              child: _buildTopMenu(),
            ),
          ),

          // ── Bottom menu (scrubber + navigation) ──
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: IgnorePointer(
              ignoring: !_overlayVisible,
              child: _buildBottomMenu(),
            ),
          ),
        ],
      ),
    );
  }

  // ─── Top Menu ──────────────────────────────────────────

  void _toggleTheme() {
    final newMode = _settings.isDark(context) ? ThemeMode.light : ThemeMode.dark;
    final updated = _settings.copyWith(themeMode: newMode);
    setState(() => _settings = updated);
    _settingsService.saveSettings(updated);
  }

  void _handleSettingsUpdate(ReadingSettings updated) {
    // Identify current visual location by fetching exact active chunk before screen dimensions change.
    if (_displayToOriginal.isNotEmpty && _currentPage < _displayToOriginal.length && _displayToOriginal[_currentPage].isNotEmpty) {
      _targetOriginalIndex = _displayToOriginal[_currentPage].first;
    }

    setState(() {
      _settings = updated;
      // Force rebuild layout constraints synchronously next frame natively
      _lastScreenSize = null;
      _displayChunks.clear();
    });
    _settingsService.saveSettings(updated);
  }

  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: _settings.backgroundColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            Widget buildSectionTitle(String title) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
                child: Text(
                  title.toUpperCase(),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: _settings.mutedColor(context),
                  ),
                ),
              );
            }

            return SafeArea(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Handle
                    Center(
                      child: Container(
                        margin: const EdgeInsets.only(top: 12),
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _settings.mutedColor(context).withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    buildSectionTitle('Font Size'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: ReaderFontSize.values.map((size) {
                          final isSelected = _settings.fontSize == size;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(
                                  size.name.toUpperCase(),
                                  style: TextStyle(color: isSelected ? Colors.white : _settings.textColor(context), fontSize: 13),
                                ),
                                selected: isSelected,
                                selectedColor: const Color(0xFFE85D04),
                                backgroundColor: _settings.isDark(context) ? Colors.black26 : Colors.black12,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                onSelected: (val) {
                                  if (val) {
                                    final updated = _settings.copyWith(fontSize: size);
                                    _handleSettingsUpdate(updated);
                                    setModalState(() {});
                                  }
                                },
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),

                    buildSectionTitle('Font Options'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: SizedBox(
                        height: 48,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: ReaderFontFamily.values.map((family) {
                            final isSelected = _settings.fontFamily == family;
                            return Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(
                                  family.name.replaceAll('Mono', ' Mono').replaceAll('Neue', ' Neue').toUpperCase(),
                                  style: TextStyle(color: isSelected ? Colors.white : _settings.textColor(context), fontSize: 12),
                                ),
                                selected: isSelected,
                                selectedColor: const Color(0xFFE85D04),
                                backgroundColor: _settings.isDark(context) ? Colors.black26 : Colors.black12,
                                onSelected: (val) {
                                  if (val) {
                                    final updated = _settings.copyWith(fontFamily: family);
                                    _handleSettingsUpdate(updated);
                                    setModalState(() {});
                                  }
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ),

                    buildSectionTitle('Text Alignment'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: ReaderTextAlign.values.map((align) {
                          final isSelected = _settings.textAlign == align;
                          return IconButton(
                            icon: Icon(
                              align == ReaderTextAlign.left ? Icons.format_align_left :
                              align == ReaderTextAlign.center ? Icons.format_align_center :
                              align == ReaderTextAlign.right ? Icons.format_align_right :
                              Icons.format_align_justify,
                              color: isSelected ? const Color(0xFFE85D04) : _settings.textColor(context),
                            ),
                            onPressed: () {
                              final updated = _settings.copyWith(textAlign: align);
                              _handleSettingsUpdate(updated);
                              setModalState(() {});
                            },
                          );
                        }).toList(),
                      ),
                    ),

                    buildSectionTitle('Content Density'),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Row(
                        children: ContentDensity.values.map((density) {
                          final isSelected = _settings.contentDensity == density;
                          return Expanded(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 4),
                              child: ChoiceChip(
                                label: Text(
                                  density.name.toUpperCase(),
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : _settings.textColor(context), 
                                    fontSize: 10,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                selected: isSelected,
                                selectedColor: const Color(0xFFE85D04),
                                backgroundColor: _settings.isDark(context) ? Colors.black26 : Colors.black12,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                onSelected: (val) {
                                  if (val) {
                                    final updated = _settings.copyWith(contentDensity: density);
                                    _handleSettingsUpdate(updated);
                                    setModalState(() {});
                                  }
                                },
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            );
          }
        );
      },
    );
  }

  Widget _buildTopMenu() {
    return AnimatedBuilder(
      animation: _overlayAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, -80 * (1 - _overlayAnim.value)),
          child: Opacity(
             opacity: _overlayAnim.value,
             child: Container(
               height: MediaQuery.of(context).padding.top + 56,
               padding: EdgeInsets.only(
                 top: MediaQuery.of(context).padding.top,
               ),
               decoration: BoxDecoration(
                 color: _settings.backgroundColor(context).withValues(alpha: 0.95),
                 boxShadow: [
                   BoxShadow(
                     color: Colors.black.withValues(alpha: 0.05),
                     blurRadius: 8,
                     offset: const Offset(0, 2),
                   ),
                 ],
               ),
               child: Row(
                 crossAxisAlignment: CrossAxisAlignment.center,
                 children: [
                   // Back button space
                   const SizedBox(width: 48), // Padding equivalent to typical back button if added
                   Expanded(
                     child: Center(
                       child: Text(
                         widget.title,
                         style: TextStyle(
                           fontSize: 16,
                           fontWeight: FontWeight.w600,
                           color: _settings.textColor(context),
                         ),
                         maxLines: 1,
                         overflow: TextOverflow.ellipsis,
                       ),
                     ),
                   ),
                   IconButton(
                     icon: Icon(
                       _settings.isDark(context) ? Icons.light_mode : Icons.dark_mode,
                       color: _settings.textColor(context),
                     ),
                     onPressed: _toggleTheme,
                   ),
                   IconButton(
                     icon: Icon(Icons.text_format, color: _settings.textColor(context)),
                     onPressed: _showSettingsModal,
                   ),
                   const SizedBox(width: 8),
                 ],
               ),
             ),
           ),
         );
       },
     );
   }

  // ─── Bottom Menu (scrubber + navigation icon) ────────────────────────

  Widget _buildBottomMenu() {
    return AnimatedBuilder(
      animation: _overlayAnim,
      builder: (context, child) {
        return Transform.translate(
          offset: Offset(0, 100 * (1 - _overlayAnim.value)),
          child: Opacity(
            opacity: _overlayAnim.value,
            child: Container(
              padding: EdgeInsets.only(
                left: 20,
                right: 8,
                top: 12,
                bottom: MediaQuery.of(context).padding.bottom + 16,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFFFAF8F5).withValues(alpha: 0.95),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Page counter
                  Text(
                    '${_currentPage + 1} / ${_displayChunks.length}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF9E9E9E),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Scrubber row
                  Row(
                    children: [
                      // Scrubber
                      Expanded(
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(
                                enabledThumbRadius: 8),
                            overlayShape: const RoundSliderOverlayShape(
                                overlayRadius: 16),
                            activeTrackColor: const Color(0xFFE85D04),
                            inactiveTrackColor: const Color(0xFFE0E0E0),
                            thumbColor: const Color(0xFFE85D04),
                            overlayColor:
                                const Color(0xFFE85D04).withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            min: 0,
                            max: (_displayChunks.length - 1).toDouble() < 0 ? 0 : (_displayChunks.length - 1).toDouble(),
                            value: _currentPage.toDouble().clamp(0, (_displayChunks.length - 1).toDouble() < 0 ? 0 : (_displayChunks.length - 1).toDouble()),
                            onChanged: (val) {
                              final page = val.round();
                              _pageController?.jumpToPage(page);
                            },
                          ),
                        ),
                      ),
                      // Navigation icon
                      IconButton(
                        onPressed: _openNavigationPanel,
                        icon: const Icon(Icons.list_alt_rounded),
                        color: const Color(0xFF2C2C2C),
                        iconSize: 28,
                        tooltip: 'Navigation',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
