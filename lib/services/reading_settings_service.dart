import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/reading_settings.dart';

class ReadingSettingsService {
  Future<ReadingSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final themeIndex = prefs.getInt('setting_themeMode');
    final fontIndex = prefs.getInt('setting_fontFamily');
    final weightIndex = prefs.getInt('setting_fontWeight');
    final sizeIndex = prefs.getInt('setting_fontSize');
    final alignIndex = prefs.getInt('setting_textAlign');
    final contentDensityString = prefs.getString('contentDensity');

    return ReadingSettings(
      themeMode: themeIndex != null && themeIndex < ThemeMode.values.length
          ? ThemeMode.values[themeIndex]
          : ThemeMode.system,
      fontFamily:
          fontIndex != null && fontIndex < ReaderFontFamily.values.length
          ? ReaderFontFamily.values[fontIndex]
          : ReaderFontFamily.literata,
      fontWeight:
          weightIndex != null && weightIndex < ReaderFontWeight.values.length
          ? ReaderFontWeight.values[weightIndex]
          : ReaderFontWeight.regular,
      fontSize: sizeIndex != null && sizeIndex < ReaderFontSize.values.length
          ? ReaderFontSize.values[sizeIndex]
          : ReaderFontSize.m,
      textAlign:
          alignIndex != null && alignIndex < ReaderTextAlign.values.length
          ? ReaderTextAlign.values[alignIndex]
          : ReaderTextAlign.left,
      contentDensity: contentDensityString != null
          ? ContentDensity.values
              .firstWhere((e) => e.toString() == contentDensityString,
                  orElse: () => ContentDensity.medium)
          : ContentDensity.medium,
    );
  }

  Future<void> saveSettings(ReadingSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setInt('setting_themeMode', settings.themeMode.index);
    await prefs.setInt('setting_fontFamily', settings.fontFamily.index);
    await prefs.setInt('setting_fontWeight', settings.fontWeight.index);
    await prefs.setInt('setting_fontSize', settings.fontSize.index);
    await prefs.setInt('setting_textAlign', settings.textAlign.index);
    await prefs.setString(
        'contentDensity', settings.contentDensity.toString());
  }
}
