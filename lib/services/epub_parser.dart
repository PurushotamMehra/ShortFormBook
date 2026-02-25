import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:epubx/epubx.dart';
import 'package:flutter/services.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;

import '../models/book_chunk.dart';
import '../models/bookmark.dart';

/// Service responsible for loading, parsing, and chunking EPUB content.
///
/// Produces small, paragraph-sized chunks for a TikTok/Reels-style
/// vertical-swipe reading experience. Each card holds roughly one paragraph
/// so the reader never feels overwhelmed.
class EpubParserService {
  /// Target maximum words per card — keeps each card short and digestible.
  static const int _targetWords = 50;

  /// Hard ceiling — if a single paragraph exceeds this, it gets split.
  static const int _hardMaxWords = 80;

  // ─── Public API ──────────────────────────────────────────────────────

  /// Loads the EPUB file from the given [assetPath] (asset bundle).
  Future<
    ({
      String title,
      List<BookChunk> chunks,
      Map<String, int> anchorMap,
      List<ChapterInfo> chapters,
    })
  >
  loadAndParse(String assetPath) async {
    final ByteData data = await rootBundle.load(assetPath);
    final Uint8List bytes = data.buffer.asUint8List();
    return _parseBytes(bytes);
  }

  /// Loads the EPUB file from a local [File].
  Future<
    ({
      String title,
      List<BookChunk> chunks,
      Map<String, int> anchorMap,
      List<ChapterInfo> chapters,
    })
  >
  loadAndParseFromFile(File file) async {
    final Uint8List bytes = await file.readAsBytes();
    return _parseBytes(bytes);
  }

  // ─── Core parsing ────────────────────────────────────────────────────

  Future<
    ({
      String title,
      List<BookChunk> chunks,
      Map<String, int> anchorMap,
      List<ChapterInfo> chapters,
    })
  >
  _parseBytes(Uint8List bytes) async {
    final EpubBook book = await EpubReader.readBook(bytes);
    final String title = book.Title ?? 'Unknown Title';

    try {
      final result = _extractContent(book);
      debugPrint(
        'EpubParser: parsed "$title" → ${result.chunks.length} chunks, '
        '${result.anchorMap.length} anchors, ${result.chapters.length} chapters',
      );

      if (result.chunks.isEmpty) {
        debugPrint(
          'EpubParser: DOM parsing produced 0 chunks, trying fallback',
        );
        final fallback = _fallbackExtract(book);
        return (
          title: title,
          chunks: fallback,
          anchorMap: <String, int>{},
          chapters: <ChapterInfo>[],
        );
      }
      return (
        title: title,
        chunks: result.chunks,
        anchorMap: result.anchorMap,
        chapters: result.chapters,
      );
    } catch (e, stack) {
      debugPrint('EpubParser: _extractContent failed: $e\n$stack');
      final fallback = _fallbackExtract(book);
      return (
        title: title,
        chunks: fallback,
        anchorMap: <String, int>{},
        chapters: <ChapterInfo>[],
      );
    }
  }

  // ─── Front-matter detection ────────────────────────────────────────

  /// Filename patterns that indicate a file is NOT main book content.
  static const _frontMatterFilePatterns = [
    'cover',
    'title',
    'titlepage',
    'copyright',
    'rights',
    'dedication',
    'epigraph',
    'foreword',
    'preface',
    'prologue',
    'acknowledgment',
    'acknowledgement',
    'about',
    'also',
    'toc',
    'contents',
    'nav',
    'index',
    'half-title',
    'halftitle',
    'frontispiece',
    'colophon',
    'publisher',
    'edition',
    'isbn',
    'introduction',
    'frontmatter',
    'backmatter',
    'endnotes',
    'appendix',
    'glossary',
    'bibliography',
  ];

  /// Check whether a content-map key (HTML filename) looks like front matter.
  bool _isFrontMatterFile(String key) {
    final lower = p
        .basename(key)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
    return _frontMatterFilePatterns.any(
      (pat) => lower.contains(pat.replaceAll('-', '')),
    );
  }

