import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/book_chunk.dart';
import '../models/reading_settings.dart';

/// A fullscreen page for a single front-matter section (cover, copyright,
/// preface, table of contents, etc.).
///
/// Content is scrollable. When the user scrolls past the top or bottom edge,
/// accumulated overscroll triggers navigation to the previous/next page.
class FrontMatterPage extends StatefulWidget {
  final BookChunk chunk;
  final ReadingSettings settings;
  final Function(String url)? onLinkTap;

  /// Whether this is the last front-matter page before content begins.
  final bool isLastFrontMatter;

  /// Tapped on the last FM page to jump to content.
  final VoidCallback? onStartReading;

  /// Called when overscrolling past the bottom edge (go to next page).
  final VoidCallback? onNavigateNext;

  /// Called when overscrolling past the top edge (go to previous page).
  final VoidCallback? onNavigatePrevious;

  const FrontMatterPage({
    super.key,
    required this.chunk,
    required this.settings,
    this.onLinkTap,
    this.isLastFrontMatter = false,
    this.onStartReading,
    this.onNavigateNext,
    this.onNavigatePrevious,
  });

  @override
  State<FrontMatterPage> createState() => _FrontMatterPageState();
}

class _FrontMatterPageState extends State<FrontMatterPage> {
  final ScrollController _scrollController = ScrollController();
  double _overscrollAccumulator = 0;
  bool _isNavigating = false;

  /// How many overscroll pixels before we trigger a page change.
  static const _overscrollThreshold = 70.0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification) {
      // Reset on each new drag.
      _overscrollAccumulator = 0;
      _isNavigating = false;
      return false;
    }

    if (notification is OverscrollNotification && !_isNavigating) {
      _overscrollAccumulator += notification.overscroll;

      // Overscroll past bottom → next page.
      if (_overscrollAccumulator > _overscrollThreshold) {
        _isNavigating = true;
        widget.onNavigateNext?.call();
        return true;
      }

      // Overscroll past top → previous page.
      if (_overscrollAccumulator < -_overscrollThreshold) {
        _isNavigating = true;
        widget.onNavigatePrevious?.call();
        return true;
      }
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final bgColor = widget.settings.backgroundColor(context);
    final textColor = widget.settings.textColor(context);
    final mutedColor = widget.settings.mutedColor(context);
    final isDark = widget.settings.isDark(context);
    final topPad = MediaQuery.of(context).padding.top;
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Container(
      color: bgColor,
      width: double.infinity,
      height: double.infinity,
      child: Column(
        children: [
          // ── Fixed top: label ──
          SizedBox(height: topPad + 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.06)
                  : Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'FRONT MATTER',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.5,
                color: mutedColor.withValues(alpha: 0.5),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // ── Scrollable content ──
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: _handleScrollNotification,
              child: SingleChildScrollView(
                controller: _scrollController,
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 28),
                child: _buildContent(context, textColor, mutedColor),
              ),
            ),
          ),

          // ── "Start Reading" button on last FM page only ──
          if (widget.isLastFrontMatter && widget.onStartReading != null) ...[
            const SizedBox(height: 12),
            _buildStartReadingButton(isDark),
          ],

          SizedBox(height: bottomPad + 8),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    Color textColor,
    Color mutedColor,
  ) {
    // ── Image chunk ──
    if (widget.chunk.type == BookChunkType.image) {
      if (widget.chunk.imageBytes == null || widget.chunk.imageBytes!.isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.7,
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                Uint8List.fromList(widget.chunk.imageBytes!),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
        ),
      );
    }

    // ── Text chunk ──
    final text = widget.chunk.text ?? '';
    if (text.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: RichText(
        textAlign: TextAlign.left,
        text: TextSpan(
          style: _textStyle(textColor),
          children: _buildSpans(textColor),
        ),
      ),
    );
  }

  Widget _buildStartReadingButton(bool isDark) {
    return GestureDetector(
      onTap: widget.onStartReading,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isDark
                ? [const Color(0xFF5C7AEA), const Color(0xFF7B68EE)]
                : [const Color(0xFF4A90D9), const Color(0xFF5C7AEA)],
          ),
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF5C7AEA).withValues(alpha: 0.3),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Start Reading',
              style: GoogleFonts.inter(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 0.3,
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              size: 20,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  TextStyle _textStyle(Color textColor) {
    if (widget.chunk.isHeading) {
      return GoogleFonts.inter(
        fontSize: 18, // slightly larger
        fontWeight: FontWeight.w700, // bolder
        color: textColor, // not faded like normal text
        height: 1.4,
        letterSpacing: 0.3,
      );
    }
    return GoogleFonts.inter(
      fontSize: 13,
      fontWeight: FontWeight.w400,
      color: textColor.withValues(alpha: 0.65),
      height: 1.55,
      letterSpacing: 0.1,
    );
  }

  List<InlineSpan> _buildSpans(Color textColor) {
    final text = widget.chunk.text ?? '';
    final links = widget.chunk.links ?? [];

    if (links.isEmpty) return [TextSpan(text: text)];

    final spans = <InlineSpan>[];
    int currentPos = 0;

    for (final link in links) {
      final start = link.start.clamp(0, text.length);
      final end = link.end.clamp(start, text.length);
      if (start >= end) continue;

      if (start > currentPos) {
        spans.add(TextSpan(text: text.substring(currentPos, start)));
      }

      spans.add(
        TextSpan(
          text: text.substring(start, end),
          style: const TextStyle(
            color: Color(0xFF5C7AEA),
            decoration: TextDecoration.underline,
            decorationColor: Color(0xFF5C7AEA),
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () => widget.onLinkTap?.call(link.url),
        ),
      );
      currentPos = end;
    }

    if (currentPos < text.length) {
      spans.add(TextSpan(text: text.substring(currentPos)));
    }

    return spans;
  }
}
