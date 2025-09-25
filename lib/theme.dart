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
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
    bodyLarge: TextStyle(color: Color(0xFF495057), fontSize: 16),
    bodyMedium: TextStyle(color: Color(0xFF495057), fontSize: 14),
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
    dataTextStyle: const TextStyle(color: Color(0xFF495057)),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFDEE2E6)),
      borderRadius: BorderRadius.circular(12),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      textStyle: const TextStyle(inherit: false, fontWeight: FontWeight.bold),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDEE2E6)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFFDEE2E6)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: const BorderSide(color: Color(0xFF005f73), width: 2),
    ),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  ),
  dialogTheme: DialogThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  ),
  useMaterial3: true,
);

final appDarkTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF005f73),
    brightness: Brightness.dark,
    primary: const Color(0xFF005f73),
    onPrimary: Colors.white,
    secondary: const Color(0xFF00A896),
    onSecondary: Colors.black,
    // surface should be a bit lighter than scaffold in dark mode so cards remain visible
    surface: const Color(0xFF14181A),
    onSurface: const Color(0xFFE7EEF1),
  ),
  scaffoldBackgroundColor: const Color(0xFF0B0F12),
  cardTheme: CardThemeData(
    elevation: 6,
    // Make card color slightly lighter than scaffold so cards are visible in dark mode
    color: const Color(0xFF111418),
    shadowColor: Colors.black.withAlpha((0.35 * 255).round()),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    margin: const EdgeInsets.all(8),
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      color: Color(0xFFE7EEF1),
      fontSize: 32,
      fontWeight: FontWeight.bold,
    ),
    headlineMedium: TextStyle(
      color: Color(0xFFE7EEF1),
      fontSize: 28,
      fontWeight: FontWeight.bold,
    ),
    headlineSmall: TextStyle(
      color: Color(0xFFE7EEF1),
      fontSize: 24,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(color: Color(0xFFBFC9CB), fontSize: 16),
    bodyMedium: TextStyle(color: Color(0xFFBFC9CB), fontSize: 14),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: const Color(0xFF0F1720),
    elevation: 4.0,
    shadowColor: Colors.black.withAlpha((0.2 * 255).round()),
    foregroundColor: const Color(0xFFE7EEF1),
    titleTextStyle: const TextStyle(
      color: Color(0xFFE7EEF1),
      fontSize: 28,
      fontWeight: FontWeight.w600,
    ),
  ),
  dataTableTheme: DataTableThemeData(
    headingRowColor: WidgetStateProperty.all(const Color(0xFF1F2A31)),
    dataRowColor: WidgetStateProperty.all(const Color(0xFF0D1214)),
    dividerThickness: 1,
    headingTextStyle: const TextStyle(
      fontWeight: FontWeight.w600,
      color: Color(0xFFE7EEF1),
    ),
    dataTextStyle: const TextStyle(color: Color(0xFFCED7D9)),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: const Color(0xFF1F6F61), // slightly brighter primary-ish button color
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      textStyle: const TextStyle(inherit: false, fontWeight: FontWeight.bold),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade800),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: Colors.grey.shade800),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(color: const Color(0xFF66C0AD), width: 2),
    ),
    filled: true,
    fillColor: const Color(0xFF0F1720),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  ),
  useMaterial3: true,
);
