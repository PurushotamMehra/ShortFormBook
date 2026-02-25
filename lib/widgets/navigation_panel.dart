import 'package:flutter/material.dart';

import '../models/bookmark.dart';

/// A modal bottom sheet panel with two tabs: Bookmarks and Chapters.
///
/// Chapters tab shows expandable sections with hierarchy. Non-chapter
/// entries (cover, title page, copyright, etc.) are grouped under
/// "Book Details". The section containing the current page is
/// auto-expanded on open.
class NavigationPanel extends StatefulWidget {
  final List<Bookmark> bookmarks;
  final int? tempBookmarkIndex;
  final List<ChapterInfo> chapters;
  final int currentPage;
  final ValueChanged<int> onNavigate;

  const NavigationPanel({
    super.key,
    required this.bookmarks,
    required this.tempBookmarkIndex,
    required this.chapters,
    required this.currentPage,
    required this.onNavigate,
  });

  /// Convenience entry point — show as a modal bottom sheet.
  static void show(
    BuildContext context, {
    required List<Bookmark> bookmarks,
    required int? tempBookmarkIndex,
    required List<ChapterInfo> chapters,
    required int currentPage,
    required ValueChanged<int> onNavigate,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NavigationPanel(
        bookmarks: bookmarks,
        tempBookmarkIndex: tempBookmarkIndex,
        chapters: chapters,
        currentPage: currentPage,
        onNavigate: (index) {
          Navigator.pop(context); // close sheet first
          onNavigate(index);
        },
      ),
    );
  }

  @override
  State<NavigationPanel> createState() => _NavigationPanelState();
}

class _NavigationPanelState extends State<NavigationPanel> {
  // ── Heuristic keywords for non-chapter / front-matter items ──
  static const _frontMatterPatterns = [
    'cover',
    'title page',
    'titlepage',
    'copyright',
    'dedication',
    'epigraph',
    'foreword',
    'preface',
    'acknowledgment',
    'acknowledgement',
    'about the author',
    'about the book',
    'also by',
    'other books',
    'table of contents',
    'contents',
    'half title',
    'halftitle',
    'frontispiece',
    'colophon',
    'publisher',
    'edition',
    'isbn',
    'introduction',
  ];

