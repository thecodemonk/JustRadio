import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const bgBase = Color(0xFF070708);
  static const bgElevated = Color(0xFF111114);
  static const accent = Color(0xFF9A7FD6);
  static const live = Color(0xFFFF4F4F);
  static const scrobble = Color(0xFFFF5566);

  static const onBg = Color(0xFFF2EFE8);
  static const onBgStrong = Colors.white;

  static Color onBgMuted([double alpha = 0.7]) => onBg.withValues(alpha: alpha);
  static Color border([double alpha = 0.08]) =>
      Colors.white.withValues(alpha: alpha);
  static Color surface([double alpha = 0.03]) =>
      Colors.white.withValues(alpha: alpha);
  static Color accentGlow([double alpha = 0.33]) =>
      accent.withValues(alpha: alpha);
}

class AppTypography {
  static TextStyle display(double size, {Color? color, double height = 1.05}) =>
      GoogleFonts.instrumentSerif(
        fontSize: size,
        fontStyle: FontStyle.italic,
        letterSpacing: -size * 0.025,
        height: height,
        color: color ?? AppColors.onBgStrong,
      );

  static TextStyle mono(
    double size, {
    Color? color,
    double letterSpacing = 1.5,
    FontWeight weight = FontWeight.w400,
  }) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        color: color ?? AppColors.onBgMuted(0.55),
        letterSpacing: letterSpacing,
        fontWeight: weight,
      );

  static TextStyle label(double size,
          {Color? color, double letterSpacing = 2}) =>
      GoogleFonts.jetBrainsMono(
        fontSize: size,
        color: color ?? AppColors.onBgMuted(0.45),
        letterSpacing: letterSpacing,
        fontWeight: FontWeight.w500,
      );

  static TextStyle body(double size, {Color? color, FontWeight? weight}) =>
      GoogleFonts.inter(
        fontSize: size,
        color: color ?? AppColors.onBg,
        fontWeight: weight ?? FontWeight.w400,
      );
}

class AppTheme {
  static ThemeData dark() {
    final base = ThemeData.dark(useMaterial3: true);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.accent,
      brightness: Brightness.dark,
      primary: AppColors.accent,
      surface: AppColors.bgBase,
      onSurface: AppColors.onBg,
    );

    final textTheme = GoogleFonts.interTextTheme(base.textTheme).apply(
      bodyColor: AppColors.onBg,
      displayColor: AppColors.onBgStrong,
    );

    return base.copyWith(
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.bgBase,
      canvasColor: AppColors.bgBase,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: const IconThemeData(color: AppColors.onBg),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: AppColors.onBg,
        iconTheme: const IconThemeData(color: AppColors.onBg),
        titleTextStyle: AppTypography.display(22),
        systemOverlayStyle: null,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: AppColors.surface(0.03),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.onBg,
        textColor: AppColors.onBg,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.border(0.06),
        thickness: 1,
        space: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface(0.04),
        hintStyle: TextStyle(color: AppColors.onBgMuted(0.4)),
        prefixIconColor: AppColors.onBgMuted(0.5),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border(0.06)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.border(0.06)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: AppColors.accent.withValues(alpha: 0.4)),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface(0.05),
        selectedColor: AppColors.accent,
        secondarySelectedColor: AppColors.accent,
        disabledColor: AppColors.surface(0.02),
        labelStyle: TextStyle(color: AppColors.onBgMuted(0.8), fontSize: 12),
        secondaryLabelStyle:
            const TextStyle(color: Color(0xFF0A0A0A), fontSize: 12),
        side: BorderSide.none,
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        checkmarkColor: const Color(0xFF0A0A0A),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.black.withValues(alpha: 0.55),
        surfaceTintColor: Colors.transparent,
        indicatorColor: AppColors.accent.withValues(alpha: 0.18),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.onBgMuted(0.55),
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => GoogleFonts.inter(
            fontSize: 11,
            color: states.contains(WidgetState.selected)
                ? AppColors.accent
                : AppColors.onBgMuted(0.55),
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w500
                : FontWeight.w400,
          ),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.bgElevated,
        contentTextStyle: const TextStyle(color: AppColors.onBg),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.bgElevated,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: AppTypography.display(22),
        contentTextStyle: AppTypography.body(14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: AppColors.bgElevated,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.border(0.15),
        thumbColor: Colors.white,
        overlayColor: AppColors.accent.withValues(alpha: 0.15),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.accent,
        foregroundColor: Color(0xFF0A0A0A),
      ),
    );
  }
}
