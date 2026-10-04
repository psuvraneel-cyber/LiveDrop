// SA-SHIP-001: nothing ships without a seller-entered tracking number and courier.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/theme/app_theme.dart';
import 'package:seller_app/core/validation/shipping_rules.dart';
import 'package:seller_app/data/repositories/seller_repository.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/orders/shipping_dialog.dart';
import 'package:seller_app/presentation/orders/shipping_label_screen.dart';

const _profile = SellerProfile(
  id: 's1',
  storeName: 'Aarohi Boutique',
  storeSlug: 'aarohi',
  phoneNumber: '9876500001',
  upiId: 'aarohi@okaxis',
  returnAddress: '12 MG Road, Kolkata 700001',
  defaultShippingFeePaisa: 8000,
  advanceConfirmationEnabled: false,
  advanceAmountPaisa: 25000,
  holdDurationDays: 30,
  isApproved: true,
);

SellerOrder _readyOrder() => SellerOrder(
      id: 'order-1',
      dropId: 'drop-1',
      orderCode: 'LD-READY1',
      buyerName: 'Riya Sen',
      buyerPhone: '9830012345',
      shippingAddress: '22 Ballygunge Place, Kolkata',
      pincode: '700019',
      subtotalPaisa: 150000,
      shippingPaisa: 8000,
      totalPaisa: 158000,
      status: OrderStatus.paid,
      confirmationMode: OrderConfirmationMode.fullPayment,
      advanceRequiredPaisa: 0,
      advancePaidPaisa: 0,
      totalPaidPaisa: 158000,
      balanceDuePaisa: 0,
      paymentStatus: OrderPaymentStatus.paid,
      fulfilmentStatus: OrderFulfilmentStatus.readyToShip,
      createdAt: DateTime.utc(2026, 10, 3, 9),
      items: const [],
    );

class _ShipRepo extends Fake implements SellerRepository {
  final List<Map<String, String>> shipCalls = [];

  @override
  Future<Map<String, dynamic>> markOrderShipped({
    required String orderId,
    required String trackingNumber,
    required String courierPartner,
    String? notes,
  }) async {
    shipCalls.add({'orderId': orderId, 'tracking': trackingNumber, 'courier': courierPartner});
    return {'success': true};
  }
}

void main() {
  group('ShippingRules', () {
    test('tracking number is required, trimmed and sanity-checked', () {
      expect(ShippingRules.validateTracking(null), isNotNull);
      expect(ShippingRules.validateTracking('   '), isNotNull);
      expect(ShippingRules.validateTracking('12345'), contains('too short'));
      expect(ShippingRules.validateTracking('A' * 41), contains('too long'));
      expect(ShippingRules.validateTracking('1234 5678'), contains('spaces'));
      expect(ShippingRules.validateTracking('AWB#123456'), isNotNull);
      expect(ShippingRules.validateTracking('-123456'), isNotNull);
      expect(ShippingRules.validateTracking('DVA123456789'), contains('real tracking number'));
      expect(ShippingRules.validateTracking(' 142129849204 '), isNull);
      expect(ShippingRules.validateTracking('EE123456789IN'), isNull);
      expect(ShippingRules.validateTracking('SR-889-1234/2'), isNull);
      expect(ShippingRules.normalizeTracking(' 142129849204 '), '142129849204');
    });

    test('courier is required', () {
      expect(ShippingRules.validateCourier(''), isNotNull);
      expect(ShippingRules.validateCourier('X'), isNotNull);
      expect(ShippingRules.validateCourier('Delhivery'), isNull);
    });
  });

  group('ShippingLabelScreen', () {
    Future<_ShipRepo> pumpScreen(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1600, 3200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final repo = _ShipRepo();
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: ShippingLabelScreen(order: _readyOrder(), profile: _profile, repository: repo),
      ));
      await tester.pumpAndSettle();
      return repo;
    }

    testWidgets('has no placeholder tracking number and no "Auto" generator', (tester) async {
      await pumpScreen(tester);
      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller!.text, isEmpty);
      expect(find.text('DVA123456789'), findsNothing);
      expect(find.text('Auto'), findsNothing);
      expect(find.text('Generate & Share Label'), findsNothing);
    });

    testWidgets('"Mark as Shipped" without courier / tracking ships nothing', (tester) async {
      final repo = await pumpScreen(tester);
      await tester.ensureVisible(find.text('Mark as Shipped'));
      await tester.tap(find.text('Mark as Shipped'));
      await tester.pumpAndSettle();
      expect(repo.shipCalls, isEmpty);
      expect(find.text('Choose or type the courier partner'), findsOneWidget);
      expect(find.text('Enter the tracking / AWB number from your courier'), findsOneWidget);
    });

    testWidgets('ships only after the seller enters a tracking number, picks a courier and confirms',
        (tester) async {
      final repo = await pumpScreen(tester);
      await tester.tap(find.text('Select courier'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('BlueDart').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  81234567890 ');

      await tester.ensureVisible(find.text('Mark as Shipped'));
      await tester.tap(find.text('Mark as Shipped'));
      await tester.pumpAndSettle();
      expect(find.text('Mark as shipped?'), findsOneWidget);
      expect(repo.shipCalls, isEmpty); // nothing before confirmation

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(repo.shipCalls, isEmpty);

      await tester.tap(find.text('Mark as Shipped'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Mark Shipped'));
      await tester.pumpAndSettle();
      expect(repo.shipCalls, [
        {'orderId': 'order-1', 'tracking': '81234567890', 'courier': 'BlueDart'},
      ]);
    });
  });

  group('ShippingDialog', () {
    testWidgets('requires a courier and a valid tracking number before dispatch', (tester) async {
      tester.view.physicalSize = const Size(1600, 3200);
      tester.view.devicePixelRatio = 2.0;
      addTearDown(tester.view.reset);
      final repo = _ShipRepo();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ShippingDialog(order: _readyOrder(), profile: _profile, repository: repo),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('Confirm Dispatch'));
      await tester.tap(find.text('Confirm Dispatch'));
      await tester.pumpAndSettle();
      expect(repo.shipCalls, isEmpty);
      expect(find.text('Choose or type the courier partner'), findsOneWidget);
      expect(find.text('Enter the tracking / AWB number from your courier'), findsOneWidget);

      await tester.tap(find.text('Blue Dart Express'));
      await tester.enterText(find.widgetWithText(TextFormField, 'Tracking / AWB Number *'), '123');
      await tester.ensureVisible(find.text('Confirm Dispatch'));
      await tester.tap(find.text('Confirm Dispatch'));
      await tester.pumpAndSettle();
      expect(repo.shipCalls, isEmpty);
      expect(find.textContaining('too short'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextFormField, 'Tracking / AWB Number *'), '81234567890');
      await tester.ensureVisible(find.text('Confirm Dispatch'));
      await tester.tap(find.text('Confirm Dispatch'));
      await tester.pumpAndSettle();
      expect(repo.shipCalls, [
        {'orderId': 'order-1', 'tracking': '81234567890', 'courier': 'Blue Dart Express'},
      ]);
    });
  });
}
