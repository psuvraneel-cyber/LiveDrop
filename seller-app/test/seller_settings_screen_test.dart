import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/settings/seller_settings_screen.dart';

class FakeSettingsSellerRepository extends Fake implements SellerRepository {
  final SellerProfile profile;

  FakeSettingsSellerRepository({required this.profile});

  @override
  Future<SellerProfile> getProfile() async => profile;

  @override
  Future<List<SellerDrop>> getDrops() async => [];

  @override
  Future<List<SellerProduct>> getProducts(String dropId) async => [];

  @override
  Future<List<SellerOrder>> getAllOrders({String? dropId, String? status}) async => [];

  @override
  Future<List<PaymentAttempt>> getPendingVerifications() async => [];

  @override
  Future<List<SellerActivityItem>> getRecentActivity({String? dropId, int limit = 5}) async => [];

  @override
  Future<SellerAnalytics> getSellerAnalytics({String? range}) async => const SellerAnalytics(
        totalRevenuePaisa: 0,
        itemsSoldCount: 0,
        activeHoldsCount: 0,
        paymentClaimsCount: 0,
        peakRevenuePaisa: 0,
        dailySales: [],
        topProducts: [],
      );
}

void main() {
  testWidgets('SellerSettingsScreen opens Storefront Settings and displays canonical Vercel URL',
      (WidgetTester tester) async {
    const mockProfile = SellerProfile(
      id: 'seller-suv',
      storeName: "Suv's Boutique",
      storeSlug: 'suv-s',
      phoneNumber: '9830123456',
      upiId: 'suv@okaxis',
      returnAddress: 'Kolkata Studio, West Bengal',
      defaultShippingFeePaisa: 8000,
      advanceConfirmationEnabled: true,
      advanceAmountPaisa: 25000,
      holdDurationDays: 7,
    );

    final repo = FakeSettingsSellerRepository(profile: mockProfile);

    await tester.pumpWidget(
      MaterialApp(
        home: SellerSettingsScreen(repository: repo),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Settings screen loads boutique header
    expect(find.text("Suv's Boutique"), findsOneWidget);
    expect(find.text('Storefront Settings'), findsOneWidget);

    // Tap Storefront Settings tile to open modal sheet
    await tester.tap(find.text('Storefront Settings'));
    await tester.pumpAndSettle();

    // Verify modal header is visible
    expect(find.text('Public Store Link'), findsOneWidget);

    // Verify canonical Vercel production URL is displayed
    expect(find.text('https://livedrop-in.vercel.app/suv-s'), findsOneWidget);

    // CRITICAL: Ensure erroneous domain is NOT present anywhere
    expect(find.textContaining('livedrop.shop'), findsNothing);

    // Verify action buttons exist: Copy Link, WhatsApp, Open in Browser
    expect(find.text('Copy Link'), findsOneWidget);
    expect(find.text('WhatsApp'), findsOneWidget);
    expect(find.byTooltip('Open in Browser'), findsOneWidget);

    // Tap "Copy Link" and verify clipboard feedback
    await tester.tap(find.text('Copy Link'));
    await tester.pump();
    expect(find.text('Store link copied to clipboard'), findsOneWidget);
  });
}
