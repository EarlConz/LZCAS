import 'package:flutter/material.dart';

const appRadius = 16.0;
const appSpacing = 20.0;

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
  scaffoldBackgroundColor: const Color(0xFFF3F6F7),
  dividerColor: const Color(0xFFD8E0E3),
  cardTheme: CardThemeData(
    elevation: 1,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.black.withAlpha((0.08 * 255).round()),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appRadius)),
    margin: EdgeInsets.zero,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      color: Color(0xFF212529),
      fontSize: 30,
      fontWeight: FontWeight.w800,
    ),
    headlineMedium: TextStyle(
      color: Color(0xFF212529),
      fontSize: 24,
      fontWeight: FontWeight.w700,
    ),
    headlineSmall: TextStyle(
      color: Color(0xFF212529),
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: TextStyle(
      color: Color(0xFF212529),
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: TextStyle(
      color: Color(0xFF212529),
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(color: Color(0xFF495057), fontSize: 16),
    bodyMedium: TextStyle(color: Color(0xFF495057), fontSize: 14),
    labelMedium: TextStyle(
      color: Color(0xFF495057),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: const Color(0xFFFFFFFF),
    elevation: 0.0,
    shadowColor: Colors.black.withAlpha((0.06 * 255).round()),
    foregroundColor: const Color(0xFF212529),
    titleTextStyle: const TextStyle(
      color: Color(0xFF212529),
      fontSize: 22,
      fontWeight: FontWeight.w800,
    ),
  ),
  dataTableTheme: DataTableThemeData(
    headingRowColor: WidgetStateProperty.all(const Color(0xFFEAF0F2)),
    dataRowColor: WidgetStateProperty.all(Colors.white),
    dividerThickness: 1,
    headingTextStyle: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: Color(0xFF212529),
    ),
    dataTextStyle: const TextStyle(color: Color(0xFF495057), fontSize: 13),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFD8E0E3)),
      borderRadius: BorderRadius.circular(appRadius),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appRadius)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(
        inherit: false,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(appRadius),
      borderSide: const BorderSide(color: Color(0xFFDEE2E6)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(appRadius),
      borderSide: const BorderSide(color: Color(0xFFDEE2E6)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(appRadius),
      borderSide: const BorderSide(color: Color(0xFF005f73), width: 2),
    ),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  ),
  dialogTheme: DialogThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appRadius)),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appRadius)),
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
  dividerColor: const Color(0xFF283238),
  cardTheme: CardThemeData(
    elevation: 1,
    surfaceTintColor: Colors.transparent,
    // Make card color slightly lighter than scaffold so cards are visible in dark mode
    color: const Color(0xFF111418),
    shadowColor: Colors.black.withAlpha((0.25 * 255).round()),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appRadius)),
    margin: EdgeInsets.zero,
  ),
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      color: Color(0xFFE7EEF1),
      fontSize: 30,
      fontWeight: FontWeight.w800,
    ),
    headlineMedium: TextStyle(
      color: Color(0xFFE7EEF1),
      fontSize: 24,
      fontWeight: FontWeight.w700,
    ),
    headlineSmall: TextStyle(
      color: Color(0xFFE7EEF1),
      fontSize: 20,
      fontWeight: FontWeight.w600,
    ),
    titleLarge: TextStyle(
      color: Color(0xFFE7EEF1),
      fontSize: 18,
      fontWeight: FontWeight.w700,
    ),
    titleMedium: TextStyle(
      color: Color(0xFFE7EEF1),
      fontSize: 15,
      fontWeight: FontWeight.w600,
    ),
    bodyLarge: TextStyle(color: Color(0xFFBFC9CB), fontSize: 16),
    bodyMedium: TextStyle(color: Color(0xFFBFC9CB), fontSize: 14),
    labelMedium: TextStyle(
      color: Color(0xFFBFC9CB),
      fontSize: 12,
      fontWeight: FontWeight.w600,
    ),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: const Color(0xFF0F1720),
    elevation: 0.0,
    shadowColor: Colors.black.withAlpha((0.2 * 255).round()),
    foregroundColor: const Color(0xFFE7EEF1),
    titleTextStyle: const TextStyle(
      color: Color(0xFFE7EEF1),
      fontSize: 22,
      fontWeight: FontWeight.w800,
    ),
  ),
  dataTableTheme: DataTableThemeData(
    headingRowColor: WidgetStateProperty.all(const Color(0xFF1F2A31)),
    dataRowColor: WidgetStateProperty.all(const Color(0xFF0D1214)),
    dividerThickness: 1,
    headingTextStyle: const TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w800,
      color: Color(0xFFE7EEF1),
    ),
    dataTextStyle: const TextStyle(color: Color(0xFFCED7D9), fontSize: 13),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: const Color(0xFF1F6F61), // slightly brighter primary-ish button color
      foregroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appRadius)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(
        inherit: false,
        fontSize: 13,
        fontWeight: FontWeight.w700,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(appRadius),
      borderSide: BorderSide(color: Colors.grey.shade800),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(appRadius),
      borderSide: BorderSide(color: Colors.grey.shade800),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(appRadius),
      borderSide: BorderSide(color: const Color(0xFF66C0AD), width: 2),
    ),
    filled: true,
    fillColor: const Color(0xFF0F1720),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(appRadius)),
  ),
  useMaterial3: true,
);
