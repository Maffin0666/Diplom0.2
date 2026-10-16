import 'package:flutter/material.dart';
import 'brand.dart';

/// Calm reading surfaces, strong contrast and generous touch targets.
class AppTheme {
  static ThemeData light(
          {bool highContrast = false,
          bool reduceMotion = false,
          bool boldText = false,
          String palette = 'standard',
          String fontMode = 'system',
          double letterSpacing = 0,
          double lineHeight = 1.4}) =>
      _build(Brightness.light, highContrast, reduceMotion, boldText, palette,
          fontMode, letterSpacing, lineHeight);

  static ThemeData dark(
          {bool highContrast = false,
          bool reduceMotion = false,
          bool boldText = false,
          String palette = 'standard',
          String fontMode = 'system',
          double letterSpacing = 0,
          double lineHeight = 1.4}) =>
      _build(Brightness.dark, highContrast, reduceMotion, boldText, palette,
          fontMode, letterSpacing, lineHeight);

  static ThemeData _build(
      Brightness brightness,
      bool highContrast,
      bool reduceMotion,
      bool boldText,
      String palette,
      String fontMode,
      double letterSpacing,
      double lineHeight) {
    final effectiveBrightness = palette == 'inverse'
        ? (brightness == Brightness.dark ? Brightness.light : Brightness.dark)
        : palette == 'black_yellow'
            ? Brightness.dark
            : brightness;
    final dark = effectiveBrightness == Brightness.dark;
    var scheme = ColorScheme.fromSeed(
      seedColor: Brand.indigo,
      brightness: effectiveBrightness,
    ).copyWith(
      primary: dark ? const Color(0xFFBEC6FF) : const Color(0xFF383C87),
      onPrimary: dark ? const Color(0xFF111735) : Colors.white,
      primaryContainer:
          dark ? const Color(0xFF292F59) : const Color(0xFFE4E8FF),
      onPrimaryContainer:
          dark ? const Color(0xFFE9ECFF) : const Color(0xFF242B66),
      secondary: dark ? const Color(0xFF7CE1D8) : const Color(0xFF006D69),
      onSecondary: dark ? const Color(0xFF073D3A) : Colors.white,
      secondaryContainer:
          dark ? const Color(0xFF1C464B) : const Color(0xFFD6F4EF),
      onSecondaryContainer:
          dark ? const Color(0xFFCCF6EF) : const Color(0xFF064C48),
      error: dark ? const Color(0xFFFFB4AA) : const Color(0xFFB3261E),
      surface: dark ? const Color(0xFF0E1426) : const Color(0xFFF8F5EF),
      onSurface: dark ? const Color(0xFFF2F3FA) : const Color(0xFF182139),
      surfaceContainerLow: dark ? const Color(0xFF1B2339) : Colors.white,
      surfaceContainerHighest:
          dark ? const Color(0xFF29314A) : const Color(0xFFE9EDF5),
      outlineVariant: dark ? const Color(0xFF46516D) : const Color(0xFFDCE2EE),
    );

    if (highContrast) {
      final bg = dark ? Colors.black : Colors.white;
      final ink = dark ? Colors.white : Colors.black;
      scheme = scheme.copyWith(
        surface: bg,
        onSurface: ink,
        onSurfaceVariant: ink,
        surfaceContainerLow: bg,
        surfaceContainerHighest: bg,
        primary: dark ? const Color(0xFFFFE66D) : const Color(0xFF172D82),
        onPrimary: dark ? Colors.black : Colors.white,
        primaryContainer: bg,
        onPrimaryContainer: ink,
        secondary: dark ? const Color(0xFF8FFFF2) : const Color(0xFF004C45),
        secondaryContainer: bg,
        onSecondaryContainer: ink,
        outline: ink,
        outlineVariant: ink,
      );
    }

    if (palette == 'black_yellow') {
      scheme = scheme.copyWith(
        surface: Colors.black,
        onSurface: Colors.white,
        onSurfaceVariant: Colors.white,
        surfaceContainerLow: Colors.black,
        surfaceContainerHighest: const Color(0xFF151515),
        primary: const Color(0xFFFFE45C),
        onPrimary: Colors.black,
        primaryContainer: const Color(0xFF292400),
        onPrimaryContainer: const Color(0xFFFFFFB3),
        secondary: Colors.white,
        tertiary: const Color(0xFFFFE45C),
        outline: Colors.white,
        outlineVariant: const Color(0xFFFFE45C),
      );
    } else if (palette == 'monochrome') {
      final ink = dark ? Colors.white : Colors.black;
      final bg = dark ? Colors.black : Colors.white;
      scheme = scheme.copyWith(
        surface: bg,
        onSurface: ink,
        onSurfaceVariant: ink,
        surfaceContainerLow: bg,
        surfaceContainerHighest:
            dark ? const Color(0xFF292929) : const Color(0xFFE6E6E6),
        primary: ink,
        onPrimary: bg,
        primaryContainer:
            dark ? const Color(0xFF333333) : const Color(0xFFDDDDDD),
        onPrimaryContainer: ink,
        secondary: ink,
        tertiary: ink,
        outline: ink,
        outlineVariant: ink,
      );
    } else if (palette == 'protanopia' ||
        palette == 'deuteranopia' ||
        palette == 'tritanopia') {
      final primary = switch (palette) {
        'tritanopia' =>
          dark ? const Color(0xFFFFB8D5) : const Color(0xFF8D1950),
        'deuteranopia' =>
          dark ? const Color(0xFFE4C6FF) : const Color(0xFF5E3E8C),
        _ => dark ? const Color(0xFFBDD1FF) : const Color(0xFF173D88),
      };
      final secondary = switch (palette) {
        'tritanopia' =>
          dark ? const Color(0xFFB9FFFB) : const Color(0xFF005C60),
        'deuteranopia' =>
          dark ? const Color(0xFFFFD68B) : const Color(0xFF684F00),
        _ => dark ? const Color(0xFFFFE28A) : const Color(0xFF735100),
      };
      scheme = scheme.copyWith(
        primary: primary,
        onPrimary: dark ? Colors.black : Colors.white,
        secondary: secondary,
        tertiary: secondary,
        outline: dark ? Colors.white : Colors.black,
      );
    }

    final rounded = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
    );
    const baseText = TextTheme(
      headlineLarge:
          TextStyle(fontSize: 34, fontWeight: FontWeight.w800, height: 1.12),
      headlineMedium:
          TextStyle(fontSize: 28, fontWeight: FontWeight.w800, height: 1.18),
      headlineSmall:
          TextStyle(fontSize: 24, fontWeight: FontWeight.w700, height: 1.2),
      titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      titleMedium: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 16, height: 1.4),
      bodyMedium: TextStyle(fontSize: 14, height: 1.4),
    );
    var textTheme = boldText || highContrast
        ? baseText.copyWith(
            headlineLarge:
                baseText.headlineLarge?.copyWith(fontWeight: FontWeight.w900),
            headlineMedium:
                baseText.headlineMedium?.copyWith(fontWeight: FontWeight.w900),
            headlineSmall:
                baseText.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
            titleLarge:
                baseText.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            titleMedium:
                baseText.titleMedium?.copyWith(fontWeight: FontWeight.w800),
            bodyLarge:
                baseText.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            bodyMedium:
                baseText.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
          )
        : baseText;
    final family = switch (fontMode) {
      'open_dyslexic' => 'OpenDyslexic',
      'atkinson' => 'AtkinsonHyperlegibleNext',
      _ => null,
    };
    if (family != null) textTheme = textTheme.apply(fontFamily: family);
    TextStyle? spaced(TextStyle? value) => value?.copyWith(
          letterSpacing: letterSpacing,
          height: lineHeight,
        );
    textTheme = textTheme.copyWith(
      bodyLarge: spaced(textTheme.bodyLarge),
      bodyMedium: spaced(textTheme.bodyMedium),
      titleLarge: spaced(textTheme.titleLarge),
      titleMedium: spaced(textTheme.titleMedium),
    );
    return ThemeData(
      fontFamily: family,
      useMaterial3: true,
      pageTransitionsTheme: reduceMotion
          ? PageTransitionsTheme(builders: {
              for (final platform in TargetPlatform.values)
                platform: const _StillPageTransition(),
            })
          : const PageTransitionsTheme(),
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: 64,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 20,
          fontWeight:
              boldText || highContrast ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: rounded.copyWith(
          side: BorderSide(
              color: scheme.outlineVariant, width: highContrast ? 2 : 1),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 64),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 64),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          side: BorderSide(
              color: scheme.outlineVariant, width: highContrast ? 2 : 1),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLow,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
        enabledBorder: OutlineInputBorder(
          borderSide: BorderSide(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(16),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),
      textTheme: textTheme,
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant),
      focusColor: scheme.primary.withValues(alpha: .25),
      visualDensity: VisualDensity.standard,
    );
  }
}

class _StillPageTransition extends PageTransitionsBuilder {
  const _StillPageTransition();
  @override
  Widget buildTransitions<T>(
          PageRoute<T> route,
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child) =>
      child;
}
