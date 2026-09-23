import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/config/admin_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/bounceable_button.dart';
import '../../core/theme/brand_emblem.dart';

/// Screen displayed when an authenticated boutique seller's account is pending administrative review.
class SellerPendingApprovalScreen extends StatefulWidget {
  final VoidCallback onRefreshStatus;
  final VoidCallback onSignOut;

  const SellerPendingApprovalScreen({
    super.key,
    required this.onRefreshStatus,
    required this.onSignOut,
  });

  @override
  State<SellerPendingApprovalScreen> createState() =>
      _SellerPendingApprovalScreenState();
}

class _SellerPendingApprovalScreenState
    extends State<SellerPendingApprovalScreen> {
  bool _isChecking = false;

  Future<void> _contactAdmin() async {
    final uri = Uri.parse(AdminConfig.whatsAppUrl);
    if (!await launchUrl(uri)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not launch WhatsApp. Contact: +91 74395 83884'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const BrandEmblem(size: 64),
                const SizedBox(height: 32),
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    color: AppColors.goldMuted,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.goldPrimary, width: 2),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.hourglass_top_rounded,
                      color: AppColors.goldPrimary,
                      size: 40,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Account Under Review',
                  style: TextStyle(
                    fontFamily: 'Playfair',
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Your boutique application and payment evidence have been submitted. To protect buyers and preserve high trust, LiveDrop administrators manually verify all boutique credentials before enabling live drops.',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.obsidianSurface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: const Column(
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.shield_outlined,
                            color: AppColors.goldPrimary,
                            size: 20,
                          ),
                          SizedBox(width: 8),
                          Text(
                            'Operational Safeguards',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      Text(
                        '• Live drop publishing is disabled until approval.\n• Direct buyer checkouts are held.\n• Approvals are typically processed within 2–4 hours.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                BounceableButton(
                  onPressed: _isChecking
                      ? null
                      : () {
                          setState(() => _isChecking = true);
                          widget.onRefreshStatus();
                          if (mounted) setState(() => _isChecking = false);
                        },
                  variant: ButtonVariant.goldGradient,
                  height: 50,
                  isLoading: _isChecking,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.refresh, color: Colors.black, size: 20),
                      SizedBox(width: 8),
                      Text(
                        'Check Approval Status',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                BounceableButton(
                  onPressed: _contactAdmin,
                  variant: ButtonVariant.darkCard,
                  height: 48,
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_outlined,
                        color: AppColors.whatsAppGreen,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Contact Support on WhatsApp',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.whatsAppGreen,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: widget.onSignOut,
                  child: const Text(
                    'Sign Out',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
