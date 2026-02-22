import 'package:flutter/material.dart';

import '../models/book_chunk.dart';
import '../models/reading_settings.dart';

class ReadingCard extends StatelessWidget {
  final BookChunk chunk;
  final ReadingSettings? settings;
  final Function(String url)? onLinkTap;
  final bool isBookmarked;
  final VoidCallback? onBookmarkTap;
  final VoidCallback? onBookmarkLongPress;

  const ReadingCard({
    super.key,
    required this.chunk,
    this.settings,
    this.onLinkTap,
    this.isBookmarked = false,
    this.onBookmarkTap,
    this.onBookmarkLongPress,
  });

  @override
  Widget build(BuildContext context) {
    // If we have settings, apply them. Otherwise, provide defaults for compiling.
    final bgColor = settings?.backgroundColor(context) ?? const Color(0xFFFAF8F5);
    
    // Default to left align if settings not provided 
    final textAlign = settings?.textAlign == ReaderTextAlign.center ? TextAlign.center 
        : settings?.textAlign == ReaderTextAlign.right ? TextAlign.right 
        : settings?.textAlign == ReaderTextAlign.justify ? TextAlign.justify 
        : TextAlign.left;

    final horizontalPadding = 24.0;

    // Use passed settings or fallback defaults
    final effectiveSettings = settings ?? const ReadingSettings();

    TextStyle textStyle = effectiveSettings.getTextStyle(context, isHeading: chunk.isHeading);

    return Container(
      color: bgColor,
      child: Stack(
        children: [
          Center(
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(horizontalPadding, 52, horizontalPadding, 62),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (chunk.type == BookChunkType.image && chunk.imageBytes != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Image.memory(
                        chunk.imageBytes! as dynamic, 
                        fit: BoxFit.contain,
                      ),
                    ),
                  if (chunk.text != null && chunk.text!.isNotEmpty)
                    Text(
                      chunk.text!,
                      style: textStyle,
                      textAlign: chunk.isHeading ? TextAlign.center : textAlign,
                    ),
                ],
              ),
            ),
          ),
          
          if (onBookmarkTap != null || onBookmarkLongPress != null)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              right: 16,
              child: GestureDetector(
                onTap: onBookmarkTap,
                onLongPress: onBookmarkLongPress,
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isBookmarked ? bgColor.withValues(alpha: 0.8) : Colors.transparent,
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
    );
  }
}
