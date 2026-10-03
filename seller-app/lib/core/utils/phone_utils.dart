/// Phone helpers for buyer contact links.
class PhoneUtils {
  PhoneUtils._();

  /// International digits for a WhatsApp link (`wa.me/<digits>`), assuming
  /// India (+91) for 10-digit mobile numbers. Numbers that already carry a
  /// country code are kept as they are, so a mobile number that itself starts
  /// with "91" (e.g. 9123456789) still gets the +91 prefix.
  static String whatsAppDigits(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) return '91$digits';
    if (digits.length == 11 && digits.startsWith('0')) return '91${digits.substring(1)}';
    if (digits.length == 13 && digits.startsWith('091')) return digits.substring(1);
    return digits;
  }
}
