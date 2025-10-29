import 'package:flutter/material.dart';

class ThemeManager {
  static final lightTheme = ThemeData(
    brightness: Brightness.light,
    scaffoldBackgroundColor: const Color(0xFFF2F2F2),
    primaryColor: const Color(0xFF6C4AB6),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.black87),
      bodyMedium: TextStyle(color: Colors.black87),
    ),
  );

  static final darkTheme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: const Color(0xFF121212),
    primaryColor: const Color(0xFF9D8DF1),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Colors.white),
      bodyMedium: TextStyle(color: Colors.white),
    ),
  );

  static void toggleTheme(BuildContext context, bool isDark) {
    final brightness = isDark ? Brightness.light : Brightness.dark;
    WidgetsBinding.instance.window.platformBrightness == brightness;
  }
}
