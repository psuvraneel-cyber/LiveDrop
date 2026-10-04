import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// LiveDrop Seller Mobile App — Boutique Luxury Haptic Engine
///
/// Delivers nuanced, tactile physical confirmations for luxury interactions:
/// - Light impact for button presses, tab navigations, and pill selections
/// - Selection click for toggles, switches, and sliders
/// - Medium impact for camera shutter intake and card flips
/// - Heavy / Success impact for order fulfillment dispatch and payment verification
class BoutiqueHaptics {
  BoutiqueHaptics._();

  /// Seller preference (Settings > App Preferences). When false no haptic is
  /// played (SA-UX-002: the switch used to change nothing).
  static bool enabled = true;

  static const String _prefFile = 'haptics_disabled';

  /// Loads the saved preference; a missing or unreadable file means "on".
  static Future<void> loadPreference() async {
    try {
      final dir = await getApplicationSupportDirectory();
      enabled = !File('${dir.path}/$_prefFile').existsSync();
    } catch (e) {
      debugPrint('[BoutiqueHaptics] preference not loaded: $e');
    }
  }

  /// Turns haptics on or off and remembers the choice on this phone.
  static Future<void> setEnabled(bool value) async {
    enabled = value;
    try {
      final dir = await getApplicationSupportDirectory();
      final file = File('${dir.path}/$_prefFile');
      if (value) {
        if (file.existsSync()) await file.delete();
      } else {
        await file.writeAsString('1');
      }
    } catch (e) {
      debugPrint('[BoutiqueHaptics] preference not saved: $e');
    }
  }

  /// Subtle touch feedback for buttons and tabs
  static void light() {
    if (!enabled) return;
    try {
      HapticFeedback.lightImpact();
    } catch (_) {}
  }

  /// Click feedback for checkboxes, switches, and radio toggles
  static void selection() {
    if (!enabled) return;
    try {
      HapticFeedback.selectionClick();
    } catch (_) {}
  }

  /// Physical confirmation for camera shutter and drag releases
  static void medium() {
    if (!enabled) return;
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
  }

  /// Authoritative impact for destructive actions (rejection, delete)
  static void heavy() {
    if (!enabled) return;
    try {
      HapticFeedback.heavyImpact();
    } catch (_) {}
  }

  /// Celebratory vibration pattern for verification approval, order dispatch, and sign-in
  static Future<void> success() async {
    if (!enabled) return;
    try {
      await HapticFeedback.mediumImpact();
      await Future<void>.delayed(const Duration(milliseconds: 70));
      await HapticFeedback.lightImpact();
    } catch (_) {}
  }
}
