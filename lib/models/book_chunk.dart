
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
class LinkMetadata {
  final int start;
  final int end;
  final String url;

  const LinkMetadata({
    required this.start,
    required this.end,
    required this.url,
  });
}

/// Represents a single readable chunk (card) of content from an EPUB book.
class BookChunk {
  final int index;
  final BookChunkType type;
  final ChunkSection section;
  final String? text;
  final List<int>? imageBytes; // store as raw bytes
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
}
