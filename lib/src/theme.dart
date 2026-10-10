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
/// The brand accent for icons, links and highlights: the teal in light mode,
/// a vivid aqua in dark mode (the teal is too dim on black).
Color accent = primary;
// Status and category colours: deeper on white, brighter on black.
Color success = primary; // paid, verified, resolved
Color danger = const Color(0xFFD44B47); // overdue, errors, declined
Color info = const Color(0xFF3478C7); // in progress, partial
Color amber = const Color(0xFFB7791F); // due, pending
Color pink = const Color(0xFFB65B87);
Color violet = const Color(0xFF7656B1);
Color slate = const Color(0xFF536179);

/// Header gradient of a property card.
List<Color> heroGradient = const [Color(0xFF195F59), Color(0xFF45A497)];
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

// True-black dark palette: black page, near-black cards, white text and
// one bright accent, so text and icons stand out.
const darkBackground = Color(0xFF000000);
const darkCard = Color(0xFF121214);
const darkRaised = Color(0xFF1C1C1F); // hero cards, chips, dialogs
const darkAccent = Color(0xFF2EE6D6);
const darkText = Color(0xFFFFFFFF);
const darkTextSoft = Color(0xFFB4B4BD);

void applyThemeTokens(bool dark) {
  accent = dark ? darkAccent : primary;
  success = dark ? const Color(0xFF4ADE80) : primary;
  danger = dark ? const Color(0xFFFF6B6B) : const Color(0xFFD44B47);
  info = dark ? const Color(0xFF6CB4FF) : const Color(0xFF3478C7);
  amber = dark ? const Color(0xFFFFC857) : const Color(0xFFB7791F);
  pink = dark ? const Color(0xFFFF8CC6) : const Color(0xFFB65B87);
  violet = dark ? const Color(0xFFB79CFF) : const Color(0xFF7656B1);
  slate = dark ? darkTextSoft : const Color(0xFF536179);
  heroGradient = dark
      ? const [Color(0xFF1C1C1F), Color(0xFF2C2C33)]
      : const [Color(0xFF195F59), Color(0xFF45A497)];
  surfaceCard = dark ? darkCard : Colors.white;
  heroInk = dark ? darkRaised : ink;
  softTint = dark ? const Color(0xFF232327) : primarySoft;
  subtle = dark ? darkTextSoft : const Color(0x8A000000);
  faint = dark ? const Color(0x73FFFFFF) : const Color(0x42000000);
  hairline = dark ? const Color(0x2EFFFFFF) : const Color(0x1F000000);
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
  final scheme = ColorScheme.fromSeed(
    seedColor: darkAccent,
    brightness: Brightness.dark,
    surface: darkCard,
  ).copyWith(
    primary: darkAccent,
    onPrimary: Colors.black,
    secondary: darkAccent,
    onSecondary: Colors.black,
    surface: darkCard,
    onSurface: darkText,
    onSurfaceVariant: darkTextSoft,
    surfaceContainerLowest: darkBackground,
    surfaceContainerLow: darkCard,
    surfaceContainer: darkCard,
    surfaceContainerHigh: darkRaised,
    surfaceContainerHighest: darkRaised,
    outline: const Color(0x52FFFFFF),
    outlineVariant: const Color(0x2EFFFFFF),
    error: const Color(0xFFFF6B6B),
  );
  const border = BorderSide(color: Color(0x2EFFFFFF));
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: darkBackground,
    canvasColor: darkBackground,
    dividerColor: const Color(0x2EFFFFFF),
    fontFamily: 'sans-serif',
    iconTheme: const IconThemeData(color: darkText),
    textTheme: const TextTheme(
      headlineLarge: TextStyle(fontWeight: FontWeight.w800, color: darkText),
      headlineMedium: TextStyle(fontWeight: FontWeight.w800, color: darkText),
      titleLarge: TextStyle(fontWeight: FontWeight.w700, color: darkText),
      titleMedium: TextStyle(fontWeight: FontWeight.w700, color: darkText),
      bodyLarge: TextStyle(height: 1.35, color: darkText),
      bodyMedium: TextStyle(height: 1.35, color: darkTextSoft),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: darkBackground,
      foregroundColor: darkText,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
    ),
    // A hairline border lets near-black cards read as cards on black.
    cardTheme: CardThemeData(
      elevation: 0,
      color: darkCard,
      surfaceTintColor: Colors.transparent,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20), side: border),
    ),
    dialogTheme: const DialogThemeData(
        backgroundColor: darkRaised, surfaceTintColor: Colors.transparent),
    bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: darkCard, surfaceTintColor: Colors.transparent),
    popupMenuTheme: const PopupMenuThemeData(
        color: darkRaised, surfaceTintColor: Colors.transparent),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: darkRaised,
      contentTextStyle: TextStyle(color: darkText),
      actionTextColor: darkAccent,
    ),
    listTileTheme:
        const ListTileThemeData(iconColor: darkText, textColor: darkText),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: darkCard,
      labelStyle: const TextStyle(color: darkTextSoft),
      hintStyle: const TextStyle(color: Color(0x73FFFFFF)),
      prefixIconColor: darkTextSoft,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: border,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: darkAccent, width: 1.6),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: darkAccent,
        foregroundColor: Colors.black,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: darkAccent,
        side: const BorderSide(color: Color(0x66FFFFFF)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: darkAccent)),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: darkAccent, foregroundColor: Colors.black),
    chipTheme: const ChipThemeData(
      backgroundColor: darkCard,
      selectedColor: darkAccent,
      side: border,
      labelStyle: TextStyle(color: darkText),
      secondaryLabelStyle: TextStyle(color: Colors.black),
      checkmarkColor: Colors.black,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: darkBackground,
      surfaceTintColor: Colors.transparent,
      indicatorColor: darkAccent,
      elevation: 0,
      height: 72,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? Colors.black
              : darkTextSoft)),
      labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color:
              states.contains(WidgetState.selected) ? darkText : darkTextSoft)),
    ),
  );
}
