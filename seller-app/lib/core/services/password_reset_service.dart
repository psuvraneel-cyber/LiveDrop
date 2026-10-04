import 'dart:async';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/env_config.dart';
import 'supabase_service.dart';

/// Sends the password-reset e-mail. Injected in tests.
typedef PasswordResetSender = Future<void> Function(String email, {required String redirectTo});

/// LiveDrop Seller — "Forgot password?" flow (SA-AUTH-001).
///
/// The e-mailed link opens the hosted page `<BUYER_BASE_URL>/seller/reset-password`
/// on the LiveDrop website, where the seller chooses a new password. The app
/// itself only requests the e-mail.
class PasswordResetService {
  PasswordResetService({PasswordResetSender? sender, String? redirectTo})
      : _sender = sender ?? _supabaseSender,
        redirectTo = redirectTo ?? EnvConfig.sellerPasswordResetUrl();

  final PasswordResetSender _sender;

  /// Where the reset link sends the seller.
  final String redirectTo;

  /// Shown after the e-mail was requested.
  static const String sentMessage =
      'Check your email for a reset link. It opens a page where you set a new password.';

  static final RegExp _emailPattern = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$');

  static Future<void> _supabaseSender(String email, {required String redirectTo}) {
    if (!SupabaseService.instance.isInitialized) {
      throw StateError('Supabase client is not initialized');
    }
    return SupabaseService.instance.client.auth.resetPasswordForEmail(
      email,
      redirectTo: redirectTo,
    );
  }

  /// Returns a seller-facing problem with [email], or null when it looks valid.
  static String? validateEmail(String email) {
    final trimmed = email.trim();
    if (trimmed.isEmpty) return 'Please enter your email address first.';
    if (!_emailPattern.hasMatch(trimmed)) return 'Please enter a valid email address.';
    return null;
  }

  /// Requests the reset e-mail. Throws on failure; use [friendlyError] for the
  /// text to show.
  Future<void> sendResetEmail(String email) {
    return _sender(email.trim(), redirectTo: redirectTo).timeout(const Duration(seconds: 15));
  }

  /// Maps a failure from [sendResetEmail] to plain, actionable text.
  static String friendlyError(Object error) {
    if (error is TimeoutException || error is SocketException) {
      return 'We could not reach the server. Check your internet connection and try again.';
    }
    if (error is StateError) {
      return 'The app is not connected to LiveDrop right now. Please restart the app and try again.';
    }
    if (error is AuthException) {
      final msg = error.message.toLowerCase();
      final status = error.statusCode;
      if (status == '429' ||
          msg.contains('rate limit') ||
          msg.contains('too many') ||
          msg.contains('security purposes')) {
        return 'Too many reset requests. Please wait a minute, then try again.';
      }
      if (msg.contains('invalid') && msg.contains('email')) {
        return 'Please enter a valid email address.';
      }
      if (msg.contains('redirect')) {
        return 'Password reset is not available right now. Please contact LiveDrop support.';
      }
    }
    final text = error.toString().toLowerCase();
    if (text.contains('socket') || text.contains('network') || text.contains('failed host lookup')) {
      return 'We could not reach the server. Check your internet connection and try again.';
    }
    return 'We could not send the reset email right now. Please try again in a moment.';
  }
}
