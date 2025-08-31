import 'package:flutter/material.dart';

final appTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: Colors.green,
    background: const Color(0xFFF9FAFB),
  ),
  scaffoldBackgroundColor: const Color(0xFFF9FAFB),
  cardTheme: CardThemeData(
    elevation: 2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
      side: BorderSide(color: Color(0xFF00BFA5), width: 1.5),
    ),
  ),
  textTheme: const TextTheme(
    headlineSmall: TextStyle(
      color: Colors.black,
      fontSize: 24,
      fontWeight: FontWeight.bold,
    ),
  ),
  appBarTheme: AppBarTheme(
    backgroundColor: const Color(0xFFFFEBEE),
    elevation: 0,
    titleTextStyle: const TextStyle(
      color: Colors.black,
      fontSize: 24,
      fontWeight: FontWeight.bold,
    ),
    shape: Border(
      bottom: BorderSide(
        color: Colors.green.shade700,
        width: 1.5,
      ),
    ),
  ),
  dataTableTheme: DataTableThemeData(
    headingRowColor: WidgetStateProperty.all(Colors.blueGrey[50]),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border.all(color: Colors.grey.shade300, width: 1),
      borderRadius: BorderRadius.circular(8),
    ),
  ),
  useMaterial3: true,
);
