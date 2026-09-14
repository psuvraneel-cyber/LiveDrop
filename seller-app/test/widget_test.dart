import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/main.dart';

void main() {
  testWidgets('LiveDropSellerApp initial smoke test renders login gate', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const LiveDropSellerApp());
    await tester.pump();

    // Verify that the login screen is presented when unauthenticated
    expect(find.text('LiveDrop Seller'), findsOneWidget);
    expect(find.text('Live-Stream Commerce & UPI Verification'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2)); // Email & Password
    expect(find.text('Sign In to Boutique'), findsOneWidget);
  });

  testWidgets('LiveDropSellerApp renders controlled ConfigurationErrorScreen when initializationError is present', (WidgetTester tester) async {
    const errorMsg = '[ENV CONFIG ERROR] Missing required configuration: SUPABASE_URL';
    await tester.pumpWidget(const LiveDropSellerApp(initializationError: errorMsg));
    await tester.pump();

    // Verify that the configuration error screen is presented
    expect(find.text('Configuration Required'), findsOneWidget);
    expect(find.text(errorMsg), findsOneWidget);
    expect(find.text('Retry Connection'), findsOneWidget);
    // Verify login inputs are not rendered in error mode
    expect(find.byType(TextField), findsNothing);
  });
}

