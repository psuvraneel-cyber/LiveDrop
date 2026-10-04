// SA-OBS-001 (crash reporting, visible load errors) and SA-NOT-001 (push routing, preferences).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/errors/exceptions.dart';
import 'package:seller_app/core/services/app_log.dart';
import 'package:seller_app/core/services/push_service.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/products/products_inventory_screen.dart';
import 'package:seller_app/presentation/settings/seller_settings_screen.dart';

import 'support/p0_fakes.dart';

class _Repo extends P0FakeRepo {
  _Repo({this.dropsError});

  final Object? dropsError;
  bool newOrders = true;
  bool paymentClaims = true;
  final List<Map<String, bool?>> prefCalls = [];

  @override
  Future<List<SellerDrop>> getDrops() async {
    final e = dropsError;
    if (e != null) throw e;
    return super.getDrops();
  }

  @override
  Future<SellerProfile> getProfile() async => SellerProfile(
        id: testProfile.id,
        storeName: testProfile.storeName,
        storeSlug: testProfile.storeSlug,
        phoneNumber: testProfile.phoneNumber,
        upiId: testProfile.upiId,
        returnAddress: testProfile.returnAddress,
        defaultShippingFeePaisa: testProfile.defaultShippingFeePaisa,
        advanceConfirmationEnabled: false,
        advanceAmountPaisa: 25000,
        holdDurationDays: 30,
        isApproved: true,
        notifyNewOrders: newOrders,
        notifyPaymentClaims: paymentClaims,
      );

  @override
  Future<void> setNotificationPrefs({bool? newOrders, bool? paymentClaims}) async {
    prefCalls.add({'newOrders': newOrders, 'paymentClaims': paymentClaims});
    if (newOrders != null) this.newOrders = newOrders;
    if (paymentClaims != null) this.paymentClaims = paymentClaims;
  }
}

void main() {
  group('PushRoute (SA-NOT-001)', () {
    test('payment claims open Payments, new orders open Orders, anything else stays put', () {
      expect(PushRoute.tabFor({'type': 'payment_claim', 'order_id': 'o1'}), PushRoute.paymentsTab);
      expect(PushRoute.tabFor({'kind': 'late_claim'}), PushRoute.paymentsTab);
      expect(PushRoute.tabFor({'type': 'new_order'}), PushRoute.ordersTab);
      expect(PushRoute.tabFor({'type': 'something_else'}), isNull);
      expect(PushRoute.tabFor(const {}), isNull);
    });

    test('without Firebase the push service does nothing and never throws', () async {
      expect(AppLog.crashlyticsReady, isFalse);
      var registered = false;
      await PushService.instance.start(
        register: (_) async => registered = true,
        unregister: (_) async {},
        onOpen: (_) {},
      );
      expect(PushService.instance.isStarted, isFalse);
      expect(registered, isFalse);
      await PushService.instance.stop();
    });
  });

  test('AppLog.error never throws without Firebase (SA-OBS-001)', () {
    expect(() => AppLog.error('test', StateError('boom'), StackTrace.current), returnsNormally);
    expect(() => AppLog.setSeller('seller-1'), returnsNormally);
  });

  test('profile reads the push preferences, defaulting to on', () {
    final base = {
      'id': 's1', 'store_name': 'A', 'store_slug': 'a', 'phone_number': '9876500001', 'upi_id': 'a@okaxis',
      'return_address': '12 MG Road', 'default_shipping_fee_paisa': 8000, 'advance_confirmation_enabled': false,
      'advance_amount_paisa': 25000, 'hold_duration_days': 30, 'is_approved': true,
    };
    final defaults = SellerProfile.fromJson(base);
    expect(defaults.notifyNewOrders, isTrue);
    expect(defaults.notifyPaymentClaims, isTrue);
    final off = SellerProfile.fromJson({...base, 'notify_new_orders': false});
    expect(off.notifyNewOrders, isFalse);
  });

  testWidgets('Products shows a retry banner instead of an empty list when loading fails (SA-OBS-001)', (tester) async {
    final repo = _Repo(dropsError: const LiveDropException('down', code: 'NETWORK_ERROR'));
    await tester.pumpWidget(testApp(ProductsInventoryScreen(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('load-error-banner')), findsOneWidget);
    expect(find.textContaining('No connection'), findsOneWidget);
  });

  testWidgets('Settings > Notifications switches are saved to the account (SA-NOT-001)', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final repo = _Repo();
    await tester.pumpWidget(testApp(SellerSettingsScreen(repository: repo)));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Notifications'));
    await tester.tap(find.text('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('New orders'), findsOneWidget);
    expect(find.text('Payments to check'), findsOneWidget);

    await tester.tap(find.widgetWithText(SwitchListTile, 'New orders'));
    await tester.pumpAndSettle();
    expect(repo.prefCalls, [
      {'newOrders': false, 'paymentClaims': null},
    ]);
    final tile = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'New orders'));
    expect(tile.value, isFalse);
  });
}
