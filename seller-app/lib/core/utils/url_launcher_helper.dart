import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';

/// LiveDrop Seller Mobile App — Resilient URL & Deep Link Launcher Helper
///
/// Features multi-tier fallbacks:
/// 1. Native app scheme intent (e.g. `whatsapp://`, `tel:`, `upi://`)
/// 2. Universal HTTPS web link
/// 3. In-app tactile SnackBar with copy-to-clipboard fallback
class UrlLauncherHelper {
  UrlLauncherHelper._();

  /// Launches WhatsApp with native scheme first, then web link, then clipboard fallback.
  static Future<void> launchWhatsApp({
    required BuildContext context,
    required String phone,
    required String message,
  }) async {
    final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
    final encodedMessage = Uri.encodeComponent(message);

    // 1. Try native WhatsApp scheme
    final nativeUri = Uri.parse('whatsapp://send?phone=$cleanPhone&text=$encodedMessage');
    try {
      if (await canLaunchUrl(nativeUri)) {
        final launched = await launchUrl(nativeUri, mode: LaunchMode.externalNonBrowserApplication);
        if (launched) return;
      }
    } catch (_) {
      // Fall through to web universal link
    }

    // 2. Try universal web wa.me link
    final webUri = Uri.parse('https://wa.me/$cleanPhone?text=$encodedMessage');
    try {
      if (await canLaunchUrl(webUri)) {
        final launched = await launchUrl(webUri, mode: LaunchMode.externalApplication);
        if (launched) return;
      }
    } catch (_) {
      // Fall through to fallback UI
    }

    // 3. Fallback: Copy phone number to clipboard and inform user
    await Clipboard.setData(ClipboardData(text: phone));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.obsidianSurface,
        content: Text(
          'Could not open WhatsApp. Number $phone copied to clipboard.',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        action: SnackBarAction(
          label: 'OK',
          textColor: AppColors.goldPrimary,
          onPressed: () {},
        ),
      ),
    );
  }

  /// Launches the phone dialer with `tel:` scheme.
  static Future<void> launchDialer({
    required BuildContext context,
    required String phoneNumber,
  }) async {
    final uri = Uri.parse('tel:$phoneNumber');
    try {
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri);
        if (launched) return;
      }
    } catch (_) {
      // Fall through
    }

    await Clipboard.setData(ClipboardData(text: phoneNumber));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.obsidianSurface,
        content: Text(
          'Number $phoneNumber copied to clipboard.',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
      ),
    );
  }

  /// Launches an external web URL in the system browser.
  static Future<void> launchExternalWebUrl({
    required BuildContext context,
    required String url,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;

    try {
      if (await canLaunchUrl(uri)) {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (launched) return;
      }
    } catch (_) {
      // Fall through
    }

    await Clipboard.setData(ClipboardData(text: url));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.obsidianSurface,
        content: Text(
          'Link copied to clipboard: $url',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
      ),
    );
  }

  /// Launches a UPI payment intent or copies VPA to clipboard.
  static Future<void> launchUpiPayment({
    required BuildContext context,
    required String upiUriString,
    required String fallbackUpiId,
  }) async {
    final uri = Uri.tryParse(upiUriString);
    if (uri != null) {
      try {
        if (await canLaunchUrl(uri)) {
          final launched = await launchUrl(uri, mode: LaunchMode.externalNonBrowserApplication);
          if (launched) return;
        }
      } catch (_) {
        // Fall through
      }
    }

    await Clipboard.setData(ClipboardData(text: fallbackUpiId));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.obsidianSurface,
        content: Text(
          'UPI ID "$fallbackUpiId" copied to clipboard. Open your UPI app to pay.',
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
