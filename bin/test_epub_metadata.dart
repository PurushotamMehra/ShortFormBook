import 'dart:io';

import 'package:epubx/epubx.dart';

Future<void> main() async {
  final file = File(
    '/home/uttam/Desktop/Antigravity Projects/Scrollable Book/assets/books/old_man_and_the_sea.epub',
  );
  if (!await file.exists()) {
    print('File not found');
    return;
  }

  final bytes = await file.readAsBytes();
  final book = await EpubReader.readBook(bytes);
  print('Title: ${book.Title}');
  print('Author: ${book.Author}');
  print('AuthorList: ${book.AuthorList?.join(", ")}');
  print('CoverImage is null: ${book.CoverImage == null}');
}
