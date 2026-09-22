import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/theme/app_colors.dart';
import 'package:seller_app/core/theme/app_theme.dart';
import 'package:seller_app/core/theme/brand_emblem.dart';
import 'package:seller_app/core/theme/bounceable_button.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/common/skeleton_loaders.dart';
import 'package:seller_app/presentation/dashboard/seller_dashboard_screen.dart';
import 'package:seller_app/presentation/splash/animated_splash_screen.dart';

class MockSellerRepository extends Fake implements SellerRepository {
  @override
  Future<SellerProfile> getProfile() async {
    return const SellerProfile(
      id: 'mock-seller-1',
      storeName: 'Priya Boutique',
      storeSlug: 'priya-boutique',
      phoneNumber: '+91 98765 43210',
      upiId: 'priyaboutique@okhdfcbank',
      returnAddress: '12 MG Road, Bangalore',
      defaultShippingFeePaisa: 8000,
      advanceConfirmationEnabled: true,
      advanceAmountPaisa: 200000,
      holdDurationDays: 30,
    );
  }

  @override
  Future<List<SellerDrop>> getDrops() async {
    return [
      SellerDrop(
        id: 'mock-drop-1',
        sellerId: 'mock-seller-1',
        title: 'Diwali Festive Drop',
        slug: 'diwali-festive-drop',
        status: DropStatus.live,
        shippingFeePaisa: 8000,
        createdAt: DateTime.now().subtract(const Duration(minutes: 32)),
        liveStartedAt: DateTime.now().subtract(const Duration(minutes: 32)),
      ),
    ];
  }

  @override
  Future<List<SellerProduct>> getProducts(String dropId) async {
    return [
      const SellerProduct(
        id: 'prod-1',
        dropId: 'mock-drop-1',
        code: 'A21',
        title: 'Banarasi Silk Saree',
        pricePaisa: 185000,
        size: 'Free Size',
        imageUrl: '',
        status: ProductStatus.available,
        version: 1,
      ),
      const SellerProduct(
        id: 'prod-2',
        dropId: 'mock-drop-1',
        code: 'A22',
        title: 'Kanchipuram Saree',
        pricePaisa: 225000,
        size: 'Free Size',
        imageUrl: '',
        status: ProductStatus.reserved,
        version: 1,
      ),
      const SellerProduct(
        id: 'prod-3',
        dropId: 'mock-drop-1',
        code: 'A23',
        title: 'Chikankari Kurti',
        pricePaisa: 145000,
        size: 'M',
        imageUrl: '',
        status: ProductStatus.sold,
        version: 1,
      ),
    ];
  }

  @override
  Future<List<PaymentAttempt>> getPendingVerifications() async {
    return [];
  }

  @override
  Future<List<SellerOrder>> getAllOrders({String? dropId, String? status}) async {
    return [];
  }

  @override
  Future<List<SellerActivityItem>> getRecentActivity({String? dropId, int limit = 5}) async {
    return [];
  }

  @override
  Future<SellerAnalytics> getSellerAnalytics({String? range}) async {
    return const SellerAnalytics(
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
  group('LUXURY BOUTIQUE NOIR DESIGN SYSTEM & MOTION TESTS', () {
    test('AppColors token invariants adhere to Luxury Boutique Noir palette', () {
      expect(AppColors.obsidian, const Color(0xFF0C0C0E));
      expect(AppColors.obsidianSurface, const Color(0xFF17171C));
      expect(AppColors.goldPrimary, const Color(0xFFE5A93C));
      expect(AppColors.goldSecondary, const Color(0xFFC88A24));
      expect(AppColors.emerald, const Color(0xFF10B981));
      expect(AppColors.amber, const Color(0xFFF59E0B));
      expect(AppColors.crimson, const Color(0xFFEF4444));
    });

    testWidgets('BrandEmblem renders procedural coat hanger monogram and brand text', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: BrandEmblem(
              size: 80,
              showText: true,
              subtitle: 'Small Boutiques, Big Stories',
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CustomPaint), findsWidgets);
      expect(find.text('LiveDrop Seller'), findsOneWidget);
      expect(find.text('Small Boutiques, Big Stories'), findsOneWidget);
    });

    testWidgets('BounceableButton handles spring scale and loading spinner states', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BounceableButton(
              onPressed: () => tapped = true,
              text: 'Sign In to Boutique',
              variant: ButtonVariant.goldGradient,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Sign In to Boutique'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.text('Sign In to Boutique'));
      await tester.pump();
      expect(tapped, isTrue);

      // Now test loading state
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: BounceableButton(
              onPressed: () {},
              text: 'Saving...',
              isLoading: true,
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('Skeleton Loaders render structured placeholder geometries', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: DropsListSkeleton(),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(DropsListSkeleton), findsOneWidget);
    });

    testWidgets('AnimatedSplashScreen renders brand monogram and launches countdown', (tester) async {
      bool navigated = false;

      await tester.pumpWidget(
        MaterialApp(
          home: AnimatedSplashScreen(
            minDuration: const Duration(milliseconds: 200),
            onNavigationTarget: (isAuth) {
              navigated = true;
              return const Scaffold(body: Text('Destination Screen'));
            },
          ),
        ),
      );

      // Initial frame: branding must be present
      await tester.pump();
      expect(find.text('LiveDrop'), findsOneWidget);
      expect(find.text('SELLER'), findsOneWidget);
      expect(find.text('Small Boutiques, Big Stories'), findsOneWidget);

      // Advance clock past minDuration
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(navigated, isTrue);
      expect(find.text('Destination Screen'), findsOneWidget);
    });

    testWidgets('SellerDashboardScreen renders Live Drop Card, 4 Metrics, and 6 Quick Actions', (tester) async {
      final repo = MockSellerRepository();

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

      // Initial pump for loading
      await tester.pump();
      // Pump past future resolution
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 500));

      // Greeting & Profile
      expect(find.text('Good morning'), findsOneWidget);
      expect(find.text('Priya Boutique 👋'), findsOneWidget);

      // Active Drop Hero Card
      expect(find.text('Diwali Festive Drop'), findsOneWidget);
      expect(find.text('LIVE'), findsOneWidget);
      expect(find.text('View on Web'), findsOneWidget);

      // 4 Metrics
      expect(find.text('Items'), findsOneWidget);
      expect(find.text('On Hold'), findsOneWidget);
      expect(find.text('Sold'), findsOneWidget);
      expect(find.text('Revenue'), findsOneWidget);

      // 6 Quick Actions Grid
      expect(find.text('Add Product'), findsOneWidget);
      expect(find.text('View Orders'), findsOneWidget);
      expect(find.text('Verify Payments'), findsOneWidget);
      expect(find.text('Manage Drop'), findsOneWidget);
      expect(find.text('Analytics'), findsOneWidget);
      // Recent Activity (scroll to view on smaller viewports)
      await tester.drag(find.byType(ListView), const Offset(0, -300));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Recent Activity'), findsOneWidget);
    });
  });
}
