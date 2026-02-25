import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ReaderFontFamily { literata, inter, robotoMono, comicNeue }

enum ReaderFontWeight { light, regular, medium, semiBold, bold }

enum ReaderFontSize { xs, s, m, l, xl }

enum ReaderTextAlign { left, center, right, justify }

enum ContentDensity { low, medium, high, fullPage }

enum AppTheme { softLight, sepia, newspaper, dark, amoled }

@immutable
class ReadingSettings {
  final AppTheme appTheme;
  final AppTheme? readerTheme;
  final ReaderFontFamily fontFamily;
  final ReaderFontWeight fontWeight;
  final ReaderFontSize fontSize;
  final ReaderTextAlign textAlign;
  final ContentDensity contentDensity;

  const ReadingSettings({
    this.appTheme = AppTheme.amoled,
    this.readerTheme,
    this.fontFamily = ReaderFontFamily.literata,
    this.fontWeight = ReaderFontWeight.regular,
    this.fontSize = ReaderFontSize.m,
    this.textAlign = ReaderTextAlign.left,
    this.contentDensity = ContentDensity.medium,
  });

  AppTheme get effectiveTheme => readerTheme ?? appTheme;

  bool get isDark =>
      effectiveTheme == AppTheme.dark || effectiveTheme == AppTheme.amoled;

  // ─── Static color lookup tables (no allocations per call) ───────────
  static const _bgColors = <AppTheme, Color>{
    AppTheme.softLight: Color(0xFFFAF8F5),
    AppTheme.sepia: Color(0xFFF4ECD8),
    AppTheme.newspaper: Color(0xFFEAE8E3),
    AppTheme.dark: Color(0xFF1E1E1E),
    AppTheme.amoled: Color(0xFF000000),
  };

  static const _menuColors = <AppTheme, Color>{
    AppTheme.softLight: Color(0xFFF0EBE1),
    AppTheme.sepia: Color(0xFFE8DECA),
    AppTheme.newspaper: Color(0xFFDCDAD4),
    AppTheme.dark: Color(0xFF2C2C2C),
    AppTheme.amoled: Color(0xFF121212),
  };

  static const _textColors = <AppTheme, Color>{
    AppTheme.softLight: Color(0xFF2C2C2C),
    AppTheme.sepia: Color(0xFF433422),
    AppTheme.newspaper: Color(0xFF1A1A1A),
    AppTheme.dark: Color(0xFFE0E0E0),
    AppTheme.amoled: Color(0xFFFFFFFF),
  };

  static const _mutedColors = <AppTheme, Color>{
    AppTheme.softLight: Color(0xFF757575),
    AppTheme.sepia: Color(0xFF8A7967),
    AppTheme.newspaper: Color(0xFF5A5A5A),
    AppTheme.dark: Color(0xFFA0A0A0),
    AppTheme.amoled: Color(0xFF888888),
  };

  Color get backgroundColor => _bgColors[effectiveTheme]!;
  Color get menuColor => _menuColors[effectiveTheme]!;
  Color get textColor => _textColors[effectiveTheme]!;
  Color get mutedColor => _mutedColors[effectiveTheme]!;

  /// Density multiplier for layout calculations.
  double get densityMultiplier {
    switch (contentDensity) {
      case ContentDensity.low:
        return 0.35;
      case ContentDensity.medium:
        return 0.55;
      case ContentDensity.high:
        return 0.75;
      case ContentDensity.fullPage:
        return 1.0;
    }
  }

  /// Resolved Flutter TextAlign value.
  TextAlign get resolvedTextAlign {
    switch (textAlign) {
      case ReaderTextAlign.center:
        return TextAlign.center;
      case ReaderTextAlign.right:
        return TextAlign.right;
      case ReaderTextAlign.justify:
        return TextAlign.justify;
      case ReaderTextAlign.left:
        return TextAlign.left;
    }
  }

  ReadingSettings copyWith({
    AppTheme? appTheme,
    AppTheme? readerTheme,
    bool clearReaderTheme = false,
    ReaderFontFamily? fontFamily,
    ReaderFontWeight? fontWeight,
    ReaderFontSize? fontSize,
    ReaderTextAlign? textAlign,
    ContentDensity? contentDensity,
  }) {
    return ReadingSettings(
      appTheme: appTheme ?? this.appTheme,
      readerTheme: clearReaderTheme ? null : (readerTheme ?? this.readerTheme),
      fontFamily: fontFamily ?? this.fontFamily,
      fontWeight: fontWeight ?? this.fontWeight,
      fontSize: fontSize ?? this.fontSize,
      textAlign: textAlign ?? this.textAlign,
      contentDensity: contentDensity ?? this.contentDensity,
    );
  }

  TextStyle getTextStyle({bool isHeading = false}) {
    final fSize = fontSizeValue;
    final fWeight = fontWeightValue;
    final color = textColor;

    final baseStyle = TextStyle(
      fontSize: isHeading ? fSize + 6 : fSize,
      fontWeight: isHeading ? FontWeight.w700 : fWeight,
      height: isHeading ? 1.4 : 1.6,
      color: color,
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
