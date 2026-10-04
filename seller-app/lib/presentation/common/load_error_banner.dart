import 'package:flutter/material.dart';

import '../../core/errors/seller_error_messages.dart';
import '../../core/theme/app_colors.dart';

/// Shown at the top of a screen whose data could not be loaded (SA-OBS-001):
/// the seller sees that something failed instead of an empty screen.
class LoadErrorBanner extends StatelessWidget {
  final Object error;
  final String what;
  final VoidCallback onRetry;

  const LoadErrorBanner({super.key, required this.error, required this.what, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final offline = SellerErrorMessages.isNetworkError(error);
    return Container(
      key: const Key('load-error-banner'),
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: AppColors.crimsonTint,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.crimson),
      ),
      child: Row(
        children: [
          Icon(offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded, color: AppColors.crimson, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              offline
                  ? 'No connection: $what may be out of date.'
                  : 'Could not load $what. What you see may be incomplete.',
              style: const TextStyle(color: AppColors.textPrimary, fontSize: 12),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
