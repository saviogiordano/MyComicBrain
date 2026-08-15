import 'package:flutter/material.dart';

import 'package:mycomicbrain/core/design_system/tokens.dart';

/// Tema Material unico dell'app — nessuna divergenza Cupertino (deciso su #7).
/// Costruito sugli stessi token di [AppColors]/[AppTypography]/[AppRadii]
/// usati direttamente dai componenti in `components/`.
abstract final class AppTheme {
  static ThemeData get dark {
    final colorScheme = const ColorScheme.dark().copyWith(
      brightness: Brightness.dark,
      surface: AppColors.surfaceBase,
      onSurface: AppColors.textPrimary,
      primary: AppColors.accent,
      onPrimary: AppColors.onAccent,
      secondary: AppColors.amber,
      onSecondary: AppColors.onAccent,
      error: AppColors.amberStrong,
      onError: AppColors.textPrimary,
      outline: AppColors.borderDefault,
      outlineVariant: AppColors.borderSubtle,
    );

    final textTheme = TextTheme(
      displayLarge: AppTypography.heroNumber.copyWith(color: AppColors.textPrimary),
      displayMedium: AppTypography.pageTitle.copyWith(color: AppColors.textPrimary),
      displaySmall: AppTypography.headline.copyWith(color: AppColors.textPrimary),
      titleLarge: AppTypography.titleLarge.copyWith(color: AppColors.textPrimary),
      titleMedium: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
      titleSmall: AppTypography.kpiValue.copyWith(color: AppColors.textPrimary),
      bodyLarge: AppTypography.bodyLarge.copyWith(color: AppColors.textPrimary),
      bodyMedium: AppTypography.bodyMedium.copyWith(color: AppColors.textSecondary),
      bodySmall: AppTypography.bodySmall.copyWith(color: AppColors.textTertiary),
      labelLarge: AppTypography.labelLarge.copyWith(color: AppColors.onAccent),
      labelMedium: AppTypography.labelMedium.copyWith(color: AppColors.textSecondary),
      labelSmall: AppTypography.sectionHeader.copyWith(color: AppColors.textMuted),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.surfaceBase,
      canvasColor: AppColors.surfaceBase,
      fontFamily: AppFonts.sans,
      textTheme: textTheme,
      dividerColor: AppColors.borderDefault,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.surfaceBase,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: AppTypography.titleMedium.copyWith(color: AppColors.textPrimary),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.onAccent,
          textStyle: AppTypography.labelLarge,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.mdRadius),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.borderStrong),
          textStyle: AppTypography.labelLarge,
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          shape: RoundedRectangleBorder(borderRadius: AppRadii.mdRadius),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          textStyle: AppTypography.labelMedium,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.overlayCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.lgRadius,
          side: const BorderSide(color: AppColors.borderDefault),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.surfaceBase,
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accentAlpha(0.14),
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => AppTypography.bodySmall.copyWith(
            color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? AppColors.accent : AppColors.textMuted,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.overlayCard,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.sm),
        hintStyle: AppTypography.bodyLarge.copyWith(color: AppColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: AppRadii.mdRadius,
          borderSide: const BorderSide(color: AppColors.borderDefault),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdRadius,
          borderSide: const BorderSide(color: AppColors.borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.mdRadius,
          borderSide: const BorderSide(color: AppColors.accent),
        ),
      ),
    );
  }
}
