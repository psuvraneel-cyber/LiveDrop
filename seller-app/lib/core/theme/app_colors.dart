import 'package:flutter/material.dart';

/// LiveDrop Seller App — Luxury Boutique Noir Design System Color Tokens
/// Strictly mirrors the authoritative 11-screen design specification.
abstract class AppColors {
  // Deep Obsidian Backgrounds
  static const Color obsidian = Color(0xFF0C0C0E);
  static const Color obsidianSurface = Color(0xFF17171C);
  static const Color obsidianElevated = Color(0xFF1C1C22);
  static const Color inputBackground = Color(0xFF141418);
  static const Color cardBorder = Color(0xFF282832);

  // Metallic Gold Accents & Gradients
  static const Color goldPrimary = Color(0xFFE5A93C);
  static const Color goldSecondary = Color(0xFFC88A24);
  static const Color goldLight = Color(0xFFFDE68A);
  static const Color goldMuted = Color(0x33E5A93C);

  static const LinearGradient goldGradient = LinearGradient(
    colors: [goldPrimary, goldSecondary],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient subtleGoldGlow = LinearGradient(
    colors: [Color(0x26E5A93C), Colors.transparent],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // Status & Operational Accents
  static const Color emerald = Color(0xFF10B981);
  static const Color emeraldTint = Color(0x2610B981);

  static const Color amber = Color(0xFFF59E0B);
  static const Color amberTint = Color(0x26F59E0B);

  static const Color crimson = Color(0xFFEF4444);
  static const Color crimsonTint = Color(0x26EF4444);

  // Typography Colors
  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xB3FFFFFF);
  static const Color textMuted = Color(0x66FFFFFF);

  // WhatsApp Accent
  static const Color whatsAppGreen = Color(0xFF25D366);
}
