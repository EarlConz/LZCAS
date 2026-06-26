import 'package:flutter/material.dart';
import 'utils/fonts.dart';

// ─── Stockpile Design System ────────────────────────────────────────────────
// Modern SaaS aesthetic: orange primary, royal-blue secondary, Satoshi font,
// clean cards with subtle shadows, pill-shaped buttons, generous whitespace.

const appRadius = 14.0;
const appSpacing = 24.0;

// ─── Primary (Orange) Swatches ──────────────────────────────────────────────
class StockpileColors {
  StockpileColors._();

  // Primary — Orange/Yellow
  static const primary50 = Color(0xFFFFF7DF);
  static const primary100 = Color(0xFFFFECB3);
  static const primary200 = Color(0xFFFFE082);
  static const primary300 = Color(0xFFFFD54F);
  static const primary400 = Color(0xFFFFCA28);
  static const primary500 = Color(0xFFFDBC00);
  static const primary600 = Color(0xFFFFB300);
  static const primary700 = Color(0xFFFFA000);
  static const primary800 = Color(0xFFFF8F00);
  static const primary900 = Color(0xFFFF6700);

  // Secondary — Royal Blue / Lavender
  static const secondary50 = Color(0xFFE9EBFF);
  static const secondary100 = Color(0xFFD1D5FF);
  static const secondary200 = Color(0xFFA5ABFF);
  static const secondary300 = Color(0xFF7981FF);
  static const secondary400 = Color(0xFF4D57FF);
  static const secondary500 = Color(0xFF0037FD);
  static const secondary600 = Color(0xFF0029CC);
  static const secondary700 = Color(0xFF001B99);
  static const secondary800 = Color(0xFF000D66);
  static const secondary900 = Color(0xFF000DCD);

  // Error — Pink/Red
  static const error50 = Color(0xFFFDE8E6);
  static const error100 = Color(0xFFFACCC7);
  static const error200 = Color(0xFFF5998E);
  static const error300 = Color(0xFFF06655);
  static const error400 = Color(0xFFEB331C);
  static const error500 = Color(0xFFFF4E05);
  static const error600 = Color(0xFFE04400);
  static const error700 = Color(0xFFB83700);
  static const error800 = Color(0xFF8F2A00);
  static const error900 = Color(0xFFCA2700);

  // Success — Green
  static const success = Color(0xFF22C55E);
  static const successBg = Color(0xFFDCFCE7);

  // Danger — Red (for badges)
  static const danger = Color(0xFFEF4444);
  static const dangerBg = Color(0xFFFEE2E2);

  // Neutrals — Light
  static const scaffoldBg = Color(0xFFFAFAFA);
  static const surface = Color(0xFFFFFFFF);
  static const darkText = Color(0xFF1A1A2E);
  static const bodyText = Color(0xFF4A4A5A);
  static const mutedText = Color(0xFF8E8E9A);
  static const divider = Color(0xFFE8E8EC);
  static const inputBg = Color(0xFFF5F5F8);
  static const tableHead = Color(0xFFF8F8FC);
  static const sidebarActive = Color(0xFFF5F5F8);
  static const charcoal = Color(0xFF2D2D3F);

  // Dark
  static const darkBg = Color(0xFF0F0F1A);
  static const darkSurface = Color(0xFF1A1A2E);
  static const darkTextPrimary = Color(0xFFEEEEF4);
  static const darkTextBody = Color(0xFFC8C8D4);
  static const darkTextMuted = Color(0xFF8A8A9E);
  static const darkDivider = Color(0xFF2E2E45);
  static const darkInputBg = Color(0xFF262640);
  static const darkSidebarActive = Color(0xFF262640);
}

// ─── Shared Shapes ──────────────────────────────────────────────────────────

final _cardShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(16),
);
final _pillShape = RoundedRectangleBorder(
  borderRadius: BorderRadius.circular(100),
);
final _inputShape = OutlineInputBorder(borderRadius: BorderRadius.circular(12));

// ─── Typography via Satoshi ─────────────────────────────────────────────────

