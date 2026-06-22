import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Klaro design tokens + ThemeData.
/// Values come from design/klaro/klaro-handoff-v1/klaro-tokens.css — keep in sync.
abstract final class Klaro {
  // ---- Surfaces (dark-first, 4 levels) ----
  static const ink = Color(0xFF0A0A12); // app background
  static const tile = Color(0xFF0C0B14); // icon / splash tile
  static const surface = Color(0xFF14141F); // cards
  static const raised = Color(0xFF1C1C2B); // elevated cards, chips
  static const overlay = Color(0xFF26263A); // sheets, menus
  static const line = Color(0xFF23233A); // hairline borders

  // ---- Brand ----
  static const violet = Color(0xFF7C5CFF); // primary accent
  static const violetLt = Color(0xFF8B7CFF); // accent on dark (text/icons)
  static const blue = Color(0xFF4B7BFF); // secondary accent
  static const blueLt = Color(0xFF6FA8FF); // secondary on dark
  static const highlight = Color(0xFFB7AAFF); // light violet highlight

  // ---- Semantic ----
  static const positive = Color(0xFF34D399); // income / under budget
  static const alert = Color(0xFFFF8A5D); // over budget / warning
  static const danger = Color(0xFFFF6B6B); // destructive

  // ---- Text ----
  static const text = Color(0xFFECEAF7); // primary
  static const textMuted = Color(0xFF8D8AA8); // secondary
  static const textFaint = Color(0xFF5B5B73); // tertiary / disabled

  // ---- Gradient (brand signature, ~132deg) ----
  // Only on: primary buttons, the logo/splash, progress accents — never behind
  // body text or data rows.
  static const gradient = LinearGradient(
    begin: Alignment(-0.74, -1.0),
    end: Alignment(0.74, 1.0),
    colors: [violet, blue],
  );

  // ---- Radius ----
  static const radiusSm = 8.0;
  static const radiusMd = 14.0;
  static const radiusLg = 18.0;
  static const radiusXl = 22.0;
  static const radiusPill = 30.0;

  // ---- Motion ----
  static const ease = Cubic(0.2, 0.8, 0.25, 1);
  static const durFast = Duration(milliseconds: 150);
  static const durBase = Duration(milliseconds: 300);
  static const durSlow = Duration(milliseconds: 500);

  // ---- Typography helpers ----
  static const display = 'Poppins'; // wordmark + headings
  static const sans = 'Inter'; // UI + body (ThemeData default)
  static const mono = 'JetBrains Mono'; // figures

  /// Monospace style for money figures.
  static TextStyle figures({
    double size = 16,
    FontWeight weight = FontWeight.w500,
    Color color = text,
  }) =>
      TextStyle(
        fontFamily: mono,
        fontSize: size,
        fontWeight: weight,
        color: color,
        letterSpacing: -0.3,
      );

  // ---- Category accents (harmonized with the web dashboard palette) ----
  static const Map<String, Color> _categoryColors = {
    'Food': Color(0xFFFF8A5D),
    'Grocery': Color(0xFF34D399),
    'Shopping': Color(0xFFB7AAFF),
    'Transport': Color(0xFF6FA8FF),
    'Entertainment': Color(0xFF8B7CFF),
    'Personal': Color(0xFF38BDF8),
    'Transfer': Color(0xFF94A3B8),
    'Bills': Color(0xFF4B7BFF),
    'Health': Color(0xFFFF6B6B),
    'Fuel': Color(0xFFFB923C),
    'Cash': Color(0xFF94A3B8),
    'Games': Color(0xFF7C5CFF),
  };

  static Color categoryColor(String? category) =>
      _categoryColors[category] ?? textMuted;

  // ---- ThemeData ----
  static ThemeData theme() {
    const scheme = ColorScheme.dark(
      primary: violet,
      onPrimary: Colors.white,
      secondary: blue,
      onSecondary: Colors.white,
      surface: surface,
      onSurface: text,
      surfaceContainerHighest: raised,
      error: danger,
      onError: Colors.white,
      outline: line,
      onSurfaceVariant: textMuted,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: ink,
      canvasColor: overlay, // dropdown menus
      fontFamily: sans,
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(bodyColor: text, displayColor: text),
      appBarTheme: const AppBarTheme(
        backgroundColor: ink,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: display,
          fontWeight: FontWeight.w600,
          fontSize: 20,
          color: text,
          letterSpacing: -0.3,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
        ),
      ),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: raised,
        labelStyle: const TextStyle(color: textMuted),
        hintStyle: const TextStyle(color: textFaint),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: line),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: violet, width: 1.5),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: line),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
        textStyle: const TextStyle(fontFamily: sans, fontSize: 14, color: text),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: overlay,
        contentTextStyle:
            const TextStyle(fontFamily: sans, fontSize: 13.5, color: text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: violet),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: violetLt),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          side: const BorderSide(color: line),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusMd),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: violet,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusPill),
          ),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        textColor: text,
        iconColor: textMuted,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: overlay,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusLg),
        ),
      ),
    );
  }
}