  /// Determine the first content-map key that is actual book content,
  /// by also consulting the EPUB's Table of Contents chapter titles.
  String? _findFirstContentKey(
    Map<String, EpubTextContentFile> contentMap,
    EpubBook book,
  ) {
    // Gather the set of content filenames referenced by TOC chapters
    // whose titles look like real chapters (i.e. NOT front matter).
    final tocChapters = book.Chapters ?? [];
    final chapterFiles = <String>{};

    void collectChapterFiles(List<EpubChapter> chapters) {
      for (final ch in chapters) {
        final title = (ch.Title ?? '').toLowerCase().trim();
        final isFM = _frontMatterFilePatterns.any((pat) => title.contains(pat));
        if (!isFM && ch.ContentFileName != null) {
          chapterFiles.add(ch.ContentFileName!);
          chapterFiles.add(p.basename(ch.ContentFileName!));
        }
        if (ch.SubChapters != null) collectChapterFiles(ch.SubChapters!);
      }
    }

    collectChapterFiles(tocChapters);

    // Walk the content map in order; first key that is either:
    // (a) referenced by a real TOC chapter, or
    // (b) does NOT match any front-matter filename pattern
    // … is our first content file.
    for (final key in contentMap.keys) {
      final baseName = p.basename(key);
      if (chapterFiles.contains(key) || chapterFiles.contains(baseName)) {
        return key;
      }
    }
    // Fallback: first file that doesn't look like front matter by name.
    for (final key in contentMap.keys) {
      if (!_isFrontMatterFile(key)) return key;
    }
    return contentMap.keys.firstOrNull;
  }

  // ─── DOM-based extraction ────────────────────────────────────────────

  ({
    List<BookChunk> chunks,
    Map<String, int> anchorMap,
    List<ChapterInfo> chapters,
  })
  _extractContent(EpubBook book) {
    final List<BookChunk> chunks = [];
    final Map<String, int> anchorMap = {};
    int chunkIndex = 0;

    final contentMap = book.Content?.Html;
    if (contentMap == null || contentMap.isEmpty) {
      return (chunks: chunks, anchorMap: anchorMap, chapters: <ChapterInfo>[]);
    }

    // Determine which key marks the start of real content.
    final firstContentKey = _findFirstContentKey(contentMap, book);
    bool reachedContent = false;

    // Current card buffer.
    final StringBuffer textBuffer = StringBuffer();
    final List<LinkMetadata> linkBuffer = [];
    // Track the section for the current file being parsed.
    ChunkSection currentSection = ChunkSection.frontMatter;
    // Track the current source file key for grouping.
    String currentKey = '';
    // Track if parsing inside a heading tag (h1-h6).
    bool currentIsHeading = false;

    // Flush the buffer into a new card chunk.
    void flush() {
      if (textBuffer.isEmpty) return;
      final text = textBuffer.toString().trim();
      if (text.isEmpty) {
        textBuffer.clear();
        linkBuffer.clear();
        return;
      }

      // If the text is small enough, emit as a single chunk.
      if (_wordCount(text) <= _hardMaxWords) {
        chunks.add(
          BookChunk(
            index: chunkIndex++,
            type: BookChunkType.text,
            text: text,
            section: currentSection,
            sourceFile: currentKey,
            links: List.from(linkBuffer),
            isHeading: currentIsHeading,
          ),
        );
      } else {
        // Text is too large — split by sentence, but drop links
        // (links span across the original buffer and can't be mapped to sub-chunks).
        final subTexts = _splitBySentence(text, _targetWords);
        for (final sub in subTexts) {
          chunks.add(
            BookChunk(
              index: chunkIndex++,
              type: BookChunkType.text,
              text: sub,
              section: currentSection,
              sourceFile: currentKey,
              isHeading: currentIsHeading,
            ),
          );
        }
      }
      textBuffer.clear();
      linkBuffer.clear();
    }

    debugPrint('EpubParser: HTML content entries = ${contentMap.length}');
    debugPrint('EpubParser: first content key = $firstContentKey');

    for (final entry in contentMap.entries) {
      final key = entry.key;
      final htmlContent = entry.value;
      final htmlString = htmlContent.Content;
      if (htmlString == null || htmlString.isEmpty) continue;

      // Track which file we're parsing.
      currentKey = key;

      // Determine section for this file.
      if (!reachedContent) {
        if (key == firstContentKey ||
            p.basename(key) ==
                (firstContentKey != null ? p.basename(firstContentKey) : '')) {
          reachedContent = true;
          currentSection = ChunkSection.content;
        } else {
          currentSection = ChunkSection.frontMatter;
        }
      } else {
        // After we've reached content, check if this is back matter.
        currentSection = _isFrontMatterFile(key)
            ? ChunkSection.frontMatter
            : ChunkSection.content;
      }

      try {
        final document = html_parser.parse(htmlString);
        final body = document.body;
        if (body == null) continue;

        // Recursive DOM walker — flushes at every block-level boundary.
        void visit(dom.Node node) {
          if (node is dom.Element) {
            // Record anchor IDs so internal links can jump here.
            if (node.id.isNotEmpty) {
              // Point to the NEXT chunk that will be created.
              anchorMap[node.id] = chunkIndex;
            }
            final nameAttr = node.attributes['name'];
            if (nameAttr != null && nameAttr.isNotEmpty) {
              anchorMap[nameAttr] = chunkIndex;
            }

            // ── Images ──
            if (node.localName == 'img') {
              flush();
              final src = node.attributes['src'];
              if (src != null) {
                final imageBytes = _resolveImage(book, src);
                if (imageBytes != null) {
                  chunks.add(
                    BookChunk(
                      index: chunkIndex++,
                      type: BookChunkType.image,
                      section: currentSection,
                      sourceFile: currentKey,
                      imageBytes: imageBytes,
                    ),
                  );
                }
              }
              return;
            }

            // ── Links (<a>) ──
            if (node.localName == 'a' && node.attributes.containsKey('href')) {
              final href = node.attributes['href']!;
              final startIdx = textBuffer.length;
              for (final child in node.nodes) {
                visit(child);
              }
              final endIdx = textBuffer.length;
              if (endIdx > startIdx) {
                linkBuffer.add(
                  LinkMetadata(start: startIdx, end: endIdx, url: href),
                );
              }
              return;
            }

            // ── Block elements → flush BEFORE entering ──
            final isBlock = _blockTags.contains(node.localName);
            final isHeadingNode = [
              'h1',
              'h2',
              'h3',
              'h4',
              'h5',
              'h6',
            ].contains(node.localName);

            if (isBlock) {
              flush(); // each block element starts a new card
            }

            final wasHeading = currentIsHeading;
            if (isHeadingNode) currentIsHeading = true;

            // Recurse into children.
            for (final child in node.nodes) {
              visit(child);
            }

            if (isBlock) {
              flush(); // close the card after the block element
            }
            if (isHeadingNode) currentIsHeading = wasHeading;
          } else if (node is dom.Text) {
            final text = node.text.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (text.isNotEmpty) {
              if (textBuffer.isNotEmpty &&
                  !textBuffer.toString().endsWith(' ')) {
                textBuffer.write(' ');
              }
              textBuffer.write(text);
            }
          }
        }

        visit(body);
        flush(); // end of chapter
      } catch (e) {
        debugPrint('EpubParser: error parsing chapter: $e');
      }
    }

    // Merge tiny chunks (< 10 words) with the next chunk to avoid
    // cards with just one or two words.
    final merged = _mergeTinyChunks(chunks);

    // Extract chapters from EPUB Table of Contents.
    final chapters = _extractTocChapters(book, merged, contentMap);

    // Log section breakdown.
    final fmCount = merged
        .where((c) => c.section == ChunkSection.frontMatter)
        .length;
    final contentCount = merged
        .where((c) => c.section == ChunkSection.content)
        .length;
    debugPrint(
      'EpubParser: $fmCount front-matter chunks, $contentCount content chunks',
    );

    return (chunks: merged, anchorMap: anchorMap, chapters: chapters);
  }

