import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

/// Crash and error reporting for the seller app (SA-OBS-001).
///
/// Errors go to the debug console and, when Firebase is set up
/// (`android/app/google-services.json`), to Firebase Crashlytics. Without
/// Firebase the app still runs: [init] returns false and [error] only logs.
class AppLog {
  AppLog._();

  static bool _crashlyticsReady = false;

  /// True once Crashlytics is receiving reports.
  static bool get crashlyticsReady => _crashlyticsReady;

  /// Starts Firebase and routes uncaught Flutter and platform errors to
  /// Crashlytics. Safe to call when Firebase is not configured.
  static Future<bool> init() async {
    try {
      await Firebase.initializeApp();
      final crashlytics = FirebaseCrashlytics.instance;
      // Debug builds never report, so developers' crashes do not mix with sellers'.
      await crashlytics.setCrashlyticsCollectionEnabled(!kDebugMode);
      FlutterError.onError = crashlytics.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        crashlytics.recordError(error, stack, fatal: true);
        return true;
      };
      _crashlyticsReady = true;
    } catch (e) {
      debugPrint('[AppLog] Firebase not available, crash reporting off: $e');
      _crashlyticsReady = false;
    }
    return _crashlyticsReady;
  }

  /// Records a handled error: where it happened, what it was. Never throws.
  static void error(String where, Object error, [StackTrace? stack]) {
    debugPrint('[$where] $error');
    if (!_crashlyticsReady) return;
    try {
      unawaited(FirebaseCrashlytics.instance.recordError(error, stack, reason: where, fatal: false));
    } catch (e) {
      debugPrint('[AppLog] could not report: $e');
    }
  }

  /// Ties reports to the signed-in seller (their account id, no personal data).
  static void setSeller(String? sellerId) {
    if (!_crashlyticsReady) return;
    try {
      unawaited(FirebaseCrashlytics.instance.setUserIdentifier(sellerId ?? ''));
    } catch (e) {
      debugPrint('[AppLog] could not set seller: $e');
    }
  }
}
