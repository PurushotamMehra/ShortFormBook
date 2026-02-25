import 'package:flutter/material.dart';

import '../models/book_chunk.dart';
import '../models/reading_settings.dart';
import '../screens/reader_screen.dart'
    show kBoundaryBottom, kBoundaryTop, kContentPaddingH;

class ReadingCard extends StatelessWidget {
  final BookChunk chunk;
  final ReadingSettings settings;
  final Function(String url)? onLinkTap;
  final bool isBookmarked;
  final VoidCallback? onBookmarkTap;
  final VoidCallback? onBookmarkLongPress;

  const ReadingCard({
    super.key,
    required this.chunk,
    required this.settings,
    this.onLinkTap,
    this.isBookmarked = false,
    this.onBookmarkTap,
    this.onBookmarkLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = settings.backgroundColor;
    final textAlign =
        chunk.isHeading ? TextAlign.center : settings.resolvedTextAlign;

    final textStyle = settings.getTextStyle(isHeading: chunk.isHeading);

    // Safe-area insets: status bar at top, nav bar at bottom.
    // The content must sit between the two boundary lines, which are
    // positioned at (safeArea.top + kBoundaryTop) from the top and
    // (safeArea.bottom + kBoundaryBottom) from the bottom.
    final safeArea = MediaQuery.paddingOf(context);
    final topPad = safeArea.top + kBoundaryTop;
    final bottomPad = safeArea.bottom + kBoundaryBottom;

    return RepaintBoundary(
      child: Container(
        color: bgColor,
        padding: EdgeInsets.fromLTRB(
          kContentPaddingH,
          topPad,
          kContentPaddingH,
          bottomPad,
        ),
        child: Stack(
          children: [
            // ── Main content (centered vertically inside the bounded area) ──
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chunk.type == BookChunkType.image &&
                      chunk.imageBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Image.memory(
                        chunk.imageBytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
                  if (chunk.text != null && chunk.text!.isNotEmpty)
                    Text(
                      chunk.text!,
                      style: textStyle,
                      textAlign: textAlign,
                    ),
                ],
              ),
            ),

            // ── Bookmark icon ──
            if (onBookmarkTap != null || onBookmarkLongPress != null)
              Positioned(
                top: 0,
                right: 0,
                child: GestureDetector(
                  onTap: onBookmarkTap,
                  onLongPress: onBookmarkLongPress,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isBookmarked
                          ? bgColor.withValues(alpha: 0.8)
                          : Colors.transparent,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isBookmarked ? Icons.bookmark : Icons.bookmark_border,
                      color: isBookmarked ? Colors.blue : Colors.transparent,
                      size: 28,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
