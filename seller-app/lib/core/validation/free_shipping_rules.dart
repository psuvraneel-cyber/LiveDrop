import 'package:intl/intl.dart';

import '../../domain/models/models.dart';

/// Where the free-shipping threshold that applies to a drop comes from.
enum FreeShippingSource { drop, shop, none }

/// The free-shipping rule in force for a drop.
class FreeShippingPolicy {
  /// Threshold in paisa; null means no free shipping.
  final int? thresholdPaisa;
  final FreeShippingSource source;

  const FreeShippingPolicy._(this.thresholdPaisa, this.source);

  static const FreeShippingPolicy none = FreeShippingPolicy._(null, FreeShippingSource.none);

  bool get offersFreeShipping => thresholdPaisa != null;

  /// "Free shipping above ₹2,999" or "No free shipping".
  String get label => FreeShippingRules.describe(thresholdPaisa);
}

/// Single source of the free-shipping rule in the seller app (SA-PAY-008).
///
/// Owner decision: the threshold is the drop's own
/// `free_shipping_threshold_paisa` when set, otherwise the shop's
/// (`profiles.free_shipping_threshold_paisa`) when set, otherwise there is NO
/// free shipping. There is no hidden default amount. The server computes the
/// actual shipping charged; the app only displays the rule.
///
/// All amounts are integer paisa.
class FreeShippingRules {
  FreeShippingRules._();

  /// Largest threshold the seller may enter (₹10,00,000).
  static const int maxThresholdPaisa = 100000000;

  static final NumberFormat _inr = NumberFormat.decimalPattern('en_IN');

  /// Resolves the threshold for a drop (drop ?? shop ?? none). Non-positive
  /// stored values are treated as "not set".
  static FreeShippingPolicy resolve({int? dropThresholdPaisa, int? shopThresholdPaisa}) {
    if (dropThresholdPaisa != null && dropThresholdPaisa > 0) {
      return FreeShippingPolicy._(dropThresholdPaisa, FreeShippingSource.drop);
    }
    if (shopThresholdPaisa != null && shopThresholdPaisa > 0) {
      return FreeShippingPolicy._(shopThresholdPaisa, FreeShippingSource.shop);
    }
    return FreeShippingPolicy.none;
  }

  static FreeShippingPolicy forDrop(SellerDrop? drop, SellerProfile? profile) => resolve(
        dropThresholdPaisa: drop?.freeShippingThresholdPaisa,
        shopThresholdPaisa: profile?.freeShippingThresholdPaisa,
      );

  /// Shipping fee (paisa) for a [subtotalPaisa] under [policy] and a flat
  /// [shippingFeePaisa]: free when the subtotal reaches the threshold.
  static int shippingFeeFor({
    required int subtotalPaisa,
    required int shippingFeePaisa,
    required FreeShippingPolicy policy,
  }) {
    final threshold = policy.thresholdPaisa;
    if (threshold != null && subtotalPaisa >= threshold) return 0;
    return shippingFeePaisa;
  }

  /// "₹2,999" for 299900, "₹2,999.50" for 299950.
  static String formatRupees(int paisa) {
    final rupees = paisa ~/ 100;
    final rest = paisa % 100;
    final whole = _inr.format(rupees);
    return rest == 0 ? '₹$whole' : '₹$whole.${rest.toString().padLeft(2, '0')}';
  }

  /// "Free shipping above ₹X" or "No free shipping".
  static String describe(int? thresholdPaisa) {
    if (thresholdPaisa == null || thresholdPaisa <= 0) return 'No free shipping';
    return 'Free shipping above ${formatRupees(thresholdPaisa)}';
  }

  /// Text-field value for a stored threshold ('' when not set).
  static String toRupeesInput(int? thresholdPaisa) {
    if (thresholdPaisa == null || thresholdPaisa <= 0) return '';
    if (thresholdPaisa % 100 == 0) return (thresholdPaisa ~/ 100).toString();
    return '${thresholdPaisa ~/ 100}.${(thresholdPaisa % 100).toString().padLeft(2, '0')}';
  }

  /// Validates a threshold typed in whole rupees. Empty is valid (= not set).
  static String? validateRupeesInput(String? input) {
    final text = (input ?? '').trim();
    if (text.isEmpty) return null;
    final rupees = int.tryParse(text);
    if (rupees == null || rupees <= 0) {
      return 'Enter a whole rupee amount above 0, or leave it blank';
    }
    if (rupees * 100 > maxThresholdPaisa) {
      return 'Enter an amount up to ${formatRupees(maxThresholdPaisa)}';
    }
    return null;
  }

  /// Parses a threshold typed in whole rupees to paisa; null when blank.
  /// Call [validateRupeesInput] first.
  static int? parseRupeesInput(String? input) {
    final text = (input ?? '').trim();
    if (text.isEmpty) return null;
    final rupees = int.tryParse(text);
    if (rupees == null || rupees <= 0) return null;
    return rupees * 100;
  }
}
