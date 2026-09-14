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
}
