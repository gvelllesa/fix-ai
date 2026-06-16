import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// FIX AI 2026 Visual Style Guide (IBM Carbon Inspired)
class AppTheme {
  // IBM Carbon Palette
  static const Color deepObsidian = Color(0xFF161616); // bg-[#161616]
  static const Color surfaceObsidian = Color(0xFF262626); // bg-[#262626] for AI bubble
  static const Color surfaceHighlight = Color(0xFF393939); // border-[#393939]
  
  static const Color primaryBlue = Color(0xFF0F62FE); // text-primary
  static const Color primaryFixedDim = Color(0xFF78A9FF); // dark:text-primary-fixed-dim
  
  static const Color secondaryText = Color(0xFF6F6F6F); // text-secondary
  static const Color outlineVariant = Color(0xFFE0E0E0); // text-on-surface-variant / borders
  
  static const Color neonEmerald = Color(0xFFA7F0BA); // tertiary-container/glowing elements
  
  // Dynamic Crimson for Auto/Alert
  static const Color dynamicCrimson = Color(0xFFDA1E28); // error
  
  static ThemeData get lightTheme {
    const Color lightBackground = Color(0xFFFFFFFF); // Pure White
    const Color lightText = Color(0xFF111827); // Dark Slate/Black
    const Color inputAndBubbleLight = Color(0xFFF3F4F6); // Very light gray
    const Color primaryAccent = Color(0xFF2563EB); // Modern blue

    return ThemeData(
      brightness: Brightness.light,
      primaryColor: primaryAccent,
      scaffoldBackgroundColor: lightBackground,
      textTheme: GoogleFonts.ibmPlexSansTextTheme(ThemeData.light().textTheme).copyWith(
        bodyMedium: GoogleFonts.ibmPlexSans(color: lightText, fontSize: 16),
        bodyLarge: GoogleFonts.ibmPlexSans(color: lightText, fontSize: 18),
        titleLarge: GoogleFonts.ibmPlexSans(color: lightText, fontWeight: FontWeight.w600, fontSize: 20),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.black),
        titleTextStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
      ),
      colorScheme: const ColorScheme.light(
        primary: primaryAccent,
        secondary: primaryAccent,
        error: dynamicCrimson,
        surface: inputAndBubbleLight, // Used for Input Field and AI Bubble
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAccent,
          foregroundColor: Colors.white,
          side: const BorderSide(color: primaryAccent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      iconTheme: const IconThemeData(color: Colors.black),
      dividerColor: const Color(0xFFE5E7EB),
    );
  }

  static ThemeData get darkTheme {
    const Color darkBackground = Color(0xFF121212); // Pure Deep Charcoal
    const Color darkText = Color(0xFFF9FAFB); // Pure white/off-white
    const Color inputAndBubbleDark = Color(0xFF1E1E1E); // Elevated gray
    const Color primaryAccent = Color(0xFF2563EB); // Modern blue

    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: primaryAccent,
      scaffoldBackgroundColor: darkBackground,
      textTheme: GoogleFonts.ibmPlexSansTextTheme(ThemeData.dark().textTheme).copyWith(
        bodyMedium: GoogleFonts.ibmPlexSans(color: darkText, fontSize: 16),
        bodyLarge: GoogleFonts.ibmPlexSans(color: darkText, fontSize: 18),
        titleLarge: GoogleFonts.ibmPlexSans(color: darkText, fontWeight: FontWeight.w600, fontSize: 20),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
      ),
      colorScheme: const ColorScheme.dark(
        primary: primaryAccent,
        secondary: primaryAccent,
        error: dynamicCrimson,
        surface: inputAndBubbleDark, // Used for Input Field and AI Bubble
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryAccent,
          foregroundColor: Colors.white,
          side: const BorderSide(color: primaryAccent),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      iconTheme: const IconThemeData(color: Colors.white),
      dividerColor: const Color(0xFF374151),
    );
  }
}
