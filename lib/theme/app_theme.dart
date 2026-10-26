import 'package:flutter/material.dart';

import '../models/user_preferences.dart';

class DesignPalette {
  const DesignPalette(this.background, this.accent, this.soft);
  final Color background;
  final Color accent;
  final Color soft;
  static DesignPalette of(AppDesign design) => switch (design) {
    AppDesign.minimal => const DesignPalette(
      Color(0xFFFAF8F4),
      Color(0xFF75634E),
      Color(0xFFEFE8DC),
    ),
    AppDesign.lovely => const DesignPalette(
      Color(0xFFFFF7FA),
      Color(0xFFA8486B),
      Color(0xFFF7DEEA),
    ),
    AppDesign.modern => const DesignPalette(
      Color(0xFFF5F5F5),
      Color(0xFF202020),
      Color(0xFFE4E4E4),
    ),
  };
}

ThemeData buildAppTheme(AppDesign design) {
  final palette = DesignPalette.of(design);
  final scheme = ColorScheme.fromSeed(
    seedColor: palette.accent,
    primary: palette.accent,
    surface: palette.background,
    secondaryContainer: palette.soft,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.background,
    fontFamilyFallback: const [
      'Noto Sans KR',
      'Malgun Gothic',
      'Apple SD Gothic Neo',
    ],
    textTheme: const TextTheme(
      headlineLarge: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 1.35,
        letterSpacing: -1.3,
      ),
      headlineMedium: TextStyle(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        height: 1.4,
        letterSpacing: -0.8,
      ),
      titleLarge: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
      bodyLarge: TextStyle(fontSize: 16, height: 1.7),
      bodyMedium: TextStyle(fontSize: 14, height: 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.background,
      indicatorColor: palette.soft,
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: palette.background,
      indicatorColor: palette.soft,
    ),
  );
}
