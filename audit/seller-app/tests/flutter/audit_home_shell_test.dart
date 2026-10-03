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

  testWidgets('SA-AUD-T07: approval gate fails OPEN when the profile request fails (offline / RLS / parse error)',
      (tester) async {
    final repo = AuditRepo(
      profileError: const LiveDropException('network down', code: 'NETWORK_ERROR'),
      drops: [_draftDrop],
    );
    await tester.pumpWidget(auditApp(SellerHomeScreen(repository: repo)));
    await _settle(tester);
    expect(find.text('Account Under Review'), findsNothing);
    expect(find.text('Add Product'), findsOneWidget); // full operational dashboard rendered
    expect(find.text('Verify Payments'), findsWidgets);
  });

  testWidgets('SA-AUD-T08: dashboard "Shipping" opens the label for whatever order is first and ships it with placeholder AWB',
      (tester) async {
    final pendingUnpaid = auditOrder(code: 'LD-PEND01');
    final repo = AuditRepo(drops: [_draftDrop], orders: [pendingUnpaid]);
    await tester.pumpWidget(auditApp(SellerHomeScreen(repository: repo)));
    await _settle(tester);

    final shippingTile = find.text('Shipping').hitTestable();
    // ignore: avoid_print
    print('AUDIT T08 Shipping finders: all=${find.text('Shipping').evaluate().length} hittable=${shippingTile.evaluate().length}');
    await tester.ensureVisible(find.text('Shipping'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Shipping').hitTestable().first);
    await _settle(tester);
    expect(find.text('Shipping Label'), findsOneWidget);
    expect(find.text('Order #LD-PEND01'), findsOneWidget); // an unpaid, pending order
    expect(find.text('PREPAID'), findsOneWidget);

    await tester.ensureVisible(find.text('Generate & Share Label'));
    await tester.tap(find.text('Generate & Share Label'));
    await _settle(tester);
    // ignore: avoid_print
    print('AUDIT T08 markOrderShipped calls: ${repo.shipCalls}');
    expect(repo.shipCalls, hasLength(1));
    expect(repo.shipCalls.first['orderId'], pendingUnpaid.id);
    expect(repo.shipCalls.first['tracking'], 'DVA123456789');
  });
}
