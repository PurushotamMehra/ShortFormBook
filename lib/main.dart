import 'package:flutter/material.dart';

import 'screens/book_list_screen.dart';

void main() {
  runApp(const ScrollableBookApp());
}

class ScrollableBookApp extends StatelessWidget {
  const ScrollableBookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Scrollable Book',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Roboto',
        scaffoldBackgroundColor: const Color(0xFFFAF8F5),
      ),
      home: const BookListScreen(),
    );
  }
}
