import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/domain/models/models.dart';

void main() {
  group('TASK-1.4: Seller Realtime Event Deserialization Tests', () {
    test('SellerOrder parses incoming realtime record accurately', () {
      final record = {
        'id': '4b724590-7811-419b-a311-6b2a091df012',
        'drop_id': 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
        'order_code': 'LD-8F429B',
        'buyer_name': 'Sangeeta Mukherjee',
        'buyer_phone': '9830100001',
        'shipping_address': 'Flat 4B, Greenview Apts, Jadavpur',
        'pincode': '700032',
        'subtotal_paisa': 75000,
        'shipping_paisa': 8000,
        'total_paisa': 83000,
        'status': 'pending',
        'hold_expires_at': '2026-09-11T15:00:00Z',
        'paid_at': null,
        'shipped_at': null,
        'tracking_number': null,
        'courier_partner': null,
        'created_at': '2026-09-11T14:45:00Z',
      };

      final order = SellerOrder.fromJson(record);
      expect(order.id, '4b724590-7811-419b-a311-6b2a091df012');
      expect(order.orderCode, 'LD-8F429B');
      expect(order.status, OrderStatus.pending);
      expect(order.subtotalPaisa, 75000);
      expect(order.shippingPaisa, 8000);
      expect(order.totalPaisa, 83000);
    });

    test('SellerOrder parses status transition from pending to paid', () {
      final record = {
        'id': '4b724590-7811-419b-a311-6b2a091df012',
        'drop_id': 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
        'order_code': 'LD-8F429B',
        'buyer_name': 'Sangeeta Mukherjee',
        'buyer_phone': '9830100001',
        'shipping_address': 'Flat 4B, Greenview Apts, Jadavpur',
        'pincode': '700032',
        'subtotal_paisa': 75000,
        'shipping_paisa': 8000,
        'total_paisa': 83000,
        'status': 'paid',
        'hold_expires_at': null,
        'paid_at': '2026-09-11T14:50:00Z',
        'shipped_at': null,
        'tracking_number': null,
        'courier_partner': null,
        'created_at': '2026-09-11T14:45:00Z',
      };

      final order = SellerOrder.fromJson(record);
      expect(order.status, OrderStatus.paid);
      expect(order.paidAt, isNotNull);
    });
  });
}
