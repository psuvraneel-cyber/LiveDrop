// AUDIT-ONLY: timestamps from PostgREST are UTC. SA-ORD-001 fixed: T04/T05 inverted — the model
// converts to local time and the card prints local time.
// Run with TZ=Asia/Kolkata (run_flutter_audit_tests.sh does this).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/orders/order_card.dart';

import 'audit_fakes.dart';

void main() {
  test('SA-AUD-T04: PostgREST timestamptz is converted to local time at the model boundary', () {
    final order = SellerOrder.fromJson({
      'id': 'o1', 'drop_id': 'd1', 'order_code': 'LD-AB12CD', 'buyer_name': 'Riya Sen',
      'buyer_phone': '9830012345', 'shipping_address': '22 Ballygunge Place, Kolkata', 'pincode': '700019',
      'subtotal_paisa': 150000, 'shipping_paisa': 8000, 'total_paisa': 158000, 'status': 'paid',
      'payment_status': 'paid', 'fulfilment_status': 'not_ready', 'total_paid_paisa': 158000,
      'balance_due_paisa': 0, 'created_at': '2026-10-03T09:00:00.123456+00:00',
    });
    // ignore: avoid_print
    print('AUDIT T04 device offset=${DateTime.now().timeZoneOffset} createdAt.isUtc=${order.createdAt.isUtc} '
        'card text=${DateFormat('hh:mm a').format(order.createdAt)} local=${DateFormat('hh:mm a').format(order.createdAt.toLocal())}');
    expect(order.createdAt.isUtc, isFalse);
    expect(order.createdAt.isAtSameMomentAs(DateTime.utc(2026, 10, 3, 9, 0, 0, 123, 456)), isTrue);
  });

  testWidgets('SA-AUD-T05: order card shows the local clock time (02:30 PM in IST), not UTC (09:00 AM)', (tester) async {
    final order = auditOrder(
      status: OrderStatus.paid,
      paymentStatus: OrderPaymentStatus.paid,
      totalPaidPaisa: 158000,
      createdAt: DateTime.parse('2026-10-03T09:00:00+00:00'),
    );
    await tester.pumpWidget(auditApp(Scaffold(body: SingleChildScrollView(child: OrderCard(
      order: order,
      profile: auditProfile,
      repository: AuditRepo(orders: [order]),
      onOrderUpdated: () {},
    )))));
    final localClock = DateFormat('hh:mm').format(order.createdAt.toLocal());
    expect(find.textContaining(localClock), findsOneWidget);
    if (DateTime.now().timeZoneOffset == const Duration(hours: 5, minutes: 30)) {
      expect(find.textContaining('02:30'), findsOneWidget);
    }
  });
}
