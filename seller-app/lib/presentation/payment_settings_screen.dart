import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/bounceable_button.dart';
import '../core/theme/boutique_haptics.dart';
import '../core/errors/exceptions.dart';
import '../data/repositories/seller_repository.dart';
import '../domain/models/models.dart';
import 'auth/confirm_password_dialog.dart';

/// LiveDrop Seller Mobile App — Direct UPI Payment Settings Screen (TASK-2.4B)
///
/// Enables sellers to configure their authoritative UPI ID, display name,
/// and optional payment instructions for direct buyer payments.
/// Redesigned with the Luxury Boutique Noir aesthetic.
class PaymentSettingsScreen extends StatefulWidget {
  final SellerRepository repository;

  const PaymentSettingsScreen({super.key, required this.repository});

  @override
  State<PaymentSettingsScreen> createState() => _PaymentSettingsScreenState();
}

class _PaymentSettingsScreenState extends State<PaymentSettingsScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _upiVpaController;
  late TextEditingController _upiDisplayNameController;
  late TextEditingController _instructionsController;

  bool _isLoading = true;
  bool _isSaving = false;
  bool _upiEnabled = true;
  String? _errorMessage;

  /// UPI ID as loaded; a different value needs the password (SA-AUTH-004).
  String _savedVpa = '';
  bool _dropIsLive = false;
  List<PayeeChange> _recentChanges = const [];

  static final _vpaRegex = RegExp(r'^[a-zA-Z0-9.\-_]{2,255}@[a-zA-Z]{2,64}$');

  @override
  void initState() {
    super.initState();
    _upiVpaController = TextEditingController();
    _upiDisplayNameController = TextEditingController();
    _instructionsController = TextEditingController();
    _loadProfile();
  }

  @override
  void dispose() {
    _upiVpaController.dispose();
    _upiDisplayNameController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profile = await widget.repository.getProfile();
      if (mounted) {
        setState(() {
          _upiEnabled = profile.upiEnabled;
          _upiVpaController.text = profile.upiVpa ?? profile.upiId;
          _savedVpa = _upiVpaController.text.trim();
          _upiDisplayNameController.text = profile.upiDisplayName ?? profile.storeName;
          _instructionsController.text = profile.paymentInstructions ?? '';
          _isLoading = false;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _errorMessage = err is LiveDropException ? err.message : 'Could not load your payment settings.';
          _isLoading = false;
        });
      }
    }
    await _loadSafetyContext();
  }

  /// Live-drop warning and recent payee changes. Failures only hide them.
  Future<void> _loadSafetyContext() async {
    try {
      final drops = await widget.repository.getDrops();
      final changes = await widget.repository.getPayeeChangeLog(limit: 5);
      if (!mounted) return;
      setState(() {
        _dropIsLive = drops.any((d) => d.status == DropStatus.live);
        _recentChanges = changes;
      });
    } catch (e) {
      debugPrint('[PaymentSettings] Safety context unavailable: $e');
    }
  }

  /// A new UPI ID decides where every buyer's money goes: confirm it and the
  /// seller's password first (SA-AUTH-004).
  Future<bool> _confirmPayeeChange(String newVpa) {
    final liveNote = _dropIsLive
        ? '\n\nA drop is live right now. Buyers who open a payment from now on will pay the new UPI ID.'
        : '';
    return showConfirmPasswordDialog(
      context,
      title: 'Change your UPI ID?',
      message: 'Buyers will pay to:\n$newVpa\n\nCheck every character. Money sent to a wrong UPI ID '
          'cannot be recovered by LiveDrop.$liveNote',
      reauthenticate: widget.repository.reauthenticate,
    );
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) {
      BoutiqueHaptics.heavy();
      return;
    }

    final newVpa = _upiVpaController.text.trim();
    if (newVpa != _savedVpa) {
      final confirmed = await _confirmPayeeChange(newVpa);
      if (!confirmed || !mounted) return;
    }

    setState(() {
      _isSaving = true;
      _errorMessage = null;
    });

    try {
      await _saveUpi();
      _savedVpa = newVpa;
      unawaited(_loadSafetyContext());

      BoutiqueHaptics.success();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('UPI payment settings saved successfully!'),
            backgroundColor: Color(0xFF10B981),
          ),
        );
      }
    } catch (err) {
      BoutiqueHaptics.heavy();
      if (mounted) {
        setState(() {
          _errorMessage = err is LiveDropException && err.code == 'REAUTH_REQUIRED'
              ? 'For your safety, confirm your password again to change the UPI ID.'
              : err is LiveDropException
                  ? err.message
                  : 'Could not save your payment settings. Try again.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _saveUpi() async {
    await widget.repository.updateUpiSettings(
      upiEnabled: _upiEnabled,
      upiVpa: _upiVpaController.text.trim(),
      upiDisplayName: _upiDisplayNameController.text.trim().isEmpty
          ? null
          : _upiDisplayNameController.text.trim(),
      paymentInstructions: _instructionsController.text.trim().isEmpty
          ? null
          : _instructionsController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        title: const Text(
          'Payment & UPI Settings',
          style: TextStyle(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: AppColors.obsidian,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18, color: AppColors.textPrimary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.goldPrimary),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Direct UPI Architecture Information Card
                    Container(
                      padding: const EdgeInsets.all(16.0),
                      decoration: BoxDecoration(
                        color: AppColors.emeraldTint,
                        borderRadius: BorderRadius.circular(12.0),
                        border: Border.all(color: AppColors.emerald.withValues(alpha: 0.3)),
                      ),
                      child: const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.shield_outlined, color: AppColors.emerald, size: 20),
                              SizedBox(width: 8),
                              Text(
                                'Direct Peer-to-Peer UPI Rail',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.emerald,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Buyers pay directly into your personal or business UPI-linked bank account. '
                            'LiveDrop never custodies your money and charges zero gateway fees. '
                            'You inspect your bank transaction history to manually verify receipt.',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // UPI Feature Toggle Card
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: AppTheme.cardDecoration(),
                      child: SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text(
                          'Accept UPI Payments',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        subtitle: const Text(
                          'Allow buyers to pay via Google Pay, PhonePe, Paytm, BHIM, etc.',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                        value: _upiEnabled,
                        activeThumbColor: AppColors.goldPrimary,
                        activeTrackColor: AppColors.goldMuted,
                        inactiveThumbColor: AppColors.textMuted,
                        inactiveTrackColor: AppColors.cardBorder,
                        onChanged: (val) {
                          BoutiqueHaptics.selection();
                          setState(() {
                            _upiEnabled = val;
                          });
                        },
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Authoritative UPI ID (VPA) Field
                    const Text(
                      'Authoritative UPI ID (VPA) *',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _upiVpaController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'e.g. boutique@oksbi or artisan@upi',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.obsidianSurface,
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
                        prefixIcon: const Icon(Icons.payment, color: AppColors.goldPrimary),
                        helperText: 'Dynamic QR codes and payment links will route to this exact VPA.',
                        helperStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) {
                          return 'UPI ID is required to receive payments.';
                        }
                        if (!_vpaRegex.hasMatch(val.trim())) {
                          return 'Please enter a valid UPI format (e.g. name@bank).';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 20),

                    // Payee Display Name Field
                    const Text(
                      'Payee Display Name',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _upiDisplayNameController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      decoration: InputDecoration(
                        hintText: 'e.g. Mother\'s Boutique Official',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.obsidianSurface,
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
                        prefixIcon: const Icon(Icons.storefront, color: AppColors.goldPrimary),
                        helperText: 'Displayed to buyers on the payment QR screen.',
                        helperStyle: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Optional Payment Instructions
                    const Text(
                      'Optional Payment Note',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextFormField(
                      controller: _instructionsController,
                      style: const TextStyle(color: AppColors.textPrimary),
                      maxLines: 2,
                      decoration: InputDecoration(
                        hintText: 'e.g. Please mention your LiveDrop reference in the payment note.',
                        hintStyle: const TextStyle(color: AppColors.textMuted),
                        filled: true,
                        fillColor: AppColors.obsidianSurface,
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
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Error Message Banner
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.crimsonTint,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.crimson),
                        ),
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Color(0xFFFCA5A5), fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    if (_dropIsLive) ...[
                      Container(
                        key: const Key('payment-settings-live-warning'),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppColors.amberTint,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.amber),
                        ),
                        child: const Text(
                          'A drop is live. Turning UPI off stops new orders immediately, and a new UPI ID '
                          'applies to every payment buyers start from now on.',
                          style: TextStyle(color: AppColors.amber, fontSize: 13),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // Save Button
                    BounceableButton(
                      variant: ButtonVariant.goldGradient,
                      height: 50,
                      isLoading: _isSaving,
                      onPressed: _isSaving ? null : _saveSettings,
                      text: 'Save Payment Settings',
                      icon: Icons.save_outlined,
                    ),
                    if (_recentChanges.isNotEmpty) ...[
                      const SizedBox(height: 28),
                      const Text(
                        'Recent changes to your payment details',
                        style: TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      for (final change in _recentChanges)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '${DateFormat('d MMM, hh:mm a').format(change.changedAt.toLocal())} \u00b7 '
                            '${change.fieldLabel}: ${change.oldValue ?? '-'} \u2192 ${change.newValue ?? '-'}'
                            '${change.changedByRole == 'authenticated' ? '' : ' (by LiveDrop support)'}',
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
                          ),
                        ),
                      const Text(
                        'If you did not make a change listed here, change your password and contact LiveDrop support.',
                        style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                      ),
                    ],
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
    );
  }
}
