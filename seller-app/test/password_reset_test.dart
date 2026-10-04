// SA-AUTH-001: "Forgot password?" sends a reset e-mail whose link opens the
// hosted page <BUYER_BASE_URL>/seller/reset-password.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/config/env_config.dart';
import 'package:seller_app/core/services/password_reset_service.dart';
import 'package:seller_app/presentation/auth/seller_login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _Call {
  final String email;
  final String redirectTo;
  _Call(this.email, this.redirectTo);
}

void main() {
  group('EnvConfig.sellerPasswordResetUrl', () {
    test('appends /seller/reset-password to the buyer base URL', () {
      expect(EnvConfig.sellerPasswordResetUrl('https://livedrop.in'), 'https://livedrop.in/seller/reset-password');
    });

    test('ignores trailing slashes and whitespace', () {
      expect(EnvConfig.sellerPasswordResetUrl(' https://livedrop.in/// '), 'https://livedrop.in/seller/reset-password');
    });

    test('defaults to the configured BUYER_BASE_URL', () {
      final url = EnvConfig.sellerPasswordResetUrl();
      expect(url, startsWith(EnvConfig.buyerBaseUrl.replaceAll(RegExp(r'/+$'), '')));
      expect(url, endsWith('/seller/reset-password'));
      expect(Uri.parse(url).isAbsolute, isTrue);
      expect(PasswordResetService(sender: (_, {required redirectTo}) async {}).redirectTo, url);
    });
  });

  group('PasswordResetService', () {
    test('sends the trimmed e-mail with the reset redirect', () async {
      final calls = <_Call>[];
      final service = PasswordResetService(
        sender: (email, {required redirectTo}) async => calls.add(_Call(email, redirectTo)),
        redirectTo: 'https://example.test/seller/reset-password',
      );
      await service.sendResetEmail('  seller@shop.in ');
      expect(calls.single.email, 'seller@shop.in');
      expect(calls.single.redirectTo, 'https://example.test/seller/reset-password');
    });

    test('validateEmail', () {
      expect(PasswordResetService.validateEmail(''), 'Please enter your email address first.');
      expect(PasswordResetService.validateEmail('not-an-email'), 'Please enter a valid email address.');
      expect(PasswordResetService.validateEmail('a@b.in'), isNull);
    });

    test('friendlyError maps failures to plain text', () {
      expect(PasswordResetService.friendlyError(TimeoutException('t')), contains('internet connection'));
      expect(PasswordResetService.friendlyError(const SocketException('x')), contains('internet connection'));
      expect(
        PasswordResetService.friendlyError(const AuthException('Email rate limit exceeded', statusCode: '429')),
        'Too many reset requests. Please wait a minute, then try again.',
      );
      expect(
        PasswordResetService.friendlyError(
            const AuthException('For security purposes, you can only request this after 42 seconds.')),
        contains('wait a minute'),
      );
      expect(
        PasswordResetService.friendlyError(const AuthException('Unable to validate email address: invalid format')),
        'Please enter a valid email address.',
      );
      expect(PasswordResetService.friendlyError(StateError('x')), contains('restart the app'));
      expect(PasswordResetService.friendlyError(Exception('boom')),
          'We could not send the reset email right now. Please try again in a moment.');
    });
  });

  group('SellerLoginScreen "Forgot password?"', () {
    Future<void> pumpLogin(WidgetTester tester, PasswordResetService service) async {
      await tester.pumpWidget(MaterialApp(
        home: SellerLoginScreen(onLoginSuccess: () {}, passwordResetService: service),
      ));
      await tester.pump();
    }

    testWidgets('sends the reset e-mail with redirectTo and explains what happens next', (tester) async {
      final calls = <_Call>[];
      final service = PasswordResetService(
        sender: (email, {required redirectTo}) async => calls.add(_Call(email, redirectTo)),
      );
      await pumpLogin(tester, service);

      await tester.enterText(find.byType(TextField).first, 'seller@shop.in');
      await tester.tap(find.text('Forgot password?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(calls, hasLength(1));
      expect(calls.single.email, 'seller@shop.in');
      expect(calls.single.redirectTo, EnvConfig.sellerPasswordResetUrl());
      expect(
        find.text('Check your email for a reset link. It opens a page where you set a new password.'),
        findsOneWidget,
      );
    });

    testWidgets('asks for an e-mail first and does not call the server', (tester) async {
      var called = false;
      final service = PasswordResetService(sender: (_, {required redirectTo}) async => called = true);
      await pumpLogin(tester, service);

      await tester.tap(find.text('Forgot password?'));
      await tester.pump();
      expect(called, isFalse);
      expect(find.text('Please enter your email address first.'), findsOneWidget);
    });

    testWidgets('shows friendly text when sending fails', (tester) async {
      final service = PasswordResetService(
        sender: (_, {required redirectTo}) async =>
            throw const AuthException('Email rate limit exceeded', statusCode: '429'),
      );
      await pumpLogin(tester, service);

      await tester.enterText(find.byType(TextField).first, 'seller@shop.in');
      await tester.tap(find.text('Forgot password?'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Too many reset requests. Please wait a minute, then try again.'), findsOneWidget);
    });
  });
}
