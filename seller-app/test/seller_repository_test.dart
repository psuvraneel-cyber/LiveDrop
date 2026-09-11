import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/config/env_config.dart';
import 'package:seller_app/core/errors/exceptions.dart';
import 'package:seller_app/domain/models/models.dart';

void main() {
  group('TASK-1.4: Seller EnvConfig Tests', () {
    test('EnvConfig throws StateError when variables are unset', () {
      expect(
        () => EnvConfig.validate(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('TASK-1.4: Seller Domain Models & Integer Paisa Tests', () {
    test('SellerProfile parses JSON correctly with integer Paisa fields', () {
      final json = {
        'id': '8a329e71-4b10-4055-90d2-df8029d5b512',
        'store_name': "Mother's Boutique",
        'phone_number': '919830012345',
        'upi_id': 'mothersboutique@okaxis',
        'upi_qr_url': 'https://storage.livedrop.store/qrs/mb.webp',
        'return_address': '12A Ballygunge Place, Kolkata - 700019',
        'default_shipping_fee_paisa': 8000,
        'free_shipping_threshold_paisa': 200000,
      };

      final profile = SellerProfile.fromJson(json);
      expect(profile.id, '8a329e71-4b10-4055-90d2-df8029d5b512');
      expect(profile.storeName, "Mother's Boutique");
      expect(profile.defaultShippingFeePaisa, 8000);
      expect(profile.freeShippingThresholdPaisa, 200000);
    });

    test('SellerDrop parses status enum and integer Paisa shipping', () {
      final json = {
        'id': 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
        'seller_id': '8a329e71-4b10-4055-90d2-df8029d5b512',
        'title': 'Friday Silk Special',
        'slug': 'mothers-boutique',
        'status': 'live',
        'shipping_fee_paisa': 8000,
        'free_shipping_threshold_paisa': 200000,
        'live_started_at': '2026-09-11T14:00:00Z',
        'closed_at': null,
        'created_at': '2026-09-11T12:00:00Z',
      };

      final drop = SellerDrop.fromJson(json);
      expect(drop.status, DropStatus.live);
      expect(drop.shippingFeePaisa, 8000);
      expect(drop.freeShippingThresholdPaisa, 200000);
    });

    test('SellerProduct parses product status and integer Paisa price', () {
      final json = {
        'id': 'e9314c99-7f55-4089-a2bb-b001d2950df1',
        'drop_id': 'c1f76d42-4f36-4d2b-9801-b5e1cf3e6801',
        'code': '#A01',
        'title': 'Handloom Tussar Saree',
        'price_paisa': 185000,
        'size': 'Free Size',
        'image_url': 'https://images.livedrop.store/products/e931.webp',
        'status': 'available',
        'reserved_at': null,
        'reserved_by_order_id': null,
        'version': 1,
      };

      final product = SellerProduct.fromJson(json);
      expect(product.code, '#A01');
      expect(product.pricePaisa, 185000);
      expect(product.status, ProductStatus.available);
      expect(product.version, 1);
    });

    test('SellerOrder parses order and nested line items correctly', () {
      final json = {
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
        'order_items': [
          {
            'id': 'item-1',
            'order_id': '4b724590-7811-419b-a311-6b2a091df012',
            'product_id': 'a8219c11-1b22-4899-b1cc-c112d2950de2',
            'price_at_purchase_paisa': 75000,
            'products': {
              'code': '#A02',
              'title': 'Chanderi Cotton Kurti',
              'image_url': 'https://images.livedrop.store/products/a821.webp',
            },
          }
        ],
      };

      final order = SellerOrder.fromJson(json);
      expect(order.orderCode, 'LD-8F429B');
      expect(order.buyerName, 'Sangeeta Mukherjee');
      expect(order.totalPaisa, 83000);
      expect(order.status, OrderStatus.pending);
      expect(order.items.length, 1);
      expect(order.items.first.productCode, '#A02');
      expect(order.items.first.priceAtPurchasePaisa, 75000);
    });
  });

  group('TASK-1.4: Seller Exceptions Tests', () {
    test('ProductReclaimedException has code PRODUCT_ALREADY_RECLAIMED', () {
      const ex = ProductReclaimedException();
      expect(ex.code, 'PRODUCT_ALREADY_RECLAIMED');
      expect(ex.message, contains('claimed by another buyer'));
    });

    test('UnauthorizedException has code UNAUTHORIZED', () {
      const ex = UnauthorizedException();
      expect(ex.code, 'UNAUTHORIZED');
    });
  });
}
