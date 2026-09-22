import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/bounceable_button.dart';
import '../data/repositories/seller_repository.dart';
import '../domain/models/models.dart';
import 'common/skeleton_loaders.dart';

/// Screen 7: Luxury Boutique Payment Verification Screen
class PendingVerificationsScreen extends StatefulWidget {
  final SellerRepository repository;

  const PendingVerificationsScreen({super.key, required this.repository});

  @override
  State<PendingVerificationsScreen> createState() => _PendingVerificationsScreenState();
}

class _PendingVerificationsScreenState extends State<PendingVerificationsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<PaymentAttempt> _pendingAttempts = [];
  final Set<String> _processingIds = {};
  final Map<String, TextEditingController> _remarksControllers = {};

  @override
  void initState() {
    super.initState();
    _loadVerifications();
  }

  @override
  void dispose() {
    for (final c in _remarksControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadVerifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final attempts = await widget.repository.getPendingVerifications();
      for (final a in attempts) {
        if (!_remarksControllers.containsKey(a.id)) {
          _remarksControllers[a.id] = TextEditingController();
        }
      }

      if (mounted) {
        setState(() {
          _pendingAttempts = attempts;
          _isLoading = false;
        });
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _errorMessage = err.toString();
          _isLoading = false;
        });
      }
    }
  }

  String _formatPaisa(int paisa) {
    final inr = (paisa / 100).toStringAsFixed(0);
    return '₹$inr';
  }

  Future<void> _verifyPayment(PaymentAttempt attempt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.obsidianSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: const Text('Confirm Payment Receipt', style: TextStyle(color: Colors.white)),
        content: Text(
          'Confirm that ${_formatPaisa(attempt.expectedAmountPaisa)} was received in your boutique UPI account for order #${attempt.orderCode ?? "Order"}?',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.goldPrimary,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Receipt'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _processingIds.add(attempt.id));

    try {
      await widget.repository.verifyManualUpiPayment(attempt.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment verified for Order #${attempt.orderCode ?? "Order"}!'),
            backgroundColor: AppColors.emerald,
          ),
        );
      }
      await _loadVerifications();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: $err'),
            backgroundColor: AppColors.crimson,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(attempt.id));
      }
    }
  }

  Future<void> _rejectPayment(PaymentAttempt attempt) async {
    String selectedReason = 'payment_not_found';
    final customReasonController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.obsidianSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.cardBorder),
          ),
          title: const Text('Reject Payment Claim', style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please select the reason why this payment claim cannot be verified:',
                style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedReason,
                dropdownColor: AppColors.obsidianSurface,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Rejection Reason',
                ),
                items: const [
                  DropdownMenuItem(
                    value: 'payment_not_found',
                    child: Text('Payment not found in bank statement'),
                  ),
                  DropdownMenuItem(
                    value: 'amount_mismatch',
                    child: Text('Amount received does not match'),
                  ),
                  DropdownMenuItem(
                    value: 'wrong_reference',
                    child: Text('Incorrect UTR / Reference ID'),
                  ),
                  DropdownMenuItem(
                    value: 'other',
                    child: Text('Other reason'),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setDialogState(() => selectedReason = val);
                  }
                },
              ),
              if (selectedReason == 'other') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: customReasonController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(labelText: 'Specify Reason'),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.crimson,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Reject Claim'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    final finalReason = selectedReason == 'other' && customReasonController.text.trim().isNotEmpty
        ? customReasonController.text.trim()
        : selectedReason;

    setState(() => _processingIds.add(attempt.id));

    try {
      await widget.repository.rejectManualUpiPayment(attempt.id, finalReason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment claim for #${attempt.orderCode ?? "Order"} rejected.'),
            backgroundColor: AppColors.amber,
          ),
        );
      }
      await _loadVerifications();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rejection failed: $err'),
            backgroundColor: AppColors.crimson,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _processingIds.remove(attempt.id));
      }
    }
  }

  void _showScreenshotModal() {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: AppColors.obsidianSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Payment Screenshot', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Container(
                height: 280,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppColors.obsidianElevated,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_rounded, size: 48, color: AppColors.goldPrimary),
                      SizedBox(height: 8),
                      Text('Google Pay / PhonePe UPI Receipt', style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: _isLoading
          ? const SafeArea(child: VerificationsSkeleton())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: AppColors.crimson),
                        const SizedBox(height: 16),
                        const Text(
                          'Failed to load verifications',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton.icon(
                          onPressed: _loadVerifications,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  color: AppColors.goldPrimary,
                  backgroundColor: AppColors.obsidianSurface,
                  onRefresh: _loadVerifications,
                  child: _pendingAttempts.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.verified_user_outlined, size: 64, color: AppColors.emerald),
                              SizedBox(height: 16),
                              Text(
                                'All Payments Verified!',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'No pending buyer payment claims awaiting verification.',
                                style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16.0),
                          itemCount: _pendingAttempts.length,
                          itemBuilder: (context, index) {
                            final attempt = _pendingAttempts[index];
                            final isProcessing = _processingIds.contains(attempt.id);
                            final remarksCtrl = _remarksControllers[attempt.id] ?? TextEditingController();

                            return Container(
                              margin: const EdgeInsets.only(bottom: 20),
                              decoration: AppTheme.cardDecoration(),
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Order Info Card (Thumbnail, Code, Buyer, Amount, Status)
                                    Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(8),
                                          child: Container(
                                            width: 52,
                                            height: 52,
                                            color: AppColors.obsidianElevated,
                                            child: const Icon(
                                              Icons.checkroom_rounded,
                                              color: AppColors.goldPrimary,
                                              size: 26,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                attempt.orderCode != null ? '#${attempt.orderCode}' : '#Order',
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                  fontSize: 15,
                                                  color: AppColors.textPrimary,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                attempt.buyerName ?? 'Customer',
                                                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                '${_formatPaisa(attempt.expectedAmountPaisa)} Advance Payment',
                                                style: const TextStyle(
                                                  fontSize: 12,
                                                  color: AppColors.goldPrimary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: AppTheme.pillDecoration(
                                            color: AppColors.amber,
                                            tintColor: AppColors.amberTint,
                                          ),
                                          child: const Text(
                                            'Verifying',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.amber,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    const Divider(color: AppColors.cardBorder, height: 1),
                                    const SizedBox(height: 14),

                                    // Buyer's UTR Details Section
                                    const Text(
                                      "Buyer's UTR Details",
                                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.textPrimary),
                                    ),
                                    const SizedBox(height: 8),

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
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text('UTR Number', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                                  const SizedBox(height: 2),
                                                  SelectableText(
                                                    attempt.buyerSubmittedUtr ?? (attempt.transactionReference.isNotEmpty ? attempt.transactionReference : 'Pending submission'),
                                                    style: const TextStyle(
                                                      fontFamily: 'monospace',
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                      color: AppColors.textPrimary,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              InkWell(
                                                onTap: () {
                                                  final utr = attempt.buyerSubmittedUtr ?? (attempt.transactionReference.isNotEmpty ? attempt.transactionReference : 'N/A');
                                                  Clipboard.setData(ClipboardData(text: utr));
                                                  ScaffoldMessenger.of(context).showSnackBar(
                                                    const SnackBar(
                                                      content: Text('UTR copied to clipboard'),
                                                      backgroundColor: AppColors.emerald,
                                                      duration: Duration(seconds: 1),
                                                    ),
                                                  );
                                                },
                                                child: Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                  decoration: BoxDecoration(
                                                    color: AppColors.goldMuted,
                                                    borderRadius: BorderRadius.circular(6),
                                                    border: Border.all(color: AppColors.goldPrimary, width: 0.8),
                                                  ),
                                                  child: const Row(
                                                    children: [
                                                      Icon(Icons.copy, size: 12, color: AppColors.goldPrimary),
                                                      SizedBox(width: 4),
                                                      Text('Copy', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.goldPrimary)),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Row(
                                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                            children: [
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Text('Amount', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    _formatPaisa(attempt.expectedAmountPaisa),
                                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.emerald),
                                                  ),
                                                ],
                                              ),
                                              Column(
                                                crossAxisAlignment: CrossAxisAlignment.end,
                                                children: [
                                                  const Text('Paid on', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    attempt.buyerClaimedAt != null
                                                        ? attempt.buyerClaimedAt!.toLocal().toString().substring(0, 16)
                                                        : attempt.createdAt.toLocal().toString().substring(0, 16),
                                                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          // Screenshot Tile
                                          Row(
                                            children: [
                                              const Text('Screenshot: ', style: TextStyle(fontSize: 11, color: AppColors.textMuted)),
                                              InkWell(
                                                onTap: _showScreenshotModal,
                                                child: const Row(
                                                  children: [
                                                    Icon(Icons.image_outlined, size: 14, color: AppColors.goldPrimary),
                                                    SizedBox(width: 4),
                                                    Text(
                                                      'Tap to view',
                                                      style: TextStyle(fontSize: 12, color: AppColors.goldPrimary, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 14),

                                    // Remarks (Optional)
                                    TextField(
                                      controller: remarksCtrl,
                                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                                      decoration: const InputDecoration(
                                        labelText: 'Remarks (optional)',
                                        hintText: 'Add a note...',
                                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                      ),
                                    ),
                                    const SizedBox(height: 16),

                                    // Dual Action Buttons: Reject (Red Outline) | Verify Payment (Gold Gradient)
                                    Row(
                                      children: [
                                        Expanded(
                                          child: BounceableButton(
                                            onPressed: isProcessing ? null : () => _rejectPayment(attempt),
                                            variant: ButtonVariant.crimsonOutline,
                                            height: 44,
                                            text: 'Reject',
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: BounceableButton(
                                            onPressed: isProcessing ? null : () => _verifyPayment(attempt),
                                            isLoading: isProcessing,
                                            variant: ButtonVariant.goldGradient,
                                            height: 44,
                                            text: 'Verify Payment',
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
    );
  }
}