TextTheme _buildTextTheme({
  required Color titleColor,
  required Color bodyColor,
  required Color mutedColor,
}) {
  final base = StockpileFonts.satoshiTextTheme();
  return base.copyWith(
    // H3: Bold 32px, height 1.2
    headlineSmall: base.headlineSmall?.copyWith(
      color: titleColor,
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    // H4: Bold 24px, height 1.2  → mapped to titleLarge
    titleLarge: base.titleLarge?.copyWith(
      color: titleColor,
      fontSize: 24,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    // H5: Bold 20px, height 1.2  → mapped to titleMedium
    titleMedium: base.titleMedium?.copyWith(
      color: titleColor,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    // H6: Bold 16px, height 1.2  → mapped to titleSmall
    titleSmall: base.titleSmall?.copyWith(
      color: titleColor,
      fontSize: 16,
      fontWeight: FontWeight.w700,
      height: 1.2,
    ),
    // Title L: Regular 28px, height 1.3  → mapped to headlineMedium
    headlineMedium: base.headlineMedium?.copyWith(
      color: titleColor,
      fontSize: 28,
      fontWeight: FontWeight.w400,
      height: 1.3,
    ),
    // Body L: Regular 18px, height 1.5
    bodyLarge: base.bodyLarge?.copyWith(
      color: bodyColor,
      fontSize: 18,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    // Body M: Regular 16px, height 1.5
    bodyMedium: base.bodyMedium?.copyWith(
      color: bodyColor,
      fontSize: 16,
      fontWeight: FontWeight.w400,
      height: 1.5,
    ),
    // Body S
    bodySmall: base.bodySmall?.copyWith(
      color: mutedColor,
      fontSize: 14,
      fontWeight: FontWeight.w400,
      height: 1.4,
    ),
    // Labels
    labelLarge: base.labelLarge?.copyWith(
      color: titleColor,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      height: 1.3,
    ),
    labelMedium: base.labelMedium?.copyWith(
      color: mutedColor,
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.3,
    ),
    labelSmall: base.labelSmall?.copyWith(
      color: mutedColor,
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.3,
    ),
  );
}

// ─── Light Theme ────────────────────────────────────────────────────────────

final stockpileTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: StockpileColors.primary500,
    brightness: Brightness.light,
    primary: StockpileColors.primary900,
    onPrimary: Colors.white,
    secondary: StockpileColors.secondary500,
    onSecondary: Colors.white,
    surface: StockpileColors.surface,
    onSurface: StockpileColors.darkText,
    error: StockpileColors.error500,
    onError: Colors.white,
  ),
  scaffoldBackgroundColor: StockpileColors.scaffoldBg,
  dividerColor: StockpileColors.divider,
  cardTheme: CardThemeData(
    elevation: 1,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.black.withAlpha((0.05 * 255).round()),
    shape: _cardShape,
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
  ),
  textTheme: _buildTextTheme(
    titleColor: StockpileColors.darkText,
    bodyColor: StockpileColors.bodyText,
    mutedColor: StockpileColors.mutedText,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: StockpileColors.surface,
    elevation: 0,
    scrolledUnderElevation: 1,
    shadowColor: Color(0x0A000000),
    foregroundColor: StockpileColors.darkText,
  ),
  dataTableTheme: DataTableThemeData(
    headingRowColor: WidgetStateProperty.all(StockpileColors.tableHead),
    dataRowColor: WidgetStateProperty.all(StockpileColors.surface),
    dividerThickness: 1,
    headingTextStyle: StockpileFonts.satoshi(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: StockpileColors.mutedText,
    ),
    dataTextStyle: StockpileFonts.satoshi(
      color: StockpileColors.bodyText,
      fontSize: 15,
    ),
    decoration: BoxDecoration(
      color: StockpileColors.surface,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withAlpha((0.04 * 255).round()),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ],
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: StockpileColors.primary900,
      foregroundColor: Colors.white,
      minimumSize: const Size(0, 48),
      shape: _pillShape,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      textStyle: StockpileFonts.satoshi(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      shape: _pillShape,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      textStyle: StockpileFonts.satoshi(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      shape: _pillShape,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      textStyle: StockpileFonts.satoshi(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: _inputShape.copyWith(
      borderSide: BorderSide(color: StockpileColors.divider),
    ),
    enabledBorder: _inputShape.copyWith(
      borderSide: BorderSide(color: StockpileColors.divider),
    ),
    focusedBorder: _inputShape.copyWith(
      borderSide: BorderSide(color: StockpileColors.primary900, width: 2),
    ),
    errorBorder: _inputShape.copyWith(
      borderSide: BorderSide(color: StockpileColors.error500, width: 1.5),
    ),
    filled: true,
    fillColor: StockpileColors.inputBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  ),
  dialogTheme: DialogThemeData(
    shape: _cardShape,
    elevation: 4,
    shadowColor: Colors.black.withAlpha((0.12 * 255).round()),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: _pillShape,
    contentTextStyle: StockpileFonts.satoshi(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: Colors.white,
    ),
  ),
  chipTheme: ChipThemeData(
    shape: _pillShape,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  ),
  navigationRailTheme: NavigationRailThemeData(
    minWidth: 100,
    labelType: NavigationRailLabelType.all,
    groupAlignment: -0.8,
    indicatorShape: const StadiumBorder(),
  ),
  drawerTheme: const DrawerThemeData(
    shape: RoundedRectangleBorder(),
    backgroundColor: StockpileColors.surface,
  ),
  popupMenuTheme: PopupMenuThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: StockpileFonts.satoshi(fontSize: 15),
    elevation: 4,
  ),
  dividerTheme: const DividerThemeData(
    color: StockpileColors.divider,
    thickness: 1,
    space: 1,
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: StockpileColors.primary900,
    foregroundColor: Colors.white,
    shape: CircleBorder(),
    elevation: 4,
  ),
);

// ─── Dark Theme ─────────────────────────────────────────────────────────────

final stockpileDarkTheme = ThemeData(
  useMaterial3: true,
  colorScheme: ColorScheme.fromSeed(
    seedColor: StockpileColors.primary500,
    brightness: Brightness.dark,
    primary: StockpileColors.primary500,
    onPrimary: StockpileColors.darkBg,
    secondary: StockpileColors.secondary400,
    onSecondary: StockpileColors.darkBg,
    surface: StockpileColors.darkSurface,
    onSurface: StockpileColors.darkTextPrimary,
    error: const Color(0xFFFF6B7A),
    onError: StockpileColors.darkBg,
  ),
  scaffoldBackgroundColor: StockpileColors.darkBg,
  dividerColor: StockpileColors.darkDivider,
  cardTheme: CardThemeData(
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    color: StockpileColors.darkSurface,
    shadowColor: Colors.transparent,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: StockpileColors.darkDivider, width: 1),
    ),
    margin: EdgeInsets.zero,
  ),
  textTheme: _buildTextTheme(
    titleColor: StockpileColors.darkTextPrimary,
    bodyColor: StockpileColors.darkTextBody,
    mutedColor: StockpileColors.darkTextMuted,
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: StockpileColors.darkSurface,
    elevation: 0,
    scrolledUnderElevation: 1,
    foregroundColor: StockpileColors.darkTextPrimary,
  ),
  dataTableTheme: DataTableThemeData(
    headingRowColor: WidgetStateProperty.all(StockpileColors.darkInputBg),
    dataRowColor: WidgetStateProperty.all(StockpileColors.darkSurface),
    dividerThickness: 1,
    headingTextStyle: StockpileFonts.satoshi(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      color: StockpileColors.darkTextMuted,
    ),
    dataTextStyle: StockpileFonts.satoshi(
      color: StockpileColors.darkTextBody,
      fontSize: 15,
    ),
    decoration: BoxDecoration(
      color: StockpileColors.darkSurface,
      borderRadius: BorderRadius.circular(16),
    ),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      elevation: 0,
      backgroundColor: StockpileColors.primary500,
      foregroundColor: StockpileColors.darkBg,
      minimumSize: const Size(0, 48),
      shape: _pillShape,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      textStyle: StockpileFonts.satoshi(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      minimumSize: const Size(0, 48),
      shape: _pillShape,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      textStyle: StockpileFonts.satoshi(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(0, 48),
      shape: _pillShape,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      textStyle: StockpileFonts.satoshi(
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    border: _inputShape.copyWith(
      borderSide: BorderSide(color: StockpileColors.darkDivider),
    ),
    enabledBorder: _inputShape.copyWith(
      borderSide: BorderSide(color: StockpileColors.darkDivider),
    ),
    focusedBorder: _inputShape.copyWith(
      borderSide: BorderSide(color: StockpileColors.primary500, width: 2),
    ),
    errorBorder: _inputShape.copyWith(
      borderSide: const BorderSide(color: Color(0xFFFF6B7A), width: 1.5),
    ),
    filled: true,
    fillColor: StockpileColors.darkInputBg,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
  ),
  dialogTheme: DialogThemeData(
    shape: _cardShape,
    elevation: 4,
    backgroundColor: StockpileColors.darkSurface,
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: _pillShape,
    contentTextStyle: StockpileFonts.satoshi(
      fontSize: 15,
      fontWeight: FontWeight.w500,
      color: StockpileColors.darkBg,
    ),
  ),
  chipTheme: ChipThemeData(
    shape: _pillShape,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
  ),
  navigationRailTheme: NavigationRailThemeData(
    minWidth: 100,
    labelType: NavigationRailLabelType.all,
    groupAlignment: -0.8,
    indicatorShape: const StadiumBorder(),
  ),
  drawerTheme: const DrawerThemeData(
    shape: RoundedRectangleBorder(),
    backgroundColor: StockpileColors.darkSurface,
  ),
  popupMenuTheme: PopupMenuThemeData(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    textStyle: StockpileFonts.satoshi(fontSize: 15),
    elevation: 4,
  ),
  dividerTheme: const DividerThemeData(
    color: StockpileColors.darkDivider,
    thickness: 1,
    space: 1,
  ),
  floatingActionButtonTheme: const FloatingActionButtonThemeData(
    backgroundColor: StockpileColors.primary500,
    foregroundColor: StockpileColors.darkBg,
    shape: CircleBorder(),
    elevation: 4,
  ),
);
