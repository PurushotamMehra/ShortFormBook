import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A user-created bookmark pointing to a specific card in the book.
@immutable
class Bookmark {
  final int chunkIndex;
  final String name;
  final DateTime createdAt;

  Bookmark({required this.chunkIndex, required this.name, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();

  Bookmark copyWith({int? chunkIndex, String? name, DateTime? createdAt}) {
    return Bookmark(
      chunkIndex: chunkIndex ?? this.chunkIndex,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'chunkIndex': chunkIndex,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    chunkIndex: json['chunkIndex'] as int,
    name: json['name'] as String,
    createdAt: DateTime.parse(json['createdAt'] as String),
  );

  static String encodeList(List<Bookmark> list) =>
      jsonEncode(list.map((b) => b.toJson()).toList());

  static List<Bookmark> decodeList(String json) => (jsonDecode(json) as List)
      .map((e) => Bookmark.fromJson(e as Map<String, dynamic>))
      .toList();
}

/// Chapter/section metadata from the EPUB Table of Contents.
///
/// Supports arbitrary nesting: Part → Chapter → Section → …
@immutable
class ChapterInfo {
  final String title;
  final int chunkIndex;

  /// 0 = top-level (e.g. "Part I"), 1 = chapter, 2 = sub-section, etc.
  final int depth;

  /// Optional children for UI hierarchy rendering.
  final List<ChapterInfo> children;

  const ChapterInfo({
    required this.title,
    required this.chunkIndex,
    this.depth = 0,
    this.children = const [],
  });
}
