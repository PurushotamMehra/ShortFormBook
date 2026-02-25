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
      themeMode: ThemeMode.dark, // Enforce dark by default
      theme: ThemeData.light().copyWith(
        scaffoldBackgroundColor: const Color(0xFFFAF8F5),
      ),
      darkTheme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF000000), // Pure black AMOLED
        colorScheme: const ColorScheme.dark(primary: Color(0xFFE85D04)),
      ),
      home: const BookListScreen(),
    );
  }
}
