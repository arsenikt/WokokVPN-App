import 'package:flutter/material.dart';

/// Wokok palette — shared with the Chrome extension and the website.
class Wok {
  static const bg = Color(0xFF1B1614);
  static const bg2 = Color(0xFF26201C);
  static const card = Color(0xFF2E2621);
  static const paper = Color(0xFFF6EAD2);
  static const fire = Color(0xFFFF7A1A);
  static const chili = Color(0xFFE5341B);
  static const gold = Color(0xFFFFD23F);
  static const muted = Color(0xFF9C8B7C);
  static const jade = Color(0xFF7BC043);
}

ThemeData wokTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: Wok.fire,
    brightness: Brightness.dark,
  ).copyWith(
    surface: Wok.bg,
    primary: Wok.fire,
    secondary: Wok.gold,
    error: Wok.chili,
    onSurface: Wok.paper,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: Wok.bg,
    canvasColor: Wok.bg,
    cardTheme: CardThemeData(
      color: Wok.card,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Wok.bg2,
      indicatorColor: Wok.fire.withValues(alpha: .22),
      labelTextStyle: WidgetStatePropertyAll(
          const TextStyle(fontSize: 12, color: Wok.paper)),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: Wok.bg2,
      indicatorColor: Wok.fire.withValues(alpha: .22),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? Wok.gold : Wok.muted),
      trackColor: WidgetStateProperty.resolveWith((s) =>
          s.contains(WidgetState.selected)
              ? Wok.fire.withValues(alpha: .6)
              : Wok.bg2),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Wok.card,
      contentTextStyle: const TextStyle(color: Wok.paper),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}
