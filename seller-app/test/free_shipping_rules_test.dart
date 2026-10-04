// SA-PAY-008: one free-shipping rule — drop threshold ?? shop threshold ?? none.
import 'package:flutter_test/flutter_test.dart';
import 'package:seller_app/core/validation/free_shipping_rules.dart';
import 'package:seller_app/domain/models/models.dart';

SellerDrop _drop({int? threshold}) => SellerDrop(
      id: 'd1',
      sellerId: 's1',
      title: 'Drop',
      slug: 'drop',
      status: DropStatus.draft,
      shippingFeePaisa: 8000,
      freeShippingThresholdPaisa: threshold,
      createdAt: DateTime.utc(2026, 10, 1),
    );

SellerProfile _profile({int? threshold}) => SellerProfile(
      id: 's1',
      storeName: 'Shop',
      storeSlug: 'shop',
      phoneNumber: '9876500001',
      upiId: 'shop@okaxis',
      returnAddress: 'Kolkata',
      defaultShippingFeePaisa: 8000,
      freeShippingThresholdPaisa: threshold,
      advanceConfirmationEnabled: false,
      advanceAmountPaisa: 25000,
      holdDurationDays: 30,
    );

void main() {
  group('FreeShippingRules.resolve', () {
    test('drop threshold wins when set', () {
      final p = FreeShippingRules.resolve(dropThresholdPaisa: 299900, shopThresholdPaisa: 150000);
      expect(p.thresholdPaisa, 299900);
      expect(p.source, FreeShippingSource.drop);
      expect(p.label, 'Free shipping above ₹2,999');
    });

    test('shop threshold applies when the drop has none', () {
      final p = FreeShippingRules.resolve(dropThresholdPaisa: null, shopThresholdPaisa: 150000);
      expect(p.thresholdPaisa, 150000);
      expect(p.source, FreeShippingSource.shop);
      expect(p.label, 'Free shipping above ₹1,500');
    });

    test('no threshold anywhere means NO free shipping (no ₹2,000 fallback)', () {
      final p = FreeShippingRules.resolve();
      expect(p.thresholdPaisa, isNull);
      expect(p.offersFreeShipping, isFalse);
      expect(p.source, FreeShippingSource.none);
      expect(p.label, 'No free shipping');
    });

    test('zero / negative stored values count as not set', () {
      expect(FreeShippingRules.resolve(dropThresholdPaisa: 0, shopThresholdPaisa: 100000).source,
          FreeShippingSource.shop);
      expect(FreeShippingRules.resolve(dropThresholdPaisa: 0, shopThresholdPaisa: 0).offersFreeShipping, isFalse);
    });

    test('forDrop reads the models', () {
      expect(FreeShippingRules.forDrop(_drop(threshold: 50000), _profile(threshold: 99900)).thresholdPaisa, 50000);
      expect(FreeShippingRules.forDrop(_drop(), _profile(threshold: 99900)).thresholdPaisa, 99900);
      expect(FreeShippingRules.forDrop(_drop(), _profile()).thresholdPaisa, isNull);
      expect(FreeShippingRules.forDrop(_drop(), null).thresholdPaisa, isNull);
    });
  });

  group('shippingFeeFor (integer paisa)', () {
    test('free at or above the threshold, flat fee below it', () {
      final p = FreeShippingRules.resolve(dropThresholdPaisa: 200000);
      expect(FreeShippingRules.shippingFeeFor(subtotalPaisa: 199999, shippingFeePaisa: 8000, policy: p), 8000);
      expect(FreeShippingRules.shippingFeeFor(subtotalPaisa: 200000, shippingFeePaisa: 8000, policy: p), 0);
    });

    test('without a threshold the fee always applies, even for large orders', () {
      expect(
        FreeShippingRules.shippingFeeFor(
            subtotalPaisa: 5000000, shippingFeePaisa: 8000, policy: FreeShippingPolicy.none),
        8000,
      );
    });
  });

  group('formatting and input', () {
    test('describe / formatRupees use Indian grouping', () {
      expect(FreeShippingRules.describe(null), 'No free shipping');
      expect(FreeShippingRules.describe(10000000), 'Free shipping above ₹1,00,000');
      expect(FreeShippingRules.formatRupees(299950), '₹2,999.50');
    });

    test('blank input is valid and means "not set"', () {
      expect(FreeShippingRules.validateRupeesInput(''), isNull);
      expect(FreeShippingRules.validateRupeesInput('   '), isNull);
      expect(FreeShippingRules.parseRupeesInput(' '), isNull);
    });

    test('whole rupees are parsed to paisa; invalid values are refused', () {
      expect(FreeShippingRules.parseRupeesInput('2999'), 299900);
      expect(FreeShippingRules.validateRupeesInput('2999'), isNull);
      expect(FreeShippingRules.validateRupeesInput('0'), isNotNull);
      expect(FreeShippingRules.validateRupeesInput('-5'), isNotNull);
      expect(FreeShippingRules.validateRupeesInput('29.99'), isNotNull);
      expect(FreeShippingRules.validateRupeesInput('abc'), isNotNull);
      expect(FreeShippingRules.validateRupeesInput('1000001'), isNotNull);
    });

    test('toRupeesInput shows only a real stored value', () {
      expect(FreeShippingRules.toRupeesInput(null), '');
      expect(FreeShippingRules.toRupeesInput(299900), '2999');
    });
  });
}
