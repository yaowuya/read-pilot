import 'package:flutter/material.dart';

class AppColors {
  static const ink = Color(0xFF252932);
  static const muted = Color(0xFF626976);
  static const blue = Color(0xFF2468DE);
  static const background = Color(0xFFF7F8FA);
  static const line = Color(0xFFE7E9EE);
  static const softBlue = Color(0xFFEDF3FF);
}

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'NotoSansSC',
  colorScheme: ColorScheme.fromSeed(
    seedColor: AppColors.blue,
    surface: Colors.white,
  ).copyWith(primary: AppColors.blue, onPrimary: Colors.white),
  scaffoldBackgroundColor: AppColors.background,
  textTheme: const TextTheme(
    headlineLarge: TextStyle(
      fontSize: 30,
      height: 1.35,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      height: 1.5,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.7, color: AppColors.ink),
    bodyMedium: TextStyle(fontSize: 14, height: 1.65, color: AppColors.ink),
    bodySmall: TextStyle(fontSize: 12, height: 1.5, color: AppColors.muted),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: AppColors.background,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: false,
  ),
  dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.blue,
      foregroundColor: Colors.white,
      minimumSize: const Size(44, 46),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(44, 44),
      foregroundColor: AppColors.ink,
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  ),
  navigationBarTheme: NavigationBarThemeData(
    backgroundColor: Colors.white,
    elevation: 0,
    height: 72,
    indicatorColor: AppColors.softBlue,
    labelTextStyle: WidgetStateProperty.resolveWith(
      (states) => TextStyle(
        fontFamily: 'NotoSansSC',
        fontSize: 12,
        color: states.contains(WidgetState.selected)
            ? AppColors.blue
            : AppColors.muted,
      ),
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
  ),
);
