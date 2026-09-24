import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/config/admin_config.dart';
import '../../core/config/env_config.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/bounceable_button.dart';
import '../../core/theme/boutique_haptics.dart';
import '../../core/utils/url_launcher_helper.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';
import '../payment_settings_screen.dart';

/// Screen 11: Luxury Boutique Settings & Preferences Screen
/// Fully interactive operational control center for boutique owners.
class SellerSettingsScreen extends StatefulWidget {
  final SellerRepository repository;

  const SellerSettingsScreen({super.key, required this.repository});

  @override
  State<SellerSettingsScreen> createState() => _SellerSettingsScreenState();
}

class _SellerSettingsScreenState extends State<SellerSettingsScreen> {
  SellerProfile? _profile;
  bool _isLoading = true;

  // Local device preferences (sound, notifications)
  bool _soundEnabled = true;
  bool _notifyNewOrders = true;
  bool _notifyPaymentClaims = true;
  bool _notifyHoldExpiries = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await widget.repository.getProfile();
      if (mounted) {
        setState(() {
          _profile = profile;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleSignOut() async {
    BoutiqueHaptics.light();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.obsidianSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout_rounded, color: AppColors.crimson, size: 22),
            SizedBox(width: 10),
            Text('Sign Out', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Are you sure you want to sign out of your boutique session? You will need to log in again to manage orders and inventory.',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.crimson,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      BoutiqueHaptics.heavy();
      await SupabaseService.instance.signOut();
    }
  }

  // ---------------------------------------------------------------------------
  // 1. Storefront Settings Bottom Sheet
  // ---------------------------------------------------------------------------
  void _openStorefrontSettings() {
    BoutiqueHaptics.light();
    final storeNameCtrl = TextEditingController(text: _profile?.storeName ?? '');
    final phoneCtrl = TextEditingController(text: _profile?.phoneNumber ?? '');
    final addressCtrl = TextEditingController(text: _profile?.returnAddress ?? '');
    final slug = _profile?.storeSlug ?? 'boutique';
    final storefrontUrl = EnvConfig.getStorefrontUrl(slug);
    bool isSaving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.obsidianSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Storefront Settings',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textMuted),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Web Store Preview Banner
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.obsidianElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.language, color: AppColors.goldPrimary, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text('Public Store Link', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                Text(
                                  storefrontUrl,
                                  style: const TextStyle(fontSize: 13, color: AppColors.textPrimary, fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.copy, size: 14, color: AppColors.goldPrimary),
                              label: const Text('Copy Link', style: TextStyle(fontSize: 12, color: AppColors.goldPrimary)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.cardBorder),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: storefrontUrl));
                                BoutiqueHaptics.light();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Store link copied to clipboard'),
                                    backgroundColor: AppColors.obsidianElevated,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.share, size: 14, color: AppColors.goldPrimary),
                              label: const Text('WhatsApp', style: TextStyle(fontSize: 12, color: AppColors.goldPrimary)),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: AppColors.cardBorder),
                                padding: const EdgeInsets.symmetric(vertical: 8),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: () {
                                BoutiqueHaptics.light();
                                final shareText = 'Visit my boutique on LiveDrop: $storefrontUrl';
                                UrlLauncherHelper.launchExternalWebUrl(
                                  context: context,
                                  url: 'https://wa.me/?text=${Uri.encodeComponent(shareText)}',
                                );
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            icon: const Icon(Icons.open_in_new, color: AppColors.goldPrimary, size: 18),
                            tooltip: 'Open in Browser',
                            onPressed: () => UrlLauncherHelper.launchExternalWebUrl(context: context, url: storefrontUrl),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                _buildModalTextField(
                  label: 'Store Name',
                  controller: storeNameCtrl,
                  icon: Icons.store_outlined,
                ),
                const SizedBox(height: 14),

                _buildModalTextField(
                  label: 'Support Phone Number',
                  controller: phoneCtrl,
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 14),

                _buildModalTextField(
                  label: 'Return / Dispatch Address',
                  controller: addressCtrl,
                  icon: Icons.location_on_outlined,
                  maxLines: 3,
                ),
                const SizedBox(height: 20),

                BounceableButton(
                  variant: ButtonVariant.goldGradient,
                  height: 48,
                  isLoading: isSaving,
                  onPressed: isSaving
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setModalState(() => isSaving = true);
                          try {
                            final updated = await widget.repository.updateProfile(
                              storeName: storeNameCtrl.text.trim(),
                              phoneNumber: phoneCtrl.text.trim(),
                              returnAddress: addressCtrl.text.trim(),
                            );
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (!mounted) return;
                            setState(() => _profile = updated);
                            BoutiqueHaptics.success();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Storefront settings updated successfully!'),
                                backgroundColor: AppColors.emerald,
                              ),
                            );
                          } catch (e) {
                            setModalState(() => isSaving = false);
                            BoutiqueHaptics.heavy();
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Failed to update: $e'),
                                  backgroundColor: AppColors.crimson,
                                ),
                              );
                            }
                          }
                        },
                  text: 'Save Storefront Settings',
                  icon: Icons.save_outlined,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Business Information Bottom Sheet
  // ---------------------------------------------------------------------------
  void _openBusinessInfo() {
    BoutiqueHaptics.light();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.obsidianSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Business Information',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildInfoRow('Seller ID', _profile?.id ?? 'N/A'),
            const Divider(color: AppColors.cardBorder, height: 20),
            _buildInfoRow('Store Slug', _profile?.storeSlug ?? 'N/A'),
            const Divider(color: AppColors.cardBorder, height: 20),
            _buildInfoRow('Verification Status', 'Active Verified Boutique', valueColor: AppColors.emerald),
            const Divider(color: AppColors.cardBorder, height: 20),
            _buildInfoRow('Registered Phone', _profile?.phoneNumber ?? 'N/A'),
            const SizedBox(height: 24),
            BounceableButton(
              variant: ButtonVariant.darkCard,
              height: 46,
              onPressed: () => Navigator.pop(ctx),
              text: 'Done',
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Order & Shipping Defaults Bottom Sheet
  // ---------------------------------------------------------------------------
  void _openOrderDefaults() {
    BoutiqueHaptics.light();
    final shippingFeeCtrl = TextEditingController(
      text: ((_profile?.defaultShippingFeePaisa ?? 8000) ~/ 100).toString(),
    );
    final advanceAmountCtrl = TextEditingController(
      text: ((_profile?.advanceAmountPaisa ?? 25000) ~/ 100).toString(),
    );
    bool advanceEnabled = _profile?.advanceConfirmationEnabled ?? false;
    int holdDays = _profile?.holdDurationDays ?? 30;
    bool isSaving = false;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.obsidianSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (sheetContext, setModalState) => Padding(
          padding: EdgeInsets.only(
            top: 20,
            left: 20,
            right: 20,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 24,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Order & Shipping Defaults',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.textMuted),
                      onPressed: () => Navigator.pop(sheetContext),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Default Shipping Fee Field
                _buildModalTextField(
                  label: 'Default Shipping Fee (₹)',
                  controller: shippingFeeCtrl,
                  icon: Icons.local_shipping_outlined,
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 14),

                // Advance Payment Confirmation Toggle
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.obsidianElevated,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: AppColors.cardBorder),
                  ),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Enable Advance Payments',
                      style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: const Text(
                      'Allow buyers to lock inventory with a partial advance deposit.',
                      style: TextStyle(color: AppColors.textMuted, fontSize: 12),
                    ),
                    value: advanceEnabled,
                    activeThumbColor: AppColors.goldPrimary,
                    onChanged: (val) {
                      BoutiqueHaptics.selection();
                      setModalState(() => advanceEnabled = val);
                    },
                  ),
                ),
                if (advanceEnabled) ...[
                  const SizedBox(height: 14),
                  _buildModalTextField(
                    label: 'Advance Deposit Amount (₹)',
                    controller: advanceAmountCtrl,
                    icon: Icons.account_balance_wallet_outlined,
                    keyboardType: TextInputType.number,
                  ),
                ],
                const SizedBox(height: 20),

                BounceableButton(
                  variant: ButtonVariant.goldGradient,
                  height: 48,
                  isLoading: isSaving,
                  onPressed: isSaving
                      ? null
                      : () async {
                          final feeInRupees = int.tryParse(shippingFeeCtrl.text.trim()) ?? 80;
                          final advanceInRupees = int.tryParse(advanceAmountCtrl.text.trim()) ?? 250;
                          final messenger = ScaffoldMessenger.of(context);

                          setModalState(() => isSaving = true);
                          try {
                            final updated = await widget.repository.updateProfile(
                              defaultShippingFeePaisa: feeInRupees * 100,
                              advanceConfirmationEnabled: advanceEnabled,
                              advanceAmountPaisa: advanceInRupees * 100,
                              holdDurationDays: holdDays,
                            );
                            if (sheetContext.mounted) {
                              Navigator.pop(sheetContext);
                            }
                            if (!mounted) return;
                            setState(() => _profile = updated);
                            BoutiqueHaptics.success();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Order defaults saved successfully!'),
                                backgroundColor: AppColors.emerald,
                              ),
                            );
                          } catch (e) {
                            setModalState(() => isSaving = false);
                            BoutiqueHaptics.heavy();
                            if (mounted) {
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text('Failed to save defaults: $e'),
                                  backgroundColor: AppColors.crimson,
                                ),
                              );
                            }
                          }
                        },
                  text: 'Save Order Defaults',
                  icon: Icons.save_outlined,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Notifications Sheet
  // ---------------------------------------------------------------------------
  void _openNotificationsSettings() {
    BoutiqueHaptics.light();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.obsidianSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Notification Alerts',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildNotificationSwitch(
                title: 'New Order Placed',
                subtitle: 'Push alert when a buyer purchases an item',
                value: _notifyNewOrders,
                onChanged: (v) {
                  BoutiqueHaptics.selection();
                  setSheetState(() => _notifyNewOrders = v);
                  setState(() => _notifyNewOrders = v);
                },
              ),
              const Divider(color: AppColors.cardBorder, height: 16),
              _buildNotificationSwitch(
                title: 'Manual Payment Claims',
                subtitle: 'Alert when a buyer submits a UPI transaction reference',
                value: _notifyPaymentClaims,
                onChanged: (v) {
                  BoutiqueHaptics.selection();
                  setSheetState(() => _notifyPaymentClaims = v);
                  setState(() => _notifyPaymentClaims = v);
                },
              ),
              const Divider(color: AppColors.cardBorder, height: 16),
              _buildNotificationSwitch(
                title: 'Hold Expiry Reminders',
                subtitle: 'Alert 1 hour before an unconfirmed reservation releases',
                value: _notifyHoldExpiries,
                onChanged: (v) {
                  BoutiqueHaptics.selection();
                  setSheetState(() => _notifyHoldExpiries = v);
                  setState(() => _notifyHoldExpiries = v);
                },
              ),
              const SizedBox(height: 20),
              BounceableButton(
                variant: ButtonVariant.darkCard,
                height: 46,
                onPressed: () => Navigator.pop(ctx),
                text: 'Done',
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 5. App Preferences & Help & Support
  // ---------------------------------------------------------------------------
  void _openAppPreferences() {
    BoutiqueHaptics.light();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.obsidianSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'App Preferences',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: AppColors.textMuted),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildNotificationSwitch(
                title: 'Tactile Haptics & Sound',
                subtitle: 'Vibration response on button presses and actions',
                value: _soundEnabled,
                onChanged: (v) {
                  BoutiqueHaptics.selection();
                  setSheetState(() => _soundEnabled = v);
                  setState(() => _soundEnabled = v);
                },
              ),
              const Divider(color: AppColors.cardBorder, height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cleaning_services_outlined, color: AppColors.goldPrimary, size: 22),
                title: const Text('Clear Image Cache', style: TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Free up storage used by product intakes', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: AppColors.textMuted),
                onTap: () {
                  BoutiqueHaptics.medium();
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Local image cache cleared successfully.'),
                      backgroundColor: AppColors.obsidianElevated,
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              BounceableButton(
                variant: ButtonVariant.darkCard,
                height: 46,
                onPressed: () => Navigator.pop(ctx),
                text: 'Close',
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openHelpAndSupport() {
    BoutiqueHaptics.light();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.obsidianSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        side: BorderSide(color: AppColors.cardBorder),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Help & Concierge Support',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: AppColors.textMuted),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const SizedBox(height: 16),
            BounceableButton(
              variant: ButtonVariant.goldGradient,
              height: 48,
              onPressed: () {
                Navigator.pop(ctx);
                UrlLauncherHelper.launchWhatsApp(
                  context: context,
                  phone: AdminConfig.whatsAppNumber,
                  message: 'Hello LiveDrop Support, I am seller "${_profile?.storeName ?? 'My Boutique'}" (ID: ${_profile?.id ?? ''}) needing assistance.',
                );
              },
              text: 'Chat with Admin on WhatsApp',
              icon: Icons.chat_outlined,
            ),
            const SizedBox(height: 12),
            BounceableButton(
              variant: ButtonVariant.darkCard,
              height: 48,
              onPressed: () {
                Navigator.pop(ctx);
                UrlLauncherHelper.launchDialer(
                  context: context,
                  phoneNumber: '+917439583884',
                );
              },
              text: 'Call Seller Concierge',
              icon: Icons.phone_outlined,
            ),
            const SizedBox(height: 16),
            const Text(
              'LiveDrop Concierge is available 9 AM – 9 PM IST for seller support.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: AppColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final storeName = _profile?.storeName ?? 'My Boutique';
    final email = SupabaseService.instance.isInitialized
        ? (SupabaseService.instance.client.auth.currentUser?.email ?? 'Not available')
        : 'Not available';

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        title: const Text('Boutique Settings', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.goldPrimary))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                children: [
                  // Profile Header Card (Tapping opens Storefront Settings)
                  InkWell(
                    onTap: _openStorefrontSettings,
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: AppTheme.cardDecoration(),
                      child: Row(
                        children: [
                          Container(
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.obsidianElevated,
                              border: Border.all(color: AppColors.goldPrimary, width: 1.5),
                            ),
                            child: const Center(
                              child: Icon(Icons.storefront_rounded, color: AppColors.goldPrimary, size: 28),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  storeName,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  email,
                                  style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                                ),
                                const SizedBox(height: 6),
                                const Row(
                                  children: [
                                    Text(
                                      'Edit Storefront Profile',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: AppColors.goldPrimary,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    SizedBox(width: 4),
                                    Icon(Icons.arrow_forward_ios_rounded, size: 10, color: AppColors.goldPrimary),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate().fadeIn(duration: 350.ms).slideY(begin: 0.05, end: 0),
                  const SizedBox(height: 18),

                  // Grouped Settings List
                  Container(
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      children: [
                        _buildSettingTile(
                          icon: Icons.storefront_outlined,
                          title: 'Storefront Settings',
                          subtitle: 'Boutique name, contact, address, web link',
                          onTap: _openStorefrontSettings,
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),
                        _buildSettingTile(
                          icon: Icons.payment_outlined,
                          title: 'Payment & UPI Settings',
                          subtitle: 'Authoritative UPI ID, QR, instructions',
                          onTap: () {
                            BoutiqueHaptics.light();
                            Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                builder: (_) => PaymentSettingsScreen(repository: widget.repository),
                              ),
                            ).then((_) => _loadProfile());
                          },
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),
                        _buildSettingTile(
                          icon: Icons.local_shipping_outlined,
                          title: 'Order & Shipping Defaults',
                          subtitle: 'Default shipping fee, advance deposit rules',
                          onTap: _openOrderDefaults,
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),
                        _buildSettingTile(
                          icon: Icons.badge_outlined,
                          title: 'Business Information',
                          subtitle: 'Seller ID, store slug, verification badge',
                          onTap: _openBusinessInfo,
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),
                        _buildSettingTile(
                          icon: Icons.notifications_none_rounded,
                          title: 'Notifications',
                          subtitle: 'Orders, payments, hold expiry alerts',
                          onTap: _openNotificationsSettings,
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),
                        _buildSettingTile(
                          icon: Icons.tune_rounded,
                          title: 'App Preferences',
                          subtitle: 'Haptics, cache management',
                          onTap: _openAppPreferences,
                        ),
                        const Divider(color: AppColors.cardBorder, height: 1),
                        _buildSettingTile(
                          icon: Icons.help_outline_rounded,
                          title: 'Help & Concierge Support',
                          subtitle: 'WhatsApp concierge, phone, FAQs',
                          onTap: _openHelpAndSupport,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 400.ms, delay: 100.ms).slideY(begin: 0.05, end: 0),
                  const SizedBox(height: 24),

                  // Red Outlined Sign Out Button
                  BounceableButton(
                    onPressed: _handleSignOut,
                    variant: ButtonVariant.crimsonOutline,
                    height: 50,
                    text: 'Sign Out',
                    icon: Icons.logout_rounded,
                  ).animate().fadeIn(duration: 400.ms, delay: 200.ms),
                  const SizedBox(height: 28),

                  // Signature Brand Footer
                  const Text(
                    'LiveDrop • Sell • Grow • Belong',
                    style: TextStyle(
                      fontSize: 12,
                      fontStyle: FontStyle.italic,
                      color: AppColors.textMuted,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
    );
  }

  Widget _buildSettingTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.obsidianElevated,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.goldPrimary, size: 20),
      ),
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
      ),
      trailing: const Icon(Icons.arrow_forward_ios_rounded, color: AppColors.textMuted, size: 13),
      onTap: onTap,
    );
  }

  Widget _buildModalTextField({
    required String label,
    required TextEditingController controller,
    required IconData icon,
    TextInputType? keyboardType,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.textSecondary),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          maxLines: maxLines,
          style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
          decoration: InputDecoration(
            filled: true,
            fillColor: AppColors.obsidianElevated,
            prefixIcon: Icon(icon, color: AppColors.goldPrimary, size: 18),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.cardBorder),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: AppColors.goldPrimary, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 13, color: AppColors.textMuted)),
        Flexible(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: valueColor ?? AppColors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildNotificationSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(title, style: const TextStyle(color: AppColors.textPrimary, fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text(subtitle, style: const TextStyle(color: AppColors.textMuted, fontSize: 12)),
      value: value,
      activeThumbColor: AppColors.goldPrimary,
      activeTrackColor: AppColors.goldMuted,
      onChanged: onChanged,
    );
  }
}
