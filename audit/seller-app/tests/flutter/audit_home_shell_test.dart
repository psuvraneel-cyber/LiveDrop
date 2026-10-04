// AUDIT-ONLY tests for the navigation shell in seller-app/lib/main.dart (SellerHomeScreen)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/errors/exceptions.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/main.dart';

import 'audit_fakes.dart';

final _draftDrop = SellerDrop(
  id: 'drop-1',
  sellerId: auditProfile.id,
  title: 'Saturday Live',
  slug: 'saturday-live',
  status: DropStatus.draft,
  shippingFeePaisa: 8000,
  createdAt: DateTime.utc(2026, 10, 1),
);

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 300));
  }
}

void main() {
  testWidgets('SA-AUD-T06: unapproved seller is shown the pending-approval screen (control)', (tester) async {
    const unapproved = SellerProfile(
      id: 'u1', storeName: 'New Seller', storeSlug: 'new-seller', phoneNumber: '9876500003',
      upiId: 'new@ybl', returnAddress: '9 Lake Road, Kolkata 700029', defaultShippingFeePaisa: 8000,
      advanceConfirmationEnabled: false, advanceAmountPaisa: 25000, holdDurationDays: 30, isApproved: false,
    );
    await tester.pumpWidget(auditApp(SellerHomeScreen(repository: AuditRepo(profile: unapproved, drops: [_draftDrop]))));
    await _settle(tester);
    expect(find.text('Account Under Review'), findsOneWidget);
  });

  // SA-AUTH-002 fixed: inverted. A failed profile load shows an error with Retry, never the dashboard.
  testWidgets('SA-AUD-T07: approval gate stays CLOSED when the profile request fails (offline / RLS / parse error)',
      (tester) async {
    final repo = AuditRepo(
      profileError: const LiveDropException('network down', code: 'NETWORK_ERROR'),
      drops: [_draftDrop],
    );
    await tester.pumpWidget(auditApp(SellerHomeScreen(repository: repo)));
    await _settle(tester);
    expect(find.text('Could not load your boutique'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.text('Add Product'), findsNothing); // no operational dashboard
    expect(find.text('Verify Payments'), findsNothing);
  });

  testWidgets('SA-AUD-T08 (fixed): dashboard "Shipping" never ships anything — it opens Orders on the '
      'Ready-to-ship list; no label screen, no placeholder AWB, no mark_order_shipped call', (tester) async {
    final pendingUnpaid = auditOrder(code: 'LD-PEND01');
    final readyPaid = auditOrder(
      id: 'order-2',
      code: 'LD-READY1',
      status: OrderStatus.paid,
      paymentStatus: OrderPaymentStatus.paid,
      fulfilmentStatus: OrderFulfilmentStatus.readyToShip,
      totalPaidPaisa: 158000,
    );
    final repo = AuditRepo(drops: [_draftDrop], orders: [pendingUnpaid, readyPaid]);
    await tester.pumpWidget(auditApp(SellerHomeScreen(repository: repo)));
    await _settle(tester);

    await tester.ensureVisible(find.text('Shipping'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Shipping').hitTestable().first);
    await _settle(tester);

    final readyVisible = find.text('#LD-READY1').hitTestable().evaluate().length;
    final pendingVisible = find.text('#LD-PEND01').hitTestable().evaluate().length;
    // ignore: avoid_print
    print('AUDIT T08 after Shipping tap: labelScreen=${find.text('Shipping Label').evaluate().length} '
        'readyVisible=$readyVisible pendingVisible=$pendingVisible shipCalls=${repo.shipCalls}');
    expect(find.text('Shipping Label'), findsNothing); // no label screen for an arbitrary order
    expect(find.text('DVA123456789'), findsNothing);
    expect(find.text('Generate & Share Label'), findsNothing);
    expect(find.text('Ready (1)').hitTestable(), findsOneWidget); // Orders tab, Ready pipeline
    expect(readyVisible, 1); // the ready-to-ship order is listed
    expect(pendingVisible, 0); // the unpaid pending order is not offered for shipping
    expect(repo.shipCalls, isEmpty); // nothing shipped by the shortcut
  });
}
