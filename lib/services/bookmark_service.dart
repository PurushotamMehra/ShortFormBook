import 'package:shared_preferences/shared_preferences.dart';

import '../models/bookmark.dart';

/// Persistent storage for user-created bookmarks.
///
/// Each book has its own list keyed by `bookmarks_<bookId>`.
/// Bookmarks are auto-named sequentially ("Bookmark 1", "Bookmark 2", …).
class BookmarkService {
  final String bookId;
  SharedPreferences? _prefs;

  BookmarkService({required this.bookId});

  String get _key => 'bookmarks_$bookId';

  Future<SharedPreferences> get _cachedPrefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  // ── Read ──────────────────────────────────────────────────────────────

  Future<List<Bookmark>> load() async {
    final prefs = await _cachedPrefs;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    return Bookmark.decodeList(raw);
  }

  // ── Write ─────────────────────────────────────────────────────────────

  Future<List<Bookmark>> add(int chunkIndex) async {
    final list = await load();

    // Don't double-bookmark the same card.
    if (list.any((b) => b.chunkIndex == chunkIndex)) return list;

    // Sequential name: highest existing number + 1
    int maxNum = 0;
    final pattern = RegExp(r'^Bookmark (\d+)$');
    for (final b in list) {
      final match = pattern.firstMatch(b.name);
      if (match != null) {
        final n = int.parse(match.group(1)!);
        if (n > maxNum) maxNum = n;
      }
    }

    list.add(Bookmark(chunkIndex: chunkIndex, name: 'Bookmark ${maxNum + 1}'));

    await _save(list);
    return list;
  }

  Future<List<Bookmark>> remove(int chunkIndex) async {
    final list = await load();
    list.removeWhere((b) => b.chunkIndex == chunkIndex);
    await _save(list);
    return list;
  }

  Future<List<Bookmark>> rename(int chunkIndex, String newName) async {
    final list = await load();
    final updated = <Bookmark>[];
    for (final b in list) {
      if (b.chunkIndex == chunkIndex) {
        updated.add(b.copyWith(name: newName));
      } else {
        updated.add(b);
      }
    }
    await _save(updated);
    return updated;
  }

  /// Check if a specific chunk is bookmarked.
  bool isBookmarked(List<Bookmark> bookmarks, int chunkIndex) =>
      bookmarks.any((b) => b.chunkIndex == chunkIndex);

  // ── Internal ──────────────────────────────────────────────────────────

  Future<void> _save(List<Bookmark> list) async {
    final prefs = await _cachedPrefs;
    await prefs.setString(_key, Bookmark.encodeList(list));
  }
}
