import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'reading_settings.dart';

@immutable
class BookMetadata {
  final String id; // filename, e.g., 'book.epub'
  final String title;
  final String author;
  final String? coverImagePath; // local path to extracted cover
  final int lastReadIndex;
  final int totalChunks;
  final int lastReadTime; // Epoch milliseconds
  final AppTheme? theme; // book-specific theme

  BookMetadata({
    required this.id,
    required this.title,
    required this.author,
    this.coverImagePath,
    this.lastReadIndex = 0,
    this.totalChunks = 0,
    int? lastReadTime,
    this.theme,
  }) : lastReadTime = lastReadTime ?? DateTime.now().millisecondsSinceEpoch;

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'title': title,
      'author': author,
      'coverImagePath': coverImagePath,
      'lastReadIndex': lastReadIndex,
      'totalChunks': totalChunks,
      'lastReadTime': lastReadTime,
      'theme': theme?.name,
    };
  }

  factory BookMetadata.fromMap(Map<String, dynamic> map) {
    return BookMetadata(
      id: map['id'] ?? '',
      title: map['title'] ?? '',
      author: map['author'] ?? '',
      coverImagePath: map['coverImagePath'],
      lastReadIndex: (map['lastReadIndex'] as num?)?.toInt() ?? 0,
      totalChunks: (map['totalChunks'] as num?)?.toInt() ?? 0,
      lastReadTime: (map['lastReadTime'] as num?)?.toInt(),
      theme: map['theme'] != null
          ? AppTheme.values.firstWhere(
              (e) => e.name == map['theme'],
              orElse: () => AppTheme.amoled,
            )
          : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory BookMetadata.fromJson(String source) =>
      BookMetadata.fromMap(json.decode(source));

  BookMetadata copyWith({
    String? id,
    String? title,
    String? author,
    String? coverImagePath,
    int? lastReadIndex,
    int? totalChunks,
    int? lastReadTime,
    AppTheme? theme,
    bool clearTheme = false,
  }) {
    return BookMetadata(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      coverImagePath: coverImagePath ?? this.coverImagePath,
      lastReadIndex: lastReadIndex ?? this.lastReadIndex,
      totalChunks: totalChunks ?? this.totalChunks,
      lastReadTime: lastReadTime ?? this.lastReadTime,
      theme: clearTheme ? null : (theme ?? this.theme),
    );
  }
}
