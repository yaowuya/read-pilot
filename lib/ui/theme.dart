import 'package:flutter/material.dart';

/// Design tokens mirrored from `docs/阅读助手_完整设计稿.html`.
///
/// The design draft is the single visual reference for the refactor, so the
/// values below are transcribed from its `:root` variables instead of being
/// picked by hand. Names keep the historical `AppColors` spelling so the rest
/// of the UI does not have to be renamed for a colour change.
class AppColors {
  /// Primary action / selected state.
  static const blue = Color(0xFF2878F0);

  /// Titles and body text.
  static const ink = Color(0xFF23262C);

  /// Secondary text, captions, placeholders.
  static const muted = Color(0xFF858B96);

  /// Dividers and borders.
  static const line = Color(0xFFEDF0F3);

  /// Page background.
  static const background = Color(0xFFF3F4F6);

  /// Tinted blue used by selected chips and soft highlights.
  static const softBlue = Color(0xFFEDF4FF);

  /// Soft panel behind the shelf continue-card and the profile stats card.
  static const panel = Color(0xFFF5F7FA);

  /// Reader paper theme background.
  static const paper = Color(0xFFF6F3EC);

  /// Reader night theme background; body text is [nightInk].
  static const night = Color(0xFF202225);
  static const nightInk = Color(0xFFC3C0B8);

  /// Eye-comfort reader background.
  static const green = Color(0xFF4A8B74);
  static const softGreen = Color(0xFFEAF2E6);
}

/// Shared geometry taken from the draft: buttons use a 10 px radius, light
/// cards 12 px, bottom sheets 22 px, and interactive icon targets 44 px.
class AppRadii {
  static const button = 10.0;
  static const card = 12.0;
  static const sheet = 22.0;
  static const pill = 999.0;
}

class AppSpacing {
  /// Phone layouts use the draft `.pad` gutter of 25.
  ///
  /// Wide layouts keep a larger gutter so the existing sidebar shell does not
  /// stretch the 390-wide phone frame across the desktop.
  static const page = 25.0;
  static const pageWide = 40.0;
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
      fontSize: 28,
      height: 1.3,
      fontWeight: FontWeight.w700,
      color: AppColors.ink,
    ),
    headlineMedium: TextStyle(
      fontSize: 22,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
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
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    centerTitle: true,
    foregroundColor: AppColors.ink,
    titleTextStyle: TextStyle(
      fontFamily: 'NotoSansSC',
      fontSize: 16,
      fontWeight: FontWeight.w600,
      color: AppColors.ink,
    ),
  ),
  dividerTheme: const DividerThemeData(color: AppColors.line, space: 1),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: Colors.white,
    hintStyle: const TextStyle(color: AppColors.muted, fontSize: 14),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      borderSide: const BorderSide(color: AppColors.line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      borderSide: const BorderSide(color: AppColors.line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadii.card),
      borderSide: const BorderSide(color: AppColors.blue, width: 1.5),
    ),
  ),
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.blue,
      foregroundColor: Colors.white,
      minimumSize: const Size(44, 48),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      textStyle: const TextStyle(
        fontFamily: 'NotoSansSC',
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      minimumSize: const Size(44, 44),
      foregroundColor: AppColors.ink,
      side: const BorderSide(color: AppColors.line),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.button),
      ),
    ),
  ),
  textButtonTheme: TextButtonThemeData(
    style: TextButton.styleFrom(
      foregroundColor: AppColors.blue,
      minimumSize: const Size(0, 36),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      textStyle: const TextStyle(
        fontFamily: 'NotoSansSC',
        fontSize: 13,
        fontWeight: FontWeight.w500,
      ),
    ),
  ),
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadii.button),
    ),
  ),
  bottomSheetTheme: const BottomSheetThemeData(
    backgroundColor: Colors.white,
    surfaceTintColor: Colors.transparent,
    showDragHandle: true,
  ),
);