  /// Returns true if a chapter title looks like front/back matter.
  bool _isFrontMatter(String title) {
    final lower = title.toLowerCase().trim();
    return _frontMatterPatterns.any((p) => lower.contains(p));
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Container(
        height: MediaQuery.of(context).size.height * 0.6,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 4),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[700],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Tab bar
            TabBar(
              labelColor: Theme.of(context).colorScheme.onSurface,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Theme.of(context).colorScheme.primary,
              indicatorWeight: 3,
              labelStyle: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
              tabs: const [
                Tab(text: 'Bookmarks'),
                Tab(text: 'Chapters'),
              ],
            ),
            Divider(height: 1, color: Colors.grey[800]),
            // Tab views
            Expanded(
              child: TabBarView(
                children: [_buildBookmarksList(), _buildChaptersList()],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bookmarks Tab ───────────────────────────────────────────────────

  Widget _buildBookmarksList() {
    final hasTemp = widget.tempBookmarkIndex != null;
    final totalItems = widget.bookmarks.length + (hasTemp ? 1 : 0);

    if (totalItems == 0) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.bookmark_border, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text(
              'No bookmarks yet',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap the bookmark icon on any card to add one',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: totalItems,
      separatorBuilder: (_, __) =>
          Divider(height: 1, indent: 56, color: Colors.grey[800]),
      itemBuilder: (context, index) {
        // Temp bookmark always shows first
        if (hasTemp && index == 0) {
          return _buildNavTile(
            icon: Icons.history,
            iconColor: Colors.grey,
            title: '↩ Back to page ${widget.tempBookmarkIndex! + 1}',
            subtitle: 'Last reading position',
            onTap: () => widget.onNavigate(widget.tempBookmarkIndex!),
          );
        }

        final bIndex = hasTemp ? index - 1 : index;
        final bookmark = widget.bookmarks[bIndex];

        return _buildNavTile(
          icon: Icons.bookmark,
          iconColor: Theme.of(context).colorScheme.primary,
          title: bookmark.name,
          subtitle: 'Page ${bookmark.chunkIndex + 1}',
          onTap: () => widget.onNavigate(bookmark.chunkIndex),
        );
      },
    );
  }

  // ── Chapters Tab ────────────────────────────────────────────────────

  Widget _buildChaptersList() {
    if (widget.chapters.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.menu_book, size: 48, color: Colors.grey),
            SizedBox(height: 12),
            Text(
              'No chapters found',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Separate front-matter from real chapters.
    final List<ChapterInfo> bookDetails = [];
    final List<ChapterInfo> chapterContent = [];

    for (final ch in widget.chapters) {
      if (_isFrontMatter(ch.title)) {
        bookDetails.add(ch);
      } else {
        chapterContent.add(ch);
      }
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // "Book Details" expandable — collapsed by default, contains
        // front-matter items as a flat list.
        if (bookDetails.isNotEmpty)
          _buildExpandableSection(
            title: 'Book Details',
            icon: Icons.info_outline,
            iconColor: Colors.grey,
            initiallyExpanded: false,
            children: bookDetails,
          ),

        // Main chapter content — each top-level entry with children
        // becomes expandable; leaf entries are plain tiles.
        ...chapterContent.map((ch) => _buildChapterEntry(ch)),
      ],
    );
  }

  /// Build a single chapter entry. If it has children, render as an
  /// expandable tile; otherwise render as a plain tile.
  Widget _buildChapterEntry(ChapterInfo chapter) {
    if (chapter.children.isEmpty) {
      // Leaf node — simple tile.
      return _buildNavTile(
        icon: Icons.article_outlined,
        iconColor: Theme.of(context).colorScheme.onSurface,
        title: chapter.title,
        subtitle: 'Page ${chapter.chunkIndex + 1}',
        onTap: () => widget.onNavigate(chapter.chunkIndex),
      );
    }

    // Has children → expandable.
    // Auto-expand if the current page falls within this section's range.
    final containsCurrentPage = _sectionContainsPage(
      chapter,
      widget.currentPage,
    );

    return _buildExpandableSection(
      title: chapter.title,
      icon: Icons.folder_outlined,
      iconColor: Theme.of(context).colorScheme.onSurface,
      initiallyExpanded: containsCurrentPage,
      onHeaderTap: () => widget.onNavigate(chapter.chunkIndex),
      children: chapter.children,
    );
  }

  /// Check if the current page falls within a section's chunk range.
  /// A section "owns" pages from its chunkIndex up to (but not including)
  /// the next sibling's chunkIndex.
  bool _sectionContainsPage(ChapterInfo section, int page) {
    if (page < section.chunkIndex) return false;

    // Flatten all descendant chunk indices to find the max.
    int maxIdx = section.chunkIndex;
    void walkMax(ChapterInfo ch) {
      if (ch.chunkIndex > maxIdx) maxIdx = ch.chunkIndex;
      for (final child in ch.children) {
        walkMax(child);
      }
    }

    walkMax(section);

    // The page is "in" this section if it's between the section start
    // and the highest chunk index in its subtree (inclusive +50 for buffer
    // since chunk indices are approximate).
    return page >= section.chunkIndex && page <= maxIdx + 50;
  }

  /// Build an expandable section with a title header and child entries.
  Widget _buildExpandableSection({
    required String title,
    required IconData icon,
    required Color iconColor,
    required bool initiallyExpanded,
    required List<ChapterInfo> children,
    VoidCallback? onHeaderTap,
  }) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        leading: Icon(icon, color: iconColor, size: 24),
        title: GestureDetector(
          onTap: onHeaderTap,
          child: Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Theme.of(context).colorScheme.onSurface,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        initiallyExpanded: initiallyExpanded,
        tilePadding: const EdgeInsets.symmetric(horizontal: 16),
        childrenPadding: const EdgeInsets.only(left: 16),
        iconColor: Colors.grey,
        collapsedIconColor: Colors.grey,
        children: children.map((ch) {
          if (ch.children.isNotEmpty) {
            // Nested sub-section.
            return _buildChapterEntry(ch);
          }
          return _buildNavTile(
            icon: Icons.article_outlined,
            iconColor: Theme.of(context).colorScheme.onSurface,
            title: ch.title,
            subtitle: 'Page ${ch.chunkIndex + 1}',
            onTap: () => widget.onNavigate(ch.chunkIndex),
          );
        }).toList(),
      ),
    );
  }

  // ── Shared tile builder ─────────────────────────────────────────────

  Widget _buildNavTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: iconColor, size: 24),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).colorScheme.onSurface,
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            )
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      dense: true,
      visualDensity: VisualDensity.compact,
      onTap: onTap,
    );
  }
}
