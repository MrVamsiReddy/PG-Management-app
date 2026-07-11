import 'package:flutter/material.dart';

const ink = Color(0xFF18212B);
const primary = Color(0xFF1A7F72);
const primarySoft = Color(0xFFE0F3EF);
const coral = Color(0xFFF47C5E);
const canvas = Color(0xFFF5F7F6);
const warning = Color(0xFFF4B740);

// ---- Theme tokens ---------------------------------------------------------
// Hardcoded greys can't follow a dark scheme, so the screens use these
// mutable tokens instead; applyThemeTokens rebinds them before each app
// build (see the MaterialApp builders).
Color surfaceCard = Colors.white;
Color heroInk = ink; // dark hero cards (rent card, UPI payee card)
Color softTint = primarySoft; // avatar / icon-chip backgrounds
Color subtle = const Color(0x8A000000); // secondary text (was black45/54)
Color faint = const Color(0x42000000); // tertiary icons (was black26)
Color hairline = const Color(0x1F000000); // borders (was black12)

/// Whether [mode] resolves to dark right now (system mode follows the OS).
bool resolveDark(ThemeMode mode) => switch (mode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
    };

void applyThemeTokens(bool dark) {
  surfaceCard = dark ? const Color(0xFF1D242C) : Colors.white;
  heroInk = dark ? const Color(0xFF242F3B) : ink;
  softTint = dark ? const Color(0xFF1E3B35) : primarySoft;
  subtle = dark ? const Color(0x9EFFFFFF) : const Color(0x8A000000);
  faint = dark ? const Color(0x54FFFFFF) : const Color(0x42000000);
  hairline = dark ? const Color(0x24FFFFFF) : const Color(0x1F000000);
}

ThemeData buildAppTheme() {
  // fromSeed derives a tonal primary that drifts from the brand colour, so
  // pin it — buttons, chips and toggles must all use the exact brand teal.
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.light,
    surface: Colors.white,
  ).copyWith(primary: primary);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    fontFamily: 'sans-serif',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontWeight: FontWeight.w800, color: ink),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, color: ink),
      titleLarge: TextStyle(fontWeight: FontWeight.w700, color: ink),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, color: ink),
      bodyLarge: TextStyle(height: 1.35, color: ink),
      bodyMedium: TextStyle(height: 1.35, color: Color(0xFF5C6670)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFE4E8E6)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.white,
      indicatorColor: primarySoft,
      elevation: 2,
      height: 72,
    ),
  );
}

ThemeData buildDarkTheme() {
  const surface = Color(0xFF1D242C);
  const lightText = Color(0xFFE9EEEC);
  final scheme = ColorScheme.fromSeed(
    seedColor: primary,
    brightness: Brightness.dark,
    surface: surface,
  ).copyWith(
    // A brighter teal keeps the brand readable on dark surfaces.
    primary: const Color(0xFF4FBFAC),
    onPrimary: const Color(0xFF06201B),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: const Color(0xFF12181E),
    fontFamily: 'sans-serif',
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontWeight: FontWeight.w800, color: lightText),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, color: lightText),
      titleLarge: TextStyle(fontWeight: FontWeight.w700, color: lightText),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, color: lightText),
      bodyLarge: TextStyle(height: 1.35, color: lightText),
      bodyMedium: TextStyle(height: 1.35, color: Color(0xFFA6B0B9)),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: surface,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF2A333D)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Color(0xFF161D24),
      indicatorColor: Color(0xFF1E3B35),
      elevation: 2,
      height: 72,
    ),
  );
}
