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
        'store_slug': 'mothers-boutique',
        'phone_number': '919830012345',
        'upi_id': 'mothersboutique@okaxis',
        'upi_qr_url': 'https://storage.livedrop.store/qrs/mb.webp',
        'return_address': '12A Ballygunge Place, Kolkata - 700019',
        'default_shipping_fee_paisa': 8000,
        'free_shipping_threshold_paisa': 200000,
        'advance_confirmation_enabled': true,
        'advance_amount_paisa': 25000,
        'hold_duration_days': 30,
      };

      final profile = SellerProfile.fromJson(json);
      expect(profile.id, '8a329e71-4b10-4055-90d2-df8029d5b512');
      expect(profile.storeName, "Mother's Boutique");
      expect(profile.storeSlug, 'mothers-boutique');
      expect(profile.defaultShippingFeePaisa, 8000);
      expect(profile.freeShippingThresholdPaisa, 200000);
      expect(profile.advanceConfirmationEnabled, true);
      expect(profile.advanceAmountPaisa, 25000);
      expect(profile.holdDurationDays, 30);
    });

    test('SellerProfile defaults advanceConfirmationEnabled to false if omitted', () {
      final json = {
        'id': '8a329e71-4b10-4055-90d2-df8029d5b512',
        'store_name': 'New Seller',
        'store_slug': 'new-seller',
        'phone_number': '919830012345',
        'upi_id': 'newseller@okaxis',
        'return_address': '12A Ballygunge Place, Kolkata - 700019',
        'default_shipping_fee_paisa': 8000,
      };

      final profile = SellerProfile.fromJson(json);
      expect(profile.advanceConfirmationEnabled, false);
      expect(profile.advanceAmountPaisa, 25000);
      expect(profile.holdDurationDays, 30);
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
        'status': 'confirmed',
        'confirmation_mode': 'advance',
        'advance_required_paisa': 25000,
        'advance_paid_paisa': 25000,
        'total_paid_paisa': 25000,
        'balance_due_paisa': 58000,
        'payment_status': 'advance_paid',
        'fulfilment_status': 'not_ready',
        'hold_expires_at': '2026-10-11T15:00:00Z',
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
      expect(order.status, OrderStatus.confirmed);
      expect(order.confirmationMode, OrderConfirmationMode.advance);
      expect(order.advanceRequiredPaisa, 25000);
      expect(order.advancePaidPaisa, 25000);
      expect(order.totalPaidPaisa, 25000);
      expect(order.balanceDuePaisa, 58000);
      expect(order.paymentStatus, OrderPaymentStatus.advancePaid);
      expect(order.fulfilmentStatus, OrderFulfilmentStatus.notReady);
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

  group('TASK-2.4B: Seller Direct UPI & Manual Verification Tests', () {
    test('SellerProfile parses UPI settings correctly', () {
      final json = {
        'id': '8a329e71-4b10-4055-90d2-df8029d5b512',
        'store_name': "Mother's Boutique",
        'store_slug': 'mothers-boutique',
        'phone_number': '919830012345',
        'upi_id': 'mothersboutique@okaxis',
        'upi_vpa': 'mothersboutique@okaxis',
        'upi_display_name': "Mother's Boutique Official",
        'payment_instructions': 'Include reference LD-XXXX in note',
        'upi_enabled': true,
        'return_address': '12A Ballygunge Place, Kolkata - 700019',
        'default_shipping_fee_paisa': 8000,
        'advance_confirmation_enabled': true,
        'advance_amount_paisa': 25000,
        'hold_duration_days': 30,
      };

      final profile = SellerProfile.fromJson(json);
      expect(profile.upiEnabled, true);
      expect(profile.upiVpa, 'mothersboutique@okaxis');
      expect(profile.upiDisplayName, "Mother's Boutique Official");
      expect(profile.paymentInstructions, 'Include reference LD-XXXX in note');
    });

    test('PaymentAttempt parses JSON correctly with status and timestamps', () {
      final json = {
        'id': 'a1000000-0000-0000-0000-000000000004',
        'order_id': '7a389156-3477-475b-a977-cb8a657ab078',
        'payment_type': 'advance',
        'payment_method': 'upi',
        'expected_amount_paisa': 30000,
        'payee_vpa_snapshot': 'artisansilks@upi',
        'payee_display_name_snapshot': 'Artisan Silks Handlooms',
        'transaction_reference': 'LD-ART404-ADV-1004',
        'status': 'awaiting_seller_verification',
        'buyer_claimed_at': '2026-09-14T11:45:00Z',
        'buyer_submitted_utr': '428739182738',
        'seller_verified_at': null,
        'verified_by': null,
        'rejection_reason': null,
        'expires_at': '2026-09-28T11:45:00Z',
        'created_at': '2026-09-14T11:30:00Z',
        'orders': {
          'order_code': 'LD-ART404',
          'buyer_name': 'Kavita Verma',
        },
      };

      final attempt = PaymentAttempt.fromJson(json);
      expect(attempt.id, 'a1000000-0000-0000-0000-000000000004');
      expect(attempt.paymentType, 'advance');
      expect(attempt.expectedAmountPaisa, 30000);
      expect(attempt.payeeVpaSnapshot, 'artisansilks@upi');
      expect(attempt.payeeDisplayNameSnapshot, 'Artisan Silks Handlooms');
      expect(attempt.transactionReference, 'LD-ART404-ADV-1004');
      expect(attempt.status, PaymentAttemptStatus.awaitingSellerVerification);
      expect(attempt.buyerSubmittedUtr, '428739182738');
      expect(attempt.orderCode, 'LD-ART404');
      expect(attempt.buyerName, 'Kavita Verma');
    });

    test('PaymentAttemptStatus enum values match DB constraints', () {
      expect(PaymentAttemptStatus.fromString('awaiting_payment').toDbValue(), 'awaiting_payment');
      expect(PaymentAttemptStatus.fromString('buyer_claimed').toDbValue(), 'buyer_claimed');
      expect(PaymentAttemptStatus.fromString('awaiting_seller_verification').toDbValue(), 'awaiting_seller_verification');
      expect(PaymentAttemptStatus.fromString('verified').toDbValue(), 'verified');
      expect(PaymentAttemptStatus.fromString('rejected').toDbValue(), 'rejected');
      expect(PaymentAttemptStatus.fromString('expired').toDbValue(), 'expired');
    });
  });
}
