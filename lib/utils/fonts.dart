import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design system font helpers.
///
/// Satoshi is by Indian Type Foundry, available on Google Fonts.
/// We use [GoogleFonts.getFont] which works with any Google Fonts family name
/// and automatically handles download + caching at runtime.
class StockpileFonts {
  StockpileFonts._();

  /// Returns a TextStyle using the Satoshi font family.
  /// Falls back to the system default sans-serif if Satoshi is unavailable.
  static TextStyle satoshi({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? height,
    double? letterSpacing,
    TextDecoration? decoration,
  }) {
    try {
      return GoogleFonts.getFont(
        'Satoshi',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        decoration: decoration,
      );
    } catch (_) {
      return TextStyle(
        fontFamily: 'Satoshi',
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
        height: height,
        letterSpacing: letterSpacing,
        decoration: decoration,
        fontFamilyFallback: const ['sans-serif'],
      );
    }
  }

  /// Returns a [TextTheme] built on Satoshi.
  static TextTheme satoshiTextTheme({Color? defaultColor}) {
    try {
      return GoogleFonts.getTextTheme('Satoshi');
    } catch (_) {
      return ThemeData.fallback().textTheme.apply(
        fontFamily: 'Satoshi',
        fontFamilyFallback: ['sans-serif'],
      );
    }
  }
}
