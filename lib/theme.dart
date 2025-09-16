import 'package:flutter/material.dart';

final appTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF005f73),
    brightness: Brightness.light,
    primary: const Color(0xFF005f73),
    onPrimary: Colors.white,
    secondary: const Color(0xFF00A896),
    onSecondary: Colors.white,
  surface: Colors.white,
  // 'background' and 'onBackground' were deprecated; prefer surface/onSurface
  onSurface: const Color(0xFF212529),
  ),
  scaffoldBackgroundColor: const Color(0xFFF8F9FA),
  cardTheme: CardThemeData(
    elevation: 4,
  shadowColor: Colors.black.withAlpha((0.1 * 255).round()),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
    ),
    margin: const EdgeInsets.all(8),
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      color: Color(0xFF212529),
      fontSize: 32,
      fontWeight: FontWeight.bold,
    ),
    headlineMedium: TextStyle(
      color: Color(0xFF212529),
      fontSize: 28,
      fontWeight: FontWeight.bold,
    ),
    headlineSmall: TextStyle(
      color: Color(0xFF212529),
      fontSize: 24,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(
      color: Color(0xFF495057),
      fontSize: 16,
    ),
    bodyMedium: TextStyle(
      color: Color(0xFF495057),
      fontSize: 14,
    ),
  ),
    appBarTheme: AppBarTheme(
    backgroundColor: const Color(0xFFFFFFFF),
    elevation: 4.0,
  shadowColor: Colors.black.withAlpha((0.1 * 255).round()),
    foregroundColor: const Color(0xFF212529),
    titleTextStyle: const TextStyle(
      color: Color(0xFF212529),
      fontSize: 28,
      fontWeight: FontWeight.w600,
    ),
  ),
  dataTableTheme: DataTableThemeData(
    headingRowColor: WidgetStateProperty.all(const Color(0xFFE9ECEF)),
    dataRowColor: WidgetStateProperty.all(Colors.white),
    dividerThickness: 1,
    headingTextStyle: const TextStyle(
      fontWeight: FontWeight.w600,
      color: Color(0xFF212529),
    ),
    dataTextStyle: const TextStyle(
      color: Color(0xFF495057),
    ),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFDEE2E6)),
      borderRadius: BorderRadius.circular(12),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      textStyle: const TextStyle(
        fontWeight: FontWeight.bold,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide.none,
    ),
    filled: true,
    fillColor: const Color(0xFFE9ECEF),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  ),
  useMaterial3: true,
);