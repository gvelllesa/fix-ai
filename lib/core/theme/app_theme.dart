import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'fix_ai_tokens.dart';

/// FIX AI Visual Style Guide (Dark-Tech / Automotive Precision System)
class AppTheme {
  // Backward compatibility palette
  static const Color deepObsidian = FixAiTokens.canvas;
  static const Color surfaceObsidian = FixAiTokens.surfacePrimary;
  static const Color surfaceHighlight = FixAiTokens.surfaceHighlight;

  static const Color primaryBlue = FixAiTokens.accentCyan;
  static const Color primaryFixedDim = Color(0xFF78A9FF);

  static const Color secondaryText = FixAiTokens.textSecondary;
  static const Color outlineVariant = FixAiTokens.borderSubtle;

  static const Color neonEmerald = FixAiTokens.accentEmerald;
  static const Color dynamicCrimson = FixAiTokens.accentRose;

  static ThemeData get lightTheme {
    const Color lightBackground = Color(0xFFF9FAFB);
    const Color lightText = Color(0xFF111827);
    const Color inputAndBubbleLight = Color(0xFFF3F4F6);
    const Color primaryAccent = Color(0xFF0F62FE);

    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryAccent,
      scaffoldBackgroundColor: lightBackground,
      textTheme: GoogleFonts.ibmPlexSansTextTheme(ThemeData.light().textTheme).copyWith(
        bodyMedium: GoogleFonts.ibmPlexSans(color: lightText, fontSize: 14),
        bodyLarge: GoogleFonts.ibmPlexSans(color: lightText, fontSize: 16),
        titleLarge: GoogleFonts.ibmPlexSans(color: lightText, fontWeight: FontWeight.w700, fontSize: 20),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black87),
        titleTextStyle: TextStyle(color: Colors.black87, fontWeight: FontWeight.bold, fontSize: 18),
      ),
      colorScheme: const ColorScheme.light(
        primary: primaryAccent,
        secondary: primaryAccent,
        error: dynamicCrimson,
        surface: inputAndBubbleLight,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FixAiTokens.borderRadiusMd,
          side: const BorderSide(color: Color(0xFFE5E7EB)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAccent,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: FixAiTokens.borderRadiusSm),
        ),
      ),
      iconTheme: const IconThemeData(color: Colors.black87),
      dividerColor: const Color(0xFFE5E7EB),
    );
  }

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: FixAiTokens.accentCyan,
      scaffoldBackgroundColor: FixAiTokens.canvas,
      textTheme: GoogleFonts.ibmPlexSansTextTheme(ThemeData.dark().textTheme).copyWith(
        bodySmall: GoogleFonts.ibmPlexSans(color: FixAiTokens.textSecondary, fontSize: 12),
        bodyMedium: GoogleFonts.ibmPlexSans(color: FixAiTokens.textPrimary, fontSize: 14),
        bodyLarge: GoogleFonts.ibmPlexSans(color: FixAiTokens.textPrimary, fontSize: 16),
        titleMedium: GoogleFonts.ibmPlexSans(color: FixAiTokens.textPrimary, fontWeight: FontWeight.w600, fontSize: 16),
        titleLarge: GoogleFonts.ibmPlexSans(color: FixAiTokens.textPrimary, fontWeight: FontWeight.w700, fontSize: 20),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: FixAiTokens.surfacePrimary,
        elevation: 0,
        iconTheme: IconThemeData(color: FixAiTokens.textPrimary),
        titleTextStyle: TextStyle(color: FixAiTokens.textPrimary, fontWeight: FontWeight.bold, fontSize: 18),
      ),
      colorScheme: const ColorScheme.dark(
        primary: FixAiTokens.accentCyan,
        secondary: FixAiTokens.accentEmerald,
        error: FixAiTokens.accentRose,
        surface: FixAiTokens.surfacePrimary,
      ),
      cardTheme: CardThemeData(
        color: FixAiTokens.surfacePrimary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: FixAiTokens.borderRadiusMd,
          side: const BorderSide(color: FixAiTokens.borderSubtle),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: FixAiTokens.accentCyan,
          foregroundColor: FixAiTokens.canvas,
          elevation: 0,
          textStyle: const TextStyle(fontWeight: FontWeight.bold),
          shape: RoundedRectangleBorder(borderRadius: FixAiTokens.borderRadiusSm),
        ),
      ),
      iconTheme: const IconThemeData(color: FixAiTokens.textPrimary),
      dividerColor: FixAiTokens.borderSubtle,
    );
  }
}
