import 'package:flutter/services.dart';

/// LiveDrop Seller Mobile App — Boutique Luxury Haptic Engine
///
/// Delivers nuanced, tactile physical confirmations for luxury interactions:
/// - Light impact for button presses, tab navigations, and pill selections
/// - Selection click for toggles, switches, and sliders
/// - Medium impact for camera shutter intake and card flips
/// - Heavy / Success impact for order fulfillment dispatch and payment verification
class BoutiqueHaptics {
  BoutiqueHaptics._();

  /// Subtle touch feedback for buttons and tabs
  static void light() {
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Click feedback for checkboxes, switches, and radio toggles
  static void selection() {
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Physical confirmation for camera shutter and drag releases
  static void medium() {
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Authoritative impact for destructive actions (rejection, delete)
  static void heavy() {
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Celebratory vibration pattern for verification approval, order dispatch, and sign-in
  static Future<void> success() async {
    try {
      await HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }
}
