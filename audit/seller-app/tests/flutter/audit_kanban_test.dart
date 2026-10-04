// AUDIT-ONLY tests for KanbanBoardScreen / OrderCard (seller-app/lib/presentation/orders/)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/orders/kanban_board_screen.dart';
import 'package:seller_app/presentation/orders/order_card.dart';
import 'package:seller_app/presentation/pending_verifications_screen.dart';

import 'audit_fakes.dart';

void main() {
  testWidgets('SA-AUD-T20 (fixed): a verified late payment that needs a refund is listed under '
      'Payments → Refunds owed, and cancelled/expired orders are under the Kanban "Closed" tab (SA-ORD-004)',
      (tester) async {
    final refundOwed = auditOrder(
      id: 'o-refund', code: 'LD-REFUND', status: OrderStatus.cancelled,
      paymentStatus: OrderPaymentStatus.paid, totalPaidPaisa: 158000,
    );
    final expiredAdvance = auditOrder(id: 'o-exp', code: 'LD-EXPIRD', status: OrderStatus.expired);
    final repo = AuditRepo(orders: [refundOwed, expiredAdvance], refunds: [auditRefund()]);

    // SA-ORD-004 (fixed): cancelled/expired orders have their own tab, not mixed into Paid.
    await tester.pumpWidget(auditApp(KanbanBoardScreen(repository: repo)));
    await tester.pumpAndSettle();
    for (final tab in ['Pending (0)', 'Paid (0)', 'Ready (0)', 'Shipped (0)', 'Closed (2)']) {
      expect(find.text(tab), findsOneWidget);
    }

    // Fixed part (SA-PAY-004): the refund obligation is visible and actionable in Payments.
    await tester.pumpWidget(auditApp(Scaffold(body: PendingVerificationsScreen(repository: repo))));
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('AUDIT T20 refunds section=${find.text('Refunds owed (1)').evaluate().length} '
        'order=${find.text('#LD-REFUND').evaluate().length} amount=${find.text('₹1580 to refund').evaluate().length}');
    expect(find.text('Refunds owed (1)'), findsOneWidget);
    expect(find.text('#LD-REFUND'), findsOneWidget);
    expect(find.text('₹1580 to refund'), findsOneWidget);
    expect(find.text('Mark refunded'), findsOneWidget);
  });

  // SA-ORD-005 / SA-SHIP-002 fixed: inverted. An advance-paid order offers "Ask for balance", no Dispatch, no label.
  testWidgets('SA-AUD-T21: advance-paid (confirmed) orders show no Dispatch and no label, only "Ask for balance"',
      (tester) async {
    final advancePaid = SellerOrder(
      id: 'o-adv', dropId: 'drop-1', orderCode: 'LD-ADV001', buyerName: 'Meera Pal', buyerPhone: '9830044444',
      shippingAddress: '3 Gariahat Road, Kolkata', pincode: '700029', subtotalPaisa: 250000, shippingPaisa: 0,
      totalPaisa: 250000, status: OrderStatus.confirmed, confirmationMode: OrderConfirmationMode.advance,
      advanceRequiredPaisa: 25000, advancePaidPaisa: 25000, totalPaidPaisa: 25000, balanceDuePaisa: 225000,
      paymentStatus: OrderPaymentStatus.advancePaid, fulfilmentStatus: OrderFulfilmentStatus.notReady,
      createdAt: DateTime.utc(2026, 10, 3, 9), items: const [],
    );
    await tester.pumpWidget(auditApp(Scaffold(body: SingleChildScrollView(child: OrderCard(
      order: advancePaid, profile: auditProfile, repository: AuditRepo(orders: [advancePaid]), onOrderUpdated: () {},
    )))));
    await tester.pump();
    expect(find.text('Advance Paid'), findsOneWidget);
    expect(find.text('Dispatch'), findsNothing);
    expect(find.text('4×6 Label'), findsNothing);
    expect(find.text('Ask for balance'), findsOneWidget);
  });
}
