import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/theme/app_theme.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/analytics/seller_analytics_screen.dart';
import 'package:seller_app/presentation/dashboard/seller_dashboard_screen.dart';
import 'package:seller_app/presentation/products/product_details_screen.dart';

class TestSellerRepository extends Fake implements SellerRepository {
  final SellerProfile? profile;
  final List<SellerDrop> drops;
  final List<SellerProduct> products;
  final List<SellerOrder> orders;
  final List<PaymentAttempt> pendingVerifications;
  final List<SellerActivityItem> activities;
  final SellerAnalytics? analytics;

  TestSellerRepository({
    this.profile,
    this.drops = const [],
    this.products = const [],
    this.orders = const [],
    this.pendingVerifications = const [],
    this.activities = const [],
    this.analytics,
  });

  @override
  Future<SellerProfile> getProfile() async {
    return profile ??
        const SellerProfile(
          id: 'seller-1',
          storeName: 'Anita Silks',
          storeSlug: 'anita-silks',
          phoneNumber: '+91 98765 00000',
          upiId: 'anitasilks@upi',
          returnAddress: '10 Silk Street, Bangalore',
          defaultShippingFeePaisa: 8000,
          advanceConfirmationEnabled: false,
          advanceAmountPaisa: 25000,
          holdDurationDays: 30,
        );
  }

  @override
  Future<List<SellerDrop>> getDrops() async => drops;

  @override
  Future<List<SellerProduct>> getProducts(String dropId) async => products;

  @override
  Future<List<SellerOrder>> getAllOrders({String? dropId, String? status}) async => orders;

  @override
  Future<List<PaymentAttempt>> getPendingVerifications() async => pendingVerifications;

  @override
  Future<List<SellerActivityItem>> getRecentActivity({String? dropId, int limit = 5}) async => activities;

  @override
  Future<SellerAnalytics> getSellerAnalytics({String? range}) async {
    return analytics ??
        const SellerAnalytics(
          totalRevenuePaisa: 0,
          itemsSoldCount: 0,
          activeHoldsCount: 0,
          paymentClaimsCount: 0,
          peakRevenuePaisa: 0,
          dailySales: [],
          topProducts: [],
        );
  }
}

