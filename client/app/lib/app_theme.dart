import 'package:flutter/material.dart';
import 'brand.dart';

/// Shared colors and touch targets for both appearance modes.
class AppTheme {
  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: Brand.violet,
      brightness: brightness,
    ).copyWith(
      primary: dark ? const Color(0xFFD5A6FF) : Brand.violet,
      onPrimary: dark ? Brand.indigo : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF483275) : const Color(0xFFF0E1FF),
      onPrimaryContainer: dark ? Brand.cream : Brand.indigo,
      secondary: dark ? Brand.aqua : const Color(0xFF006B7A),
      onSecondary: Brand.indigo,
      secondaryContainer:
          dark ? const Color(0xFF29475A) : const Color(0xFFFFE8C9),
      onSecondaryContainer: dark ? Brand.cream : Brand.indigo,
      error: dark ? Brand.coral : const Color(0xFFB92739),
      surface: dark ? Brand.indigo : Brand.cream,
      onSurface: dark ? Brand.cream : Brand.indigo,
      surfaceContainerLow: dark ? const Color(0xFF27294F) : Colors.white,
      surfaceContainerHighest:
          dark ? const Color(0xFF343660) : const Color(0xFFF4ECF5),
      outlineVariant: dark ? const Color(0xFF646687) : const Color(0xFFDCD3E1),
    );

    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: 72,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 21,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: dark ? 0 : 2,
        margin: EdgeInsets.zero,
        shape: rounded.copyWith(
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 60),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: rounded,
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 56),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: rounded,
          side: BorderSide(color: scheme.outlineVariant),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
    );
  }
}
