import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF08634F),
    brightness: brightness,
    primary: dark ? const Color(0xFFA5E9C8) : const Color(0xFF00634E),
    onPrimary: dark ? const Color(0xFF07392D) : Colors.white,
    surface: dark ? const Color(0xFF14221E) : const Color(0xFFFAFBFC),
    onSurface: dark ? const Color(0xFFF3F7F4) : const Color(0xFF152722),
    primaryContainer: dark ? const Color(0xFF25473B) : const Color(0xFFE3F3E9),
    onPrimaryContainer: dark
        ? const Color(0xFFC1F0D7)
        : const Color(0xFF0A5743),
    outline: dark ? const Color(0xFF8B9D96) : const Color(0xFF76827D),
    outlineVariant: dark ? const Color(0xFF34483F) : const Color(0xFFDCE3DF),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Archivo',
  );
  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    textTheme: base.textTheme.copyWith(
      displaySmall: base.textTheme.displaySmall?.copyWith(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.3,
        height: 1.1,
      ),
      headlineLarge: base.textTheme.headlineLarge?.copyWith(
        fontSize: 32,
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
        height: 1.15,
      ),
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontSize: 27,
        fontWeight: FontWeight.w700,
        letterSpacing: -.8,
        height: 1.15,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        letterSpacing: -.5,
      ),
      titleMedium: base.textTheme.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
        letterSpacing: -.3,
      ),
      bodyLarge: base.textTheme.bodyLarge?.copyWith(fontSize: 16, height: 1.4),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(
        fontSize: 14,
        height: 1.4,
      ),
      labelLarge: base.textTheme.labelLarge?.copyWith(
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF1D3028) : Colors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 54),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
        textStyle: const TextStyle(
          fontFamily: 'Archivo',
          fontWeight: FontWeight.w700,
          fontSize: 17,
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 52),
        side: BorderSide(color: scheme.primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(
          fontFamily: 'Archivo',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        textStyle: const TextStyle(
          fontFamily: 'Archivo',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1A2A24) : Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    chipTheme: base.chipTheme.copyWith(
      side: BorderSide(color: scheme.outlineVariant),
      backgroundColor: dark ? const Color(0xFF1D3028) : const Color(0xFFF0F3F2),
      selectedColor: scheme.primary,
      secondaryLabelStyle: TextStyle(color: scheme.onPrimary),
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      shape: const StadiumBorder(),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.onPrimary
            : Colors.white,
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? scheme.primary.withValues(
                alpha: states.contains(WidgetState.disabled) ? .55 : 1,
              )
            : scheme.outline.withValues(alpha: .65),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.inverseSurface,
      contentTextStyle: TextStyle(
        fontFamily: 'Archivo',
        color: scheme.onInverseSurface,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant),
  );
}
