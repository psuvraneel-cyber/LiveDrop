import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/config/admin_config.dart';
import 'package:seller_app/presentation/auth/seller_login_screen.dart';
import 'package:seller_app/presentation/auth/seller_registration_screen.dart';

void main() {
  group('Seller Auth & Registration Flow Tests', () {
    testWidgets('SellerLoginScreen renders Create Account and Contact Admin WhatsApp buttons', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SellerLoginScreen(onLoginSuccess: () {}),
        ),
      );
      await tester.pump();

      // Verify header and form elements
      expect(find.text('LiveDrop Seller'), findsOneWidget);
      expect(find.text('Sign In to Boutique'), findsOneWidget);
      expect(find.text('Forgot password?'), findsOneWidget);

      // Verify New here? Create Account link
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('New here? Create Account'),
        ),
        findsOneWidget,
      );

      // Verify Contact Admin via WhatsApp button
      expect(find.text('Contact Admin via WhatsApp'), findsOneWidget);
      expect(find.byIcon(Icons.chat_outlined), findsOneWidget);
    });

    testWidgets('SellerRegistrationScreen renders Step 1 (Account Credentials)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SellerRegistrationScreen(onRegistrationSuccess: () {}),
        ),
      );
      await tester.pump();

      // Verify step indicators
      expect(find.text('Account'), findsOneWidget);
      expect(find.text('Profile'), findsOneWidget);
      expect(find.text('Payment'), findsOneWidget);

      // Verify Step 1 fields
      expect(find.text('Email Address'), findsOneWidget);
      expect(find.text('Password'), findsOneWidget);
      expect(find.text('Confirm Password'), findsOneWidget);
      expect(find.text('Next: Boutique Profile'), findsOneWidget);
    });

    testWidgets('AdminConfig contains correct contact and payment details', (tester) async {
      expect(AdminConfig.whatsAppNumber, '917439583884');
      expect(AdminConfig.onboardingUpiId, 'psuvraneel@okaxis');
      expect(AdminConfig.onboardingUpiDisplayName, 'Suvraneel Paul');
      expect(AdminConfig.onboardingFeePaisa, 5000);
      expect(AdminConfig.onboardingFeeDisplay, '₹50');
      expect(AdminConfig.whatsAppUrl, contains('917439583884'));
      expect(AdminConfig.upiPaymentUrl, contains('pa=psuvraneel@okaxis'));
      expect(AdminConfig.upiPaymentUrl, contains('am=50'));
    });
  });
}