void main() {
  group('LiveDrop Seller UI Verification & Real Data Tests', () {
    testWidgets('Dashboard renders authentic zeros (0, 0, 0, ₹0) when drop is empty', (tester) async {
      final repo = TestSellerRepository(
        drops: [
          SellerDrop(
            id: 'drop-1',
            sellerId: 'seller-1',
            title: 'Empty Launch Drop',
            slug: 'empty-launch-drop',
            status: DropStatus.draft,
            shippingFeePaisa: 8000,
            createdAt: DateTime.now(),
          ),
        ],
        products: [],
        orders: [],
        activities: [],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SellerDashboardScreen(
            repository: repo,
            onNavigateToAddProduct: () {},
            onNavigateToOrders: () {},
            onNavigateToPayments: () {},
            onNavigateToAnalytics: () {},
            onNavigateToShipping: () {},
            onManageDrop: () {},
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // Authentic Zeros must be rendered
      expect(find.text('0'), findsNWidgets(3)); // Items, On Hold, Sold
      expect(find.text('₹0'), findsOneWidget); // Revenue

      // Must NOT show fake hardcoded 42, 7, 19, or ₹38,450
      expect(find.text('42'), findsNothing);
      expect(find.text('19'), findsNothing);
      expect(find.text('₹38,450'), findsNothing);

      // Status badge must be DRAFT, not LIVE
      expect(find.text('DRAFT'), findsOneWidget);
      expect(find.text('LIVE'), findsNothing);

      // Subtitle must reflect Draft status
      expect(find.text('Draft — not visible to buyers'), findsOneWidget);

      // Empty activity state
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('No activity in this drop yet'), findsOneWidget);
    });

    testWidgets('Dashboard renders real activity items when present', (tester) async {
      final repo = TestSellerRepository(
        drops: [
          SellerDrop(
            id: 'drop-1',
            sellerId: 'seller-1',
            title: 'Live Festive Drop',
            slug: 'live-festive-drop',
            status: DropStatus.live,
            shippingFeePaisa: 8000,
            createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
            liveStartedAt: DateTime.now().subtract(const Duration(minutes: 10)),
          ),
        ],
        activities: [
          SellerActivityItem(
            id: 'act-1',
            title: 'New payment claim #ORD-777',
            subtitle: '₹2,500 claimed via UPI',
            timestamp: DateTime.now().subtract(const Duration(minutes: 2)),
            type: 'payment_claim',
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SellerDashboardScreen(
            repository: repo,
            onNavigateToAddProduct: () {},
            onNavigateToOrders: () {},
            onNavigateToPayments: () {},
            onNavigateToAnalytics: () {},
            onNavigateToShipping: () {},
            onManageDrop: () {},
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('Started 10 min ago'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('New payment claim #ORD-777'), findsOneWidget);
      expect(find.text('No activity in this drop yet'), findsNothing);
    });

    testWidgets('SellerAnalyticsScreen displays real calculated metrics, peak tag, and top products', (tester) async {
      final repo = TestSellerRepository(
        analytics: SellerAnalytics(
          totalRevenuePaisa: 4500000, // ₹45,000
          itemsSoldCount: 15,
          activeHoldsCount: 3,
          paymentClaimsCount: 2,
          peakRevenuePaisa: 1200000, // ₹12,000
          dailySales: [
            DailySalesStat(date: DateTime.utc(2026, 9, 15), dayLabel: 'Mon', totalPaisa: 500000),
            DailySalesStat(date: DateTime.utc(2026, 9, 16), dayLabel: 'Tue', totalPaisa: 1200000),
            DailySalesStat(date: DateTime.utc(2026, 9, 17), dayLabel: 'Wed', totalPaisa: 800000),
            DailySalesStat(date: DateTime.utc(2026, 9, 18), dayLabel: 'Thu', totalPaisa: 300000),
            DailySalesStat(date: DateTime.utc(2026, 9, 19), dayLabel: 'Fri', totalPaisa: 700000),
            DailySalesStat(date: DateTime.utc(2026, 9, 20), dayLabel: 'Sat', totalPaisa: 600000),
            DailySalesStat(date: DateTime.utc(2026, 9, 21), dayLabel: 'Sun', totalPaisa: 400000),
          ],
          topProducts: const [
            TopProductStat(
              productCode: 'B12',
              title: 'Kalamkari Silk Dupatta',
              soldCount: 8,
              revenuePaisa: 2400000,
            ),
          ],
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: SellerAnalyticsScreen(repository: repo),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));

      // 4 KPI Cards
      expect(find.text('₹45,000'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      // Peak chip
      expect(find.text('₹12,000 Peak'), findsOneWidget);

      // Top Product Item
      expect(find.text('#B12 Kalamkari Silk Dupatta'), findsOneWidget);
      expect(find.text('8 sold'), findsOneWidget);
      expect(find.text('₹24,000'), findsOneWidget);
    });

    testWidgets('ProductDetailsScreen renders authentic garment attributes and no mock Banarasi copy', (tester) async {
      final repo = TestSellerRepository();
      const product = SellerProduct(
        id: 'p-100',
        dropId: 'd-1',
        code: 'K09',
        title: 'Chanderi Zari Kurti',
        pricePaisa: 195000,
        size: 'L',
        imageUrl: 'https://images.unsplash.com/photo-1583391733956-3750e0ff4e8b',
        status: ProductStatus.available,
        version: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: ProductDetailsScreen(
            product: product,
            repository: repo,
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Real garment info
      expect(find.text('#K09 Chanderi Zari Kurti'), findsOneWidget);
      expect(find.text('₹1950'), findsNWidgets(2)); // Hero + Attribute
      expect(find.text('Apparel / Size L'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);

      // Authentic description
      expect(
        find.text('Chanderi Zari Kurti (Piece K09). Authentic boutique garment. Listed at ₹1950.'),
        findsOneWidget,
      );

      // Mock Banarasi text must NOT be present
      expect(find.textContaining('Pure Banarasi silk with traditional zari weave'), findsNothing);
    });
  });
}
