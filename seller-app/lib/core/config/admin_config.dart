/// LiveDrop Seller Mobile App — Admin Contact & Onboarding Configuration
///
/// Authoritative admin details for the "Contact Admin" WhatsApp link
/// and the ₹50 onboarding fee payment flow during seller registration.
class AdminConfig {
  AdminConfig._();

  /// Admin WhatsApp number with country code (no + prefix, digits only).
  /// Used by the "Contact Admin" button on the login screen.
  /// Format: country code + number, e.g. '917439583884' for +91 74395 83884.
  static const String whatsAppNumber = '917439583884';

  /// Admin UPI VPA for receiving the ₹50 onboarding fee.
  /// Displayed to new sellers during registration.
  static const String onboardingUpiId = 'psuvraneel@okaxis';

  /// Admin/payee display name shown on the UPI payment screen and QR.
  static const String onboardingUpiDisplayName = 'Suvraneel Paul';

  /// Asset path to the admin UPI QR code image.
  static const String qrCodeAssetPath = 'assets/images/admin_upi_qr.jpg';

  /// Onboarding fee amount in Paisa (₹50 = 5000 Paisa).
  /// Strictly integer, never floating-point (ADR-009).
  static const int onboardingFeePaisa = 5000;

  /// Human-readable onboarding fee in ₹.
  static String get onboardingFeeDisplay =>
      '₹${onboardingFeePaisa ~/ 100}';

  /// Pre-filled WhatsApp message for the "Contact Admin" button.
  static const String whatsAppMessage =
      'Hi, I am a boutique seller and I would like to get access to the LiveDrop Seller app. '
      'Please help me set up my account.';

  /// Full WhatsApp deep link URL.
  static String get whatsAppUrl =>
      'https://wa.me/$whatsAppNumber?text=${Uri.encodeComponent(whatsAppMessage)}';

  /// UPI intent URL for the onboarding payment.
  static String get upiPaymentUrl =>
      'upi://pay?pa=$onboardingUpiId'
      '&pn=${Uri.encodeComponent(onboardingUpiDisplayName)}'
      '&am=${onboardingFeePaisa ~/ 100}'
      '&tn=${Uri.encodeComponent('LiveDrop Seller Onboarding Fee')}'
      '&cu=INR';
}
