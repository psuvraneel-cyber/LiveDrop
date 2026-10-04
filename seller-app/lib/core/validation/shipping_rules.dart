/// Seller-entered dispatch details (SA-SHIP-001).
///
/// The app never invents a tracking/AWB number: the seller types the one the
/// courier issued. These checks only catch obvious mistakes before the
/// `mark_order_shipped` RPC (which remains the authority).
class ShippingRules {
  ShippingRules._();

  static const int minTrackingLength = 6;
  static const int maxTrackingLength = 40;
  static const int maxCourierLength = 60;

  /// Letters, digits and the separators couriers use (`-`, `/`); must start
  /// and end with a letter or digit.
  static final RegExp _trackingPattern = RegExp(r'^[A-Za-z0-9](?:[A-Za-z0-9\-/]*[A-Za-z0-9])?$');

  /// Example values shown in hints/old builds. Never accepted as real AWBs.
  static const Set<String> _placeholderTracking = {'DVA123456789'};

  /// Trimmed tracking number as it will be sent.
  static String normalizeTracking(String input) => input.trim();

  /// Returns a seller-facing problem with [input], or null when acceptable.
  static String? validateTracking(String? input) {
    final value = normalizeTracking(input ?? '');
    if (value.isEmpty) return 'Enter the tracking / AWB number from your courier';
    if (value.contains(RegExp(r'\s'))) return 'Remove spaces from the tracking number';
    if (value.length < minTrackingLength) {
      return 'Tracking number looks too short (at least $minTrackingLength characters)';
    }
    if (value.length > maxTrackingLength) {
      return 'Tracking number is too long (at most $maxTrackingLength characters)';
    }
    if (!_trackingPattern.hasMatch(value)) {
      return 'Use only letters, numbers, "-" or "/"';
    }
    if (_placeholderTracking.contains(value.toUpperCase())) {
      return 'Enter the real tracking number from your courier';
    }
    return null;
  }

  /// Returns a seller-facing problem with [input], or null when acceptable.
  static String? validateCourier(String? input) {
    final value = (input ?? '').trim();
    if (value.isEmpty) return 'Choose or type the courier partner';
    if (value.length < 2) return 'Courier name looks too short';
    if (value.length > maxCourierLength) {
      return 'Courier name is too long (at most $maxCourierLength characters)';
    }
    return null;
  }
}
