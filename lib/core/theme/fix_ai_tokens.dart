import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Design tokens for FIX AI (Dark-Tech / Automotive Precision System)
/// Follows DTCG 3-tier token architecture and strict accessibility requirements.
class FixAiTokens {
  FixAiTokens._();

  // ==========================================
  // 1. Color Palette (Surfaces, Neutrals & Accents)
  // ==========================================

  // Surfaces & Canvas (Dark Obsidian Theme)
  static const Color canvas = Color(0xFF090C10);
  static const Color surfacePrimary = Color(0xFF131822);
  static const Color surfaceElevated = Color(0xFF18202E);
  static const Color surfaceHighlight = Color(0xFF222B3D);
  static const Color surfaceGlass = Color(0xCC131822);

  // Borders & Dividers
  static const Color borderSubtle = Color(0xFF1F2837);
  static const Color borderGlow = Color(0xFF2E3D52);
  static const Color borderBright = Color(0xFF3F4F66);

  // High-Precision Brand & Status Accents
  static const Color accentCyan = Color(0xFF00E5FF);     // Telemetry & UDS
  static const Color accentEmerald = Color(0xFF10B981);  // System Normal / OK / Connected
  static const Color accentAmber = Color(0xFFF59E0B);    // Calibration / Staged / Tuning
  static const Color accentRose = Color(0xFFEF4444);     // Critical Fault / Safety Warning
  static const Color accentPurple = Color(0xFF8B5CF6);   // Coding / Cheat Codes
  static const Color accentBlue = Color(0xFF3B82F6);     // Factory Modules / Topology

  // Typography Neutrals (WCAG AAA compliant)
  static const Color textPrimary = Color(0xFFF3F4F6);    // Off-white headline/body
  static const Color textSecondary = Color(0xFF9CA3AF);  // Readable secondary text
  static const Color textMuted = Color(0xFF6B7280);      // Caption / microcopy
  static const Color textDisabled = Color(0xFF4B5563);   // Disabled controls

  // ==========================================
  // 2. 4px Spacing Rhythm
  // ==========================================
  static const double space4 = 4.0;
  static const double space8 = 8.0;
  static const double space12 = 12.0;
  static const double space16 = 16.0;
  static const double space20 = 20.0;
  static const double space24 = 24.0;
  static const double space32 = 32.0;
  static const double space40 = 40.0;

  // ==========================================
  // 3. Border Radii
  // ==========================================
  static const double radiusSm = 8.0;
  static const double radiusMd = 12.0;
  static const double radiusLg = 16.0;
  static const double radiusXl = 20.0;
  static const double radiusPill = 999.0;

  static final BorderRadius borderRadiusSm = BorderRadius.circular(radiusSm);
  static final BorderRadius borderRadiusMd = BorderRadius.circular(radiusMd);
  static final BorderRadius borderRadiusLg = BorderRadius.circular(radiusLg);
  static final BorderRadius borderRadiusXl = BorderRadius.circular(radiusXl);
  static final BorderRadius borderRadiusPill = BorderRadius.circular(radiusPill);

  // ==========================================
  // 4. Typography Styles
  // ==========================================
  static TextStyle get displayLarge => GoogleFonts.ibmPlexSans(
        color: textPrimary,
        fontSize: 26,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.2,
      );

  static TextStyle get titleLarge => GoogleFonts.ibmPlexSans(
        color: textPrimary,
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.25,
      );

  static TextStyle get titleMedium => GoogleFonts.ibmPlexSans(
        color: textPrimary,
        fontSize: 15,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.1,
      );

  static TextStyle get sectionHeader => GoogleFonts.ibmPlexSans(
        color: textSecondary,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
      );

  static TextStyle get bodyMedium => GoogleFonts.ibmPlexSans(
        color: textPrimary,
        fontSize: 14,
        fontWeight: FontWeight.w400,
        height: 1.4,
      );

  static TextStyle get bodySmall => GoogleFonts.ibmPlexSans(
        color: textSecondary,
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 1.35,
      );

  static TextStyle get monoLabel => GoogleFonts.ibmPlexMono(
        color: textPrimary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5,
      );

  static TextStyle get monoNumeric => GoogleFonts.ibmPlexMono(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
      );
}