  // ─── Post-processing ─────────────────────────────────────────────────

  /// Merge very small consecutive text chunks so we don't get 1-word cards.
  List<BookChunk> _mergeTinyChunks(List<BookChunk> input) {
    if (input.isEmpty) return input;

    final List<BookChunk> result = [];
    BookChunk? pending;
    int idx = 0;

    for (final chunk in input) {
      if (chunk.type != BookChunkType.text) {
        // Flush pending, then add the image.
        if (pending != null) {
          result.add(
            BookChunk(
              index: idx++,
              type: BookChunkType.text,
              section: pending.section,
              sourceFile: pending.sourceFile,
              text: pending.text,
              links: pending.links,
              isHeading: pending.isHeading,
            ),
          );
          pending = null;
        }
        result.add(
          BookChunk(
            index: idx++,
            type: BookChunkType.image,
            section: chunk.section,
            sourceFile: chunk.sourceFile,
            imageBytes: chunk.imageBytes,
          ),
        );
        continue;
      }

      final text = chunk.text ?? '';
      if (text.isEmpty) continue;

      if (pending == null) {
        pending = chunk;
        continue;
      }

      final pendingText = pending.text ?? '';
      final pendingWords = _wordCount(pendingText);
      final chunkWords = _wordCount(text);

      // Only merge chunks from the same section AND same source file. Do not merge headings with normal text
      if (pendingWords < 15 &&
          (pendingWords + chunkWords) <= _hardMaxWords &&
          pending.section == chunk.section &&
          pending.sourceFile == chunk.sourceFile &&
          pending.isHeading == chunk.isHeading) {
        pending = BookChunk(
          index: 0, // re-index later
          type: BookChunkType.text,
          section: pending.section,
          sourceFile: pending.sourceFile,
          isHeading: pending.isHeading,
          text: '$pendingText\n\n$text',
          links: [
            ...?pending.links,
            // Offset the current chunk's links by the combined text position
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
      } else {
        // Emit pending and start fresh.
        result.add(
          BookChunk(
            index: idx++,
            type: BookChunkType.text,
            section: pending.section,
            sourceFile: pending.sourceFile,
            text: pendingText,
            links: pending.links,
            isHeading: pending.isHeading,
          ),
        );
        pending = chunk;
      }
    }

    if (pending != null) {
      result.add(
        BookChunk(
          index: idx++,
          type: BookChunkType.text,
          section: pending.section,
          sourceFile: pending.sourceFile,
          text: pending.text,
          links: pending.links,
          isHeading: pending.isHeading,
        ),
      );
    }

    return result;
  }

  // ─── Fallback extraction ─────────────────────────────────────────────

  List<BookChunk> _fallbackExtract(EpubBook book) {
    final html = book.Content?.Html;
    if (html == null || html.isEmpty) {
      return [
        const BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: 'Could not parse this book.',
        ),
      ];
    }

    final buf = StringBuffer();
    for (final entry in html.values) {
      final content = entry.Content;
      if (content == null) continue;
      final stripped = content.replaceAll(RegExp(r'<[^>]*>'), ' ');
      buf.write(stripped);
      buf.write('\n\n');
    }

    final fullText = buf.toString().trim();
    if (fullText.isEmpty) {
      return [
        const BookChunk(
          index: 0,
          type: BookChunkType.text,
          text: 'Could not parse this book.',
        ),
      ];
    }

    final subTexts = _splitBySentence(fullText, _targetWords);
    final chunks = <BookChunk>[];
    for (int i = 0; i < subTexts.length; i++) {
      chunks.add(
        BookChunk(index: i, type: BookChunkType.text, text: subTexts[i]),
      );
    }
    debugPrint('EpubParser: fallback produced ${chunks.length} chunks');
    return chunks;
  }

  // ─── Text splitting utilities ────────────────────────────────────────

  /// Split text into chunks of approximately [targetWords] words each,
  /// breaking at sentence boundaries.
  List<String> _splitBySentence(String text, int targetWords) {
    final sentences = _splitIntoSentences(text);
    final List<String> result = [];
    final buf = StringBuffer();

    for (final s in sentences) {
      final bufWords = _wordCount(buf.toString());
      final sWords = _wordCount(s);
      if (bufWords + sWords > targetWords && buf.isNotEmpty) {
        result.add(buf.toString().trim());
        buf.clear();
      }
      if (buf.isNotEmpty) buf.write(' ');
      buf.write(s);
    }
    if (buf.isNotEmpty && buf.toString().trim().isNotEmpty) {
      result.add(buf.toString().trim());
    }
    return result;
  }

  int _wordCount(String s) {
    final trimmed = s.trim();
    if (trimmed.isEmpty) return 0;
    return trimmed.split(RegExp(r'\s+')).length;
  }

  List<String> _splitIntoSentences(String text) {
    final List<String> sentences = [];
    final buffer = StringBuffer();
    bool insideQuote = false;

    for (int i = 0; i < text.length; i++) {
      final char = text[i];
      if (char == '\u201C' || char == '\u201D') {
        insideQuote = char == '\u201C';
        buffer.write(char);
        continue;
      }
      if (char == '"') {
        insideQuote = !insideQuote;
        buffer.write(char);
        continue;
      }
      buffer.write(char);
      if (!insideQuote &&
          (char == '.' || char == '!' || char == '?') &&
          _isEndOfSentence(text, i)) {
        sentences.add(buffer.toString().trim());
        buffer.clear();
      }
    }
    if (buffer.isNotEmpty && buffer.toString().trim().isNotEmpty) {
      sentences.add(buffer.toString().trim());
    }
    return sentences;
  }

  bool _isEndOfSentence(String text, int i) {
    int j = i + 1;
    while (j < text.length && text[j] == ' ') {
      j++;
    }
    if (j >= text.length) return true;
    final next = text[j];
    return next == next.toUpperCase() && next != next.toLowerCase();
  }

  // ─── Image resolution ────────────────────────────────────────────────

  Uint8List? _resolveImage(EpubBook book, String src) {
    try {
      final images = book.Content?.Images;
      if (images == null) return null;

      final filename = p.basename(src);
      for (final key in images.keys) {
        if (key.endsWith(filename)) {
          final content = images[key];
          if (content?.Content == null) continue;
          return Uint8List.fromList(content!.Content!);
        }
      }
    } catch (e) {
      debugPrint('EpubParser: failed to resolve image "$src": $e');
    }
    return null;
  }

  // ─── Constants ───────────────────────────────────────────────────────

  static const Set<String> _blockTags = {
    'p',
    'div',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'li',
    'blockquote',
    'section',
    'article',
    'header',
    'footer',
    'main',
    'figure',
    'figcaption',
    'pre',
    'hr',
    'br',
  };

  // ─── EPUB Table of Contents extraction ─────────────────────────────

  /// Builds a hierarchical chapter list from the EPUB's built-in TOC
  /// (`EpubBook.Chapters`). Each `EpubChapter` has a `Title`,
  /// `ContentFileName`, and recursive `SubChapters`.
  ///
  /// We match each chapter's content filename against the HTML content
  /// keys to find which chunk index corresponds to the start of that
  /// chapter file.
  List<ChapterInfo> _extractTocChapters(
    EpubBook book,
    List<BookChunk> chunks,
    Map<String, EpubTextContentFile> contentMap,
  ) {
    final epubChapters = book.Chapters;
    if (epubChapters == null || epubChapters.isEmpty) {
      debugPrint('EpubParser: No TOC chapters found in this EPUB');
      return [];
    }

    // Build a map: content filename → chunk index of the first chunk
    // produced from that file.
    // We track which contentMap key produced chunks by walking the keys
    // in order and counting the chunks each one contributed.
    final Map<String, int> fileToChunkStart = {};
    int runningChunkCount = 0;

    // Approximate: walk contentMap keys in order, parse each file to
    // count how many chunks it produces, and record the starting index.
    // Since we already parsed, we need a simpler approach: match the
    // chapter's content to actual chunk text.
    //
    // Better approach: build a filename → first-chunk-index map by
    // checking which content keys exist and assigning chunk offsets.
    final orderedKeys = contentMap.keys.toList();
    // Track: for each HTML file, what chunk index does it start at?
    // We re-parse each one lightly to count chunks.
    for (final key in orderedKeys) {
      fileToChunkStart[key] = runningChunkCount;
      // Also map by basename for fuzzy matching
      fileToChunkStart[p.basename(key)] = runningChunkCount;

      final htmlContent = contentMap[key];
      if (htmlContent?.Content == null) continue;

      // Count how many chunks this file produced by counting block
      // elements (approximate).
      try {
        final doc = html_parser.parse(htmlContent!.Content!);
        final body = doc.body;
        if (body == null) continue;

        int blockCount = 0;
        void countBlocks(dom.Node node) {
          if (node is dom.Element) {
            if (_blockTags.contains(node.localName)) blockCount++;
            if (node.localName == 'img') blockCount++;
            for (final child in node.nodes) {
              countBlocks(child);
            }
          }
        }

        countBlocks(body);
        // Each file produces at least 1 chunk (from flush at end)
        runningChunkCount += blockCount > 0 ? blockCount : 1;
      } catch (_) {
        runningChunkCount += 1;
      }
    }

    debugPrint('EpubParser: TOC has ${epubChapters.length} top-level chapters');

    // Recursively walk EpubChapters to build ChapterInfo tree.
    List<ChapterInfo> walkChapters(List<EpubChapter> chapters, int depth) {
      final List<ChapterInfo> result = [];
      for (final ch in chapters) {
        final title = ch.Title?.trim() ?? '';
        if (title.isEmpty) continue;

        // Find chunk index for this chapter's content.
        int chunkIdx = 0;
        final contentFile = ch.ContentFileName;
        if (contentFile != null) {
          // Try exact key match first, then basename
          chunkIdx =
              fileToChunkStart[contentFile] ??
              fileToChunkStart[p.basename(contentFile)] ??
              0;
        }
        // Clamp to valid range
        chunkIdx = chunkIdx.clamp(0, chunks.length - 1);

        // Recurse into sub-chapters
        final children = (ch.SubChapters != null && ch.SubChapters!.isNotEmpty)
            ? walkChapters(ch.SubChapters!, depth + 1)
            : <ChapterInfo>[];

        result.add(
          ChapterInfo(
            title: title,
            chunkIndex: chunkIdx,
            depth: depth,
            children: children,
          ),
        );
      }
      return result;
    }

    return walkChapters(epubChapters, 0);
  }
}
