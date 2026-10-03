// AUDIT-ONLY tests for KanbanBoardScreen / OrderCard (seller-app/lib/presentation/orders/)
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/orders/kanban_board_screen.dart';
import 'package:seller_app/presentation/orders/order_card.dart';

import 'audit_fakes.dart';

void main() {
  testWidgets('SA-AUD-T20: cancelled/expired orders — including a verified late payment that needs a refund — appear in no tab',
      (tester) async {
    final refundOwed = auditOrder(
      id: 'o-refund', code: 'LD-REFUND', status: OrderStatus.cancelled,
      paymentStatus: OrderPaymentStatus.paid, totalPaidPaisa: 158000,
    );
    final expiredAdvance = auditOrder(id: 'o-exp', code: 'LD-EXPIRD', status: OrderStatus.expired);
    final repo = AuditRepo(orders: [refundOwed, expiredAdvance]);
    await tester.pumpWidget(auditApp(KanbanBoardScreen(repository: repo)));
    await tester.pumpAndSettle();
    for (final tab in ['Pending (0)', 'Paid (0)', 'Ready (0)', 'Shipped (0)']) {
      expect(find.text(tab), findsOneWidget);
    }
    expect(find.text('#LD-REFUND'), findsNothing);
  });

  testWidgets('SA-AUD-T21: advance-paid (confirmed) orders show "Dispatch" although the DB refuses to ship them',
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
    expect(find.text('Dispatch'), findsOneWidget);
    expect(find.text('4×6 Label'), findsOneWidget); // label prints "PREPAID - DO NOT COLLECT CASH" with ₹2,250 still due
  });
}
