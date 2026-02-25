import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/book_chunk.dart';
import '../models/bookmark.dart';
import '../models/reading_settings.dart';
import '../services/bookmark_service.dart';
import '../services/reading_settings_service.dart';
import '../services/book_metadata_service.dart';
import '../widgets/navigation_panel.dart';
import '../widgets/reading_card.dart';
import 'search_screen.dart';

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

/// Shared layout constants so boundary lines, ReadingCard padding,
/// and chunk-splitting all agree on the exact same measurements.
const double kBoundaryTop = 24.0;
const double kBoundaryBottom = 28.0;
const double kContentPaddingH = 24.0;

class _ReaderScreenState extends State<ReaderScreen>
    with SingleTickerProviderStateMixin {
  PageController? _pageController;
  late final BookmarkService _bookmarkService;
  late final AnimationController _overlayAnimController;
  late final Animation<double> _overlayAnim;

  bool _ready = false;
  int _currentPage = 0;
  int _targetOriginalIndex = 0;
  Size? _lastScreenSize;
  EdgeInsets? _lastSafeArea;

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

  // Metadata
  final _metadataService = BookMetadataService();

  // Cached preferences to avoid repeated async lookups
  SharedPreferences? _prefs;

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

    await _metadataService.init();
    final metadata = _metadataService.getMetadata(widget.bookId);

    _prefs = await SharedPreferences.getInstance();
    final key = 'last_read_${widget.bookId}';
    int lastIndex = _prefs!.getInt(key) ?? 0;

    if (metadata != null && metadata.lastReadIndex > 0) {
      lastIndex = metadata.lastReadIndex;
    }

    _targetOriginalIndex = lastIndex.clamp(0, widget.chunks.length - 1);

    final bookmarks = await _bookmarkService.load();
    final settings = await _settingsService.loadSettings();

    // Inject the book's custom theme overrides specifically into the reader settings
    final metadataRaw = _metadataService.getMetadata(widget.bookId);

    setState(() {
      _bookmarks = bookmarks;
      _settings = settings.copyWith(
        readerTheme: metadataRaw?.theme,
        clearReaderTheme: metadataRaw?.theme == null,
      );
      _ready = true;
    });
  }

  void _ensureDisplayChunksBuilt(
    Size screenSize,
    EdgeInsets safeArea,
    TextScaler textScaler,
  ) {
    if (_lastScreenSize == screenSize &&
        _lastSafeArea == safeArea &&
        _displayChunks.isNotEmpty) {
      return;
    }

    _lastScreenSize = screenSize;
    _lastSafeArea = safeArea;
    _rebuildDisplayChunks(screenSize, safeArea, textScaler);

    final newDisplayIndex = _originalToDisplay[_targetOriginalIndex] ?? 0;
    _currentPage = newDisplayIndex;
    _pageController?.dispose();
    _pageController = PageController(initialPage: newDisplayIndex);
  }

  void _rebuildDisplayChunks(
    Size screenSize,
    EdgeInsets safeArea,
    TextScaler textScaler,
  ) {
    _displayChunks.clear();
    _displayToOriginal.clear();
    _originalToDisplay.clear();

    if (widget.chunks.isEmpty) return;

    final densityMultiplier = _settings.densityMultiplier;

    // Available width = screen width - 2 * horizontal padding
    final availableWidth = screenSize.width - (kContentPaddingH * 2);

    // The content lives between the two boundary lines.
    // We must subtract safe-area insets (status bar + nav bar) because
    // those eat into our usable area.
    final topInset = safeArea.top + kBoundaryTop;
    final bottomInset = safeArea.bottom + kBoundaryBottom;
    final fullBoundsHeight = screenSize.height - topInset - bottomInset;
    final maxHeight = fullBoundsHeight * densityMultiplier;

    // Cache text styles to avoid repeated GoogleFonts calls
    final bodyStyle = _settings.getTextStyle();
    final headingStyle = _settings.getTextStyle(isHeading: true);

    final bodyAlign = _settings.resolvedTextAlign;

    // Helper: measures exact painted height, using the same textScaler
    // as the Text widget so measurements are pixel-accurate.
    double measureTextHeight(String text, bool isHeading) {
      final tp = TextPainter(
        text: TextSpan(text: text, style: isHeading ? headingStyle : bodyStyle),
        textDirection: TextDirection.ltr,
        textAlign: isHeading ? TextAlign.center : bodyAlign,
        textScaler: textScaler,
      );
      tp.layout(maxWidth: availableWidth);
      final h = tp.height;
      tp.dispose();
      return h;
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
      final sentences = matches
          .map((m) => m.group(0)?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      if (sentences.isEmpty) return [original];

      final subChunks = <BookChunk>[];
      final StringBuffer currentText = StringBuffer();
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
                  url: link.url,
                ),
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
            text: subText,
            links: subLinks,
          ),
        );

        currentText.clear();
        currentStartOffset = endOffset;
      }

      int charOffset = 0;
      for (final sentence in sentences) {
        final testText = currentText.isEmpty
            ? sentence
            : '${currentText.toString()} $sentence';
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
              ...?(chunk.links
                  ?.map(
                    (l) => LinkMetadata(
                      start: l.start + pendingText.length + 2,
                      end: l.end + pendingText.length + 2,
                      url: l.url,
                    ),
                  )
                  .toList()),
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

  void _onPageChanged(int index) {
    _currentPage = index;
    // Defer persistence to avoid blocking the page transition
    _deferSaveReadingPosition(index);
  }

  void _deferSaveReadingPosition(int index) {
    // Use a post-frame callback to avoid jank during the swipe animation
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _persistReadingPosition(index);
    });
  }

  Future<void> _persistReadingPosition(int index) async {
    if (index >= _displayToOriginal.length) return;
    final originals = _displayToOriginal[index];
    if (originals.isEmpty) return;

    final originalIndex = originals.first;

    _prefs ??= await SharedPreferences.getInstance();
    await _prefs!.setInt('last_read_${widget.bookId}', originalIndex);

    final metadata = _metadataService.getMetadata(widget.bookId);
    if (metadata != null) {
      final updated = metadata.copyWith(
        lastReadIndex: originalIndex,
        totalChunks: widget.chunks.length,
        lastReadTime: DateTime.now().millisecondsSinceEpoch,
      );
      await _metadataService.updateMetadata(updated);
    }
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
      final updated = await _bookmarkService.add(chunkIndex);
      setState(() => _bookmarks = updated);
    } else {
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
    final bookmark = _bookmarks.firstWhere((b) => b.chunkIndex == chunkIndex);
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
                final updated = await _bookmarkService.rename(chunkIndex, name);
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
    _tempBookmarkIndex = _currentPage;
    _pageController?.jumpToPage(targetIndex);
  }

  Future<void> _openSearchScreen() async {
    final targetIndex = await Navigator.push<int>(
      context,
      MaterialPageRoute(builder: (_) => SearchScreen(chunks: widget.chunks)),
    );

    if (targetIndex != null) {
      final displayIndex = _originalToDisplay[targetIndex];
      if (displayIndex != null) {
        _navigateTo(displayIndex);
      }
    }
  }

  void _openNavigationPanel() {
    NavigationPanel.show(
      context,
      bookmarks: _bookmarks,
      tempBookmarkIndex: _tempBookmarkIndex,
      chapters: widget.chapters,
      currentPage: _currentPage,
      onNavigate: (originalIndex) {
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (widget.chunks.isNotEmpty) {
      final screenSize = MediaQuery.sizeOf(context);
      final safeArea = MediaQuery.paddingOf(context);
      final textScaler = MediaQuery.textScalerOf(context);
      _ensureDisplayChunksBuilt(screenSize, safeArea, textScaler);
    }

    if (_displayChunks.isEmpty) {
      return Scaffold(
        backgroundColor: _settings.backgroundColor,
        body: Center(
          child: Text(
            'No readable content found in this book.',
            style: TextStyle(color: _settings.textColor),
          ),
        ),
      );
    }

    final bgColor = _settings.backgroundColor;
    final mutedColor = _settings.mutedColor;

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // ── PageView (always present) ──
          _ReaderPageView(
            pageController: _pageController!,
            displayChunks: _displayChunks,
            displayToOriginal: _displayToOriginal,
            settings: _settings,
            bookmarkService: _bookmarkService,
            bookmarks: _bookmarks,
            onPageChanged: _onPageChanged,
            onLinkTap: _onLinkTap,
            onBookmarkTap: _onBookmarkTap,
            onBookmarkLongPress: _onBookmarkLongPress,
          ),

          // ── Fixed Boundaries for Density Visualization ──
          Positioned(
            top: MediaQuery.paddingOf(context).top + kBoundaryTop,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Container(
                height: 1,
                color: mutedColor.withValues(alpha: 0.3),
              ),
            ),
          ),
          Positioned(
            bottom: MediaQuery.paddingOf(context).bottom + kBoundaryBottom,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Container(
                height: 1,
                color: mutedColor.withValues(alpha: 0.3),
              ),
            ),
          ),

          // ── Center tap detector for overlay toggle ──
          _CenterTapDetector(onTap: _toggleOverlay),

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

  void _handleSettingsUpdate(ReadingSettings updated) {
    // Identify current visual location before screen dimensions change.
    if (_displayToOriginal.isNotEmpty &&
        _currentPage < _displayToOriginal.length &&
        _displayToOriginal[_currentPage].isNotEmpty) {
      _targetOriginalIndex = _displayToOriginal[_currentPage].first;
    }

    // Persist readerTheme directly back into BookMetadata
    final metadata = _metadataService.getMetadata(widget.bookId);
    if (metadata != null && metadata.theme != updated.readerTheme) {
      _metadataService.updateMetadata(
        metadata.copyWith(
          theme: updated.readerTheme,
          clearTheme: updated.readerTheme == null,
        ),
      );
    }

    setState(() {
      _settings = updated;
      // Force rebuild layout constraints synchronously next frame
      _lastScreenSize = null;
      _lastSafeArea = null;
      _displayChunks.clear();
    });
    _settingsService.saveSettings(updated);
  }

  void _showSettingsModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return _SettingsModalContent(
          settings: _settings,
          onSettingsChanged: (updated) {
            _handleSettingsUpdate(updated);
          },
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
              height: MediaQuery.paddingOf(context).top + 56,
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              decoration: BoxDecoration(
                color: _settings.menuColor.withValues(alpha: 0.95),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: _settings.textColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Center(
                      child: Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _settings.textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.search, color: _settings.textColor),
                    onPressed: _openSearchScreen,
                  ),
                  IconButton(
                    icon: Icon(Icons.text_format, color: _settings.textColor),
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
                bottom: MediaQuery.paddingOf(context).bottom + 16,
              ),
              decoration: BoxDecoration(
                color: _settings.menuColor.withValues(alpha: 0.95),
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
                              enabledThumbRadius: 8,
                            ),
                            overlayShape: const RoundSliderOverlayShape(
                              overlayRadius: 16,
                            ),
                            activeTrackColor: const Color(0xFFE85D04),
                            inactiveTrackColor: _settings.isDark
                                ? Colors.grey[800]
                                : const Color(0xFFE0E0E0),
                            thumbColor: const Color(0xFFE85D04),
                            overlayColor: const Color(
                              0xFFE85D04,
                            ).withValues(alpha: 0.2),
                          ),
                          child: Slider(
                            max: (_displayChunks.length - 1).toDouble().clamp(
                              0,
                              double.infinity,
                            ),
                            value: _currentPage.toDouble().clamp(
                              0,
                              (_displayChunks.length - 1).toDouble().clamp(
                                0,
                                double.infinity,
                              ),
                            ),
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
                        color: _settings.textColor,
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

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Extracted Widgets — Separation of Concerns & Rebuild Minimization
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

/// Extracted PageView to isolate its rebuilds from overlay changes.
class _ReaderPageView extends StatelessWidget {
  final PageController pageController;
  final List<BookChunk> displayChunks;
  final List<List<int>> displayToOriginal;
  final ReadingSettings settings;
  final BookmarkService bookmarkService;
  final List<Bookmark> bookmarks;
  final ValueChanged<int> onPageChanged;
  final Function(String url) onLinkTap;
  final Function(int displayIndex) onBookmarkTap;
  final Function(int displayIndex) onBookmarkLongPress;

  const _ReaderPageView({
    required this.pageController,
    required this.displayChunks,
    required this.displayToOriginal,
    required this.settings,
    required this.bookmarkService,
    required this.bookmarks,
    required this.onPageChanged,
    required this.onLinkTap,
    required this.onBookmarkTap,
    required this.onBookmarkLongPress,
  });

  @override
  Widget build(BuildContext context) {
    return PageView.builder(
      scrollDirection: Axis.vertical,
      controller: pageController,
      itemCount: displayChunks.length,
      physics: const BouncingScrollPhysics(),
      onPageChanged: onPageChanged,
      itemBuilder: (context, index) {
        final mappedOriginals = displayToOriginal[index];
        final chunkIndex = mappedOriginals.isNotEmpty
            ? mappedOriginals.first
            : -1;

        return ReadingCard(
          chunk: displayChunks[index],
          settings: settings,
          onLinkTap: onLinkTap,
          isBookmarked: bookmarkService.isBookmarked(bookmarks, chunkIndex),
          onBookmarkTap: () => onBookmarkTap(index),
          onBookmarkLongPress: () => onBookmarkLongPress(index),
        );
      },
    );
  }
}

/// Extracted center tap detector to avoid rebuilding with overlay state.
class _CenterTapDetector extends StatelessWidget {
  final VoidCallback onTap;

  const _CenterTapDetector({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final screenH = MediaQuery.sizeOf(context).height;
    final third = screenH / 3;
    return Positioned(
      top: third,
      left: 0,
      right: 0,
      height: third,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: onTap,
      ),
    );
  }
}

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// Settings Modal — Extracted from the 400-line build method
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class _SettingsModalContent extends StatefulWidget {
  final ReadingSettings settings;
  final ValueChanged<ReadingSettings> onSettingsChanged;

  const _SettingsModalContent({
    required this.settings,
    required this.onSettingsChanged,
  });

  @override
  State<_SettingsModalContent> createState() => _SettingsModalContentState();
}

class _SettingsModalContentState extends State<_SettingsModalContent> {
  late ReadingSettings _localSettings;

  @override
  void initState() {
    super.initState();
    _localSettings = widget.settings;
  }

  void _update(ReadingSettings updated) {
    setState(() => _localSettings = updated);
    widget.onSettingsChanged(updated);
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: _localSettings.mutedColor,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _localSettings.menuColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
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
                    color: _localSettings.mutedColor.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // ── Theme ──
              _buildSectionTitle('Theme'),
              _buildThemeChips(),

              // ── Font Size ──
              _buildSectionTitle('Font Size'),
              _buildFontSizeChips(),

              // ── Font Options ──
              _buildSectionTitle('Font Options'),
              _buildFontFamilyChips(),

              // ── Text Alignment ──
              _buildSectionTitle('Text Alignment'),
              _buildTextAlignButtons(),

              // ── Content Density ──
              _buildSectionTitle('Content Density'),
              _buildContentDensityChips(),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThemeChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: AppTheme.values.map((theme) {
            final isSelected = _localSettings.effectiveTheme == theme;
            final themeName = theme.name.toUpperCase().replaceAll(
              'SOFTLIGHT',
              'SOFT LIGHT',
            );

            final dummySettings = ReadingSettings(appTheme: theme);
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
                    _update(_localSettings.copyWith(readerTheme: theme));
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildFontSizeChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: ReaderFontSize.values.map((size) {
          final isSelected = _localSettings.fontSize == size;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(
                  size.name.toUpperCase(),
                  style: TextStyle(
                    color: _localSettings.textColor,
                    fontSize: 13,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                selectedColor: _localSettings.backgroundColor,
                backgroundColor: _localSettings.backgroundColor,
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
                    _update(_localSettings.copyWith(fontSize: size));
                  }
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildFontFamilyChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: ReaderFontFamily.values.map((family) {
            final isSelected = _localSettings.fontFamily == family;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(
                  family.name
                      .replaceAll('Mono', ' Mono')
                      .replaceAll('Neue', ' Neue')
                      .toUpperCase(),
                  style: TextStyle(
                    color: _localSettings.textColor,
                    fontSize: 12,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                selectedColor: _localSettings.backgroundColor,
                backgroundColor: _localSettings.backgroundColor,
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
                    _update(_localSettings.copyWith(fontFamily: family));
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildTextAlignButtons() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: ReaderTextAlign.values.map((align) {
          final isSelected = _localSettings.textAlign == align;
          return IconButton(
            icon: Icon(
              align == ReaderTextAlign.left
                  ? Icons.format_align_left
                  : align == ReaderTextAlign.center
                  ? Icons.format_align_center
                  : align == ReaderTextAlign.right
                  ? Icons.format_align_right
                  : Icons.format_align_justify,
              color: isSelected
                  ? const Color(0xFFE85D04)
                  : _localSettings.textColor,
            ),
            onPressed: () {
              _update(_localSettings.copyWith(textAlign: align));
            },
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContentDensityChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: ContentDensity.values.map((density) {
          final isSelected = _localSettings.contentDensity == density;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: ChoiceChip(
                label: Text(
                  density.name.toUpperCase(),
                  style: TextStyle(
                    color: _localSettings.textColor,
                    fontSize: 10,
                    fontWeight: isSelected
                        ? FontWeight.bold
                        : FontWeight.normal,
                  ),
                ),
                selected: isSelected,
                selectedColor: _localSettings.backgroundColor,
                backgroundColor: _localSettings.backgroundColor,
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
                    _update(_localSettings.copyWith(contentDensity: density));
                  }
                },
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
