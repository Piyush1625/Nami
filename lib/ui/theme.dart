import 'package:flutter/material.dart';

ThemeData buildTheme(
  Color seed,
  Brightness brightness, {
  bool amoled = false,
  bool liquidGlass = false,
}) {
  final useBlack = amoled && brightness == Brightness.dark;
  var scheme = ColorScheme.fromSeed(seedColor: seed, brightness: brightness);
  if (useBlack) {
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainer: const Color(0xFF07070B),
      surfaceContainerLow: Colors.black,
      surfaceContainerHigh: const Color(0xFF0E0E14),
    );
  }

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: useBlack ? Colors.black : null,
    cardTheme: CardThemeData(
      color: useBlack
          ? (liquidGlass
              ? scheme.primary.withValues(alpha: 0.08)
              : const Color(0xFF0A0A0F))
          : null,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: liquidGlass
            ? BorderSide(color: scheme.primary.withValues(alpha: 0.22), width: 1)
            : BorderSide.none,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: useBlack ? Colors.black : null,
      scrolledUnderElevation: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: useBlack ? Colors.black : null,
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16),
    ),
  );
}
