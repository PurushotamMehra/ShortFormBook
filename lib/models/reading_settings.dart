import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ReaderFontFamily { literata, inter, robotoMono, comicNeue }
enum ReaderFontWeight { light, regular, medium, semiBold, bold }
enum ReaderFontSize { xs, s, m, l, xl }
enum ReaderTextAlign { left, center, right, justify }
enum ContentDensity { low, medium, high, fullPage }

class ReadingSettings {
  final ThemeMode themeMode;
  final ReaderFontFamily fontFamily;
  final ReaderFontWeight fontWeight;
  final ReaderFontSize fontSize;
  final ReaderTextAlign textAlign;
  final ContentDensity contentDensity;

  const ReadingSettings({
    this.themeMode = ThemeMode.system,
    this.fontFamily = ReaderFontFamily.literata,
    this.fontWeight = ReaderFontWeight.regular,
    this.fontSize = ReaderFontSize.m,
    this.textAlign = ReaderTextAlign.left,
    this.contentDensity = ContentDensity.medium,
  });

  bool isDark(BuildContext context) {
    if (themeMode == ThemeMode.system) {
      return MediaQuery.of(context).platformBrightness == Brightness.dark;
    }
    return themeMode == ThemeMode.dark;
  }

  Color backgroundColor(BuildContext context) {
    return isDark(context) ? const Color(0xFF1E1E1E) : const Color(0xFFFAF8F5);
  }

  Color textColor(BuildContext context) {
    return isDark(context) ? const Color(0xFFE0E0E0) : const Color(0xFF2C2C2C);
  }

  Color mutedColor(BuildContext context) {
    return isDark(context) ? const Color(0xFFA0A0A0) : const Color(0xFF757575);
  }

  ReadingSettings copyWith({
    ThemeMode? themeMode,
    ReaderFontFamily? fontFamily,
    ReaderFontWeight? fontWeight,
    ReaderFontSize? fontSize,
    ReaderTextAlign? textAlign,
    ContentDensity? contentDensity,
  }) {
    return ReadingSettings(
      themeMode: themeMode ?? this.themeMode,
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      fontSize: fontSize ?? this.fontSize,
      textAlign: textAlign ?? this.textAlign,
      contentDensity: contentDensity ?? this.contentDensity,
    );
  }

  TextStyle getTextStyle(BuildContext context, {bool isHeading = false}) {
    final fontSizeValue = this.fontSizeValue;
    final fontWeightValue = this.fontWeightValue;
    final txtColor = textColor(context);

    final baseStyle = TextStyle(
      fontSize: isHeading ? fontSizeValue + 6 : fontSizeValue,
      fontWeight: isHeading ? FontWeight.w700 : fontWeightValue,
      height: isHeading ? 1.4 : 1.6,
      color: txtColor,
      letterSpacing: isHeading ? 0.3 : 0,
    );

    switch (fontFamily) {
      case ReaderFontFamily.inter:
        return GoogleFonts.inter(textStyle: baseStyle);
      case ReaderFontFamily.robotoMono:
        return GoogleFonts.robotoMono(textStyle: baseStyle);
      case ReaderFontFamily.comicNeue:
        return GoogleFonts.comicNeue(textStyle: baseStyle);
      case ReaderFontFamily.literata:
        return GoogleFonts.literata(textStyle: baseStyle);
    }
  }

  double get fontSizeValue {
    switch (fontSize) {
      case ReaderFontSize.xs:
        return 14.0;
      case ReaderFontSize.s:
        return 16.0;
      case ReaderFontSize.m:
        return 18.0;
      case ReaderFontSize.l:
        return 22.0;
      case ReaderFontSize.xl:
        return 26.0;
    }
  }

  FontWeight get fontWeightValue {
    switch (fontWeight) {
      case ReaderFontWeight.light:
        return FontWeight.w300;
      case ReaderFontWeight.regular:
        return FontWeight.w400;
      case ReaderFontWeight.medium:
        return FontWeight.w500;
      case ReaderFontWeight.semiBold:
        return FontWeight.w600;
      case ReaderFontWeight.bold:
        return FontWeight.w700;
    }
  }
}
