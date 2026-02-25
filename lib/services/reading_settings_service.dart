import 'package:shared_preferences/shared_preferences.dart';

import '../models/reading_settings.dart';

class ReadingSettingsService {
  Future<ReadingSettings> loadSettings() async {
    final prefs = await SharedPreferences.getInstance();

    final appThemeString = prefs.getString('setting_appTheme');
    final fontIndex = prefs.getInt('setting_fontFamily');
    final weightIndex = prefs.getInt('setting_fontWeight');
    final sizeIndex = prefs.getInt('setting_fontSize');
    final alignIndex = prefs.getInt('setting_textAlign');
    final contentDensityString = prefs.getString('contentDensity');

    return ReadingSettings(
      appTheme: appThemeString != null
          ? AppTheme.values.firstWhere(
              (e) => e.name == appThemeString,
              orElse: () => AppTheme.amoled,
            )
          : AppTheme.amoled,
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
          ? ContentDensity.values.firstWhere(
              (e) => e.toString() == contentDensityString,
              orElse: () => ContentDensity.medium,
            )
          : ContentDensity.medium,
    );
  }

  Future<void> saveSettings(ReadingSettings settings) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('setting_appTheme', settings.appTheme.name);
    await prefs.setInt('setting_fontFamily', settings.fontFamily.index);
    await prefs.setInt('setting_fontWeight', settings.fontWeight.index);
    await prefs.setInt('setting_fontSize', settings.fontSize.index);
    await prefs.setInt('setting_textAlign', settings.textAlign.index);
    await prefs.setString('contentDensity', settings.contentDensity.toString());
  }
}
