import 'package:flutter/foundation.dart';

/// Types of content in a book chunk.
enum BookChunkType { text, image }

/// Whether this chunk belongs to front/back matter or main content.
enum ChunkSection {
  /// Non-content pages: copyright, preface, TOC, dedication, etc.
  frontMatter,

  /// Actual book content (chapters).
  content,
}

/// A link within a text chunk.
@immutable
class LinkMetadata {
  final int start;
  final int end;
  final String url;

  const LinkMetadata({
    required this.start,
    required this.end,
    required this.url,
  });

  LinkMetadata copyWith({int? start, int? end, String? url}) {
    return LinkMetadata(
      start: start ?? this.start,
      end: end ?? this.end,
      url: url ?? this.url,
    );
  }
}

/// Represents a single readable chunk (card) of content from an EPUB book.
@immutable
class BookChunk {
  final int index;
  final BookChunkType type;
  final ChunkSection section;
  final String? text;
  final Uint8List? imageBytes;
  final List<LinkMetadata>? links;

  /// Whether this chunk represents a heading (h1-h6).
  final bool isHeading;

  /// The EPUB source file key this chunk was parsed from (e.g. "preface.xhtml").
  /// Used to group front-matter chunks by their originating file.
  final String? sourceFile;

  const BookChunk({
    required this.index,
    required this.type,
    this.section = ChunkSection.content,
    this.text,
    this.imageBytes,
    this.links,
    this.isHeading = false,
    this.sourceFile,
  });

  /// Create a copy with a different section.
  BookChunk withSection(ChunkSection newSection) => BookChunk(
    index: index,
    type: type,
    section: newSection,
    text: text,
    imageBytes: imageBytes,
    links: links,
    isHeading: isHeading,
    sourceFile: sourceFile,
  );

  BookChunk copyWith({
    int? index,
    BookChunkType? type,
    ChunkSection? section,
    String? text,
    Uint8List? imageBytes,
    List<LinkMetadata>? links,
    bool? isHeading,
    String? sourceFile,
  }) {
    return BookChunk(
      index: index ?? this.index,
      type: type ?? this.type,
      section: section ?? this.section,
      text: text ?? this.text,
      imageBytes: imageBytes ?? this.imageBytes,
      links: links ?? this.links,
      isHeading: isHeading ?? this.isHeading,
      sourceFile: sourceFile ?? this.sourceFile,
    );
  }
}
