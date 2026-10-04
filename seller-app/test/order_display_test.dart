import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/utils/phone_utils.dart';
import 'package:seller_app/domain/models/models.dart';
import 'package:seller_app/presentation/orders/order_details_screen.dart';

void main() {
  group('PhoneUtils.whatsAppDigits (SA-ORD-002)', () {
    const cases = {
      '9123456789': '919123456789', // mobile that itself starts with 91
      '9830012345': '919830012345',
      '+91 98300 12345': '919830012345',
      '919830012345': '919830012345',
      '09830012345': '919830012345',
      '0919830012345': '919830012345',
    };
    cases.forEach((raw, expected) {
      test('$raw -> $expected', () => expect(PhoneUtils.whatsAppDigits(raw), expected));
    });
  });

  group('buyerInitials (SA-ORD-003)', () {
    const cases = {
      'Priya Sharma': 'PS',
      'Priya  Sharma': 'PS',
      '  riya\tsen ': 'RS',
      'Ananya': 'A',
      '': 'B',
      '   ': 'B',
      'Mou Rani Das': 'MR',
    };
    cases.forEach((name, expected) {
      test('"$name" -> $expected', () => expect(buyerInitials(name), expected));
    });
  });

  test('order timestamps are local DateTimes for the same instant (SA-ORD-001)', () {
    final order = SellerOrder.fromJson({
      'id': 'o1', 'drop_id': 'd1', 'order_code': 'LD-AB12CD', 'buyer_name': 'Riya Sen',
      'buyer_phone': '9830012345', 'shipping_address': '22 Ballygunge Place, Kolkata', 'pincode': '700019',
      'subtotal_paisa': 150000, 'shipping_paisa': 8000, 'total_paisa': 158000, 'status': 'paid',
      'payment_status': 'paid', 'fulfilment_status': 'not_ready', 'total_paid_paisa': 158000,
      'balance_due_paisa': 0, 'created_at': '2026-10-03T20:00:00+00:00',
      'paid_at': '2026-10-03T20:05:00+00:00',
    });
    expect(order.createdAt.isUtc, isFalse);
    expect(order.createdAt.isAtSameMomentAs(DateTime.utc(2026, 10, 3, 20)), isTrue);
    expect(order.paidAt!.isUtc, isFalse);
    if (DateTime.now().timeZoneOffset == const Duration(hours: 5, minutes: 30)) {
      // 20:00 UTC is 01:30 the next morning in IST: it belongs to 4 October.
      expect(order.createdAt.day, 4);
      expect(order.createdAt.hour, 1);
    }
  });
}
