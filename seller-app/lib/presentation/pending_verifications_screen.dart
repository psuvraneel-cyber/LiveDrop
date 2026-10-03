import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../core/errors/seller_error_messages.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_theme.dart';
import '../core/theme/bounceable_button.dart';
import '../core/utils/phone_utils.dart';
import '../core/utils/url_launcher_helper.dart';
import '../data/realtime/seller_live_store.dart';
import '../data/repositories/seller_repository.dart';
import '../domain/models/models.dart';
import 'common/live_refresh.dart';
import 'common/skeleton_loaders.dart';

/// Screen 7: Luxury Boutique Payment Verification Screen
///
/// Shows, in this order:
/// 1. **Refunds owed** — late payments verified after the piece was resold
///    (SA-PAY-004). The seller refunds the buyer and records the reference.
/// 2. **Payment claims** — overdue claims first, labelled "Overdue — verify or
///    reject" (SA-PAY-003): the server keeps them verifiable, so they never
///    disappear on their own.
///
/// The list reloads by itself when the [SellerLiveStore] revision changes
/// (SA-RT-001).
class PendingVerificationsScreen extends StatefulWidget {
  final SellerRepository repository;
  final SellerLiveStore? liveStore;

  const PendingVerificationsScreen({
    super.key,
    required this.repository,
    this.liveStore,
  });

  @override
  State<PendingVerificationsScreen> createState() => _PendingVerificationsScreenState();
}

class _PendingVerificationsScreenState extends State<PendingVerificationsScreen>
    with SellerLiveRefreshMixin<PendingVerificationsScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<PaymentAttempt> _pendingAttempts = [];
  List<OwedRefund> _refundsOwed = [];
  bool _refundsUnavailable = false;
  final Set<String> _processingIds = {};
  final Set<String> _refundProcessingIds = {};
  final Map<String, TextEditingController> _remarksControllers = {};
  final ScrollController _scrollController = ScrollController();
  String? _highlightedRefundOrderId;
  int _loadSequence = 0;

  @override
  SellerLiveStore? get liveStore => widget.liveStore;

  @override
  void onLiveRevision() {
    _loadVerifications(silent: true);
  }

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
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadVerifications({bool silent = false}) async {
    final sequence = ++_loadSequence;
    if (!silent) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    List<OwedRefund>? refunds;
    try {
      refunds = await widget.repository.getRefundsOwed();
    } catch (_) {
      refunds = null; // the claims queue must still load (older server, offline…)
    }

    try {
      final attempts = await widget.repository.getPendingVerifications();
      if (!mounted || sequence != _loadSequence) return;
      for (final a in attempts) {
        if (!_remarksControllers.containsKey(a.id)) {
          _remarksControllers[a.id] = TextEditingController();
        }
      }

      setState(() {
        _pendingAttempts = _sortClaims(attempts, DateTime.now());
        _refundsOwed = refunds ?? _refundsOwed;
        _refundsUnavailable = refunds == null;
        _isLoading = false;
        _errorMessage = null;
      });
    } catch (err) {
      if (!mounted || sequence != _loadSequence) return;
      // A failed background (live) reload keeps what is already on screen.
      if (silent && _errorMessage == null && !_isLoading) return;
      setState(() {
        _errorMessage = 'Check your connection, then tap Retry.';
        _isLoading = false;
      });
    }
  }

  /// Overdue claims first (oldest deadline first), then the rest in the
  /// order the server returned them (oldest claim first).
  static List<PaymentAttempt> _sortClaims(List<PaymentAttempt> attempts, DateTime now) {
    final overdue = attempts.where((a) => a.isOverdue(now)).toList()
      ..sort((a, b) => a.verificationDeadline!.compareTo(b.verificationDeadline!));
    final onTime = attempts.where((a) => !a.isOverdue(now)).toList();
    return [...overdue, ...onTime];
  }

  Future<void> _refreshAfterMutation() async {
    final store = widget.liveStore;
    if (store != null) {
      store.requestRefresh(immediate: true);
    } else {
      await _loadVerifications(silent: true);
    }
  }

  String _formatPaisa(int paisa) {
    final inr = (paisa / 100).toStringAsFixed(0);
    return '₹$inr';
  }

  static int? _asInt(Object? value) => value is num ? value.toInt() : null;

  static String _formatRemaining(Duration remaining) {
    if (remaining.inMinutes < 1) return 'less than a minute';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    if (hours == 0) return '${minutes}m';
    return '${hours}h ${minutes.toString().padLeft(2, '0')}m';
  }

  Future<void> _verifyPayment(PaymentAttempt attempt) async {
    final amount = _formatPaisa(attempt.expectedAmountPaisa);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.obsidianSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: const Text('Confirm Payment Receipt', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Confirm that $amount was received in your boutique UPI account for order #${attempt.orderCode ?? "Order"}?',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            if (attempt.isLateClaim) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.crimsonTint,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.crimson.withValues(alpha: 0.6)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.warning_amber_rounded, color: AppColors.crimson, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Late payment: the buyer paid after the hold had expired. '
                        'If this garment has already been sold to someone else, the payment '
                        'is still recorded and you must refund $amount to the buyer.',
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13, height: 1.35),
                      ),
                    ),
                  ],
                ),
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
              backgroundColor: AppColors.goldPrimary,
              foregroundColor: Colors.black,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Confirm Receipt'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _processingIds.add(attempt.id));

    try {
      final result = await widget.repository.verifyManualUpiPayment(attempt.id);
      if (!mounted) return;
      if (result['refund_required'] == true) {
        final refundPaisa = _asInt(result['refund_amount_paisa']) ??
            _asInt(result['amount_paisa']) ??
            attempt.expectedAmountPaisa;
        final orderId = result['order_id'] as String? ?? attempt.orderId;
        await _refreshAfterMutation();
        if (!mounted) return;
        final showRefunds = await _showRefundRequiredDialog(attempt, refundPaisa);
        if (!mounted) return;
        if (showRefunds) {
          setState(() => _highlightedRefundOrderId = orderId);
          if (_scrollController.hasClients) {
            await _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        }
      } else {
        final lateConfirmed = attempt.isLateClaim && result['inventory_available'] == true;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              lateConfirmed
                  ? 'Late payment verified — Order #${attempt.orderCode ?? "Order"} is confirmed.'
                  : 'Payment verified for Order #${attempt.orderCode ?? "Order"}!',
            ),
            backgroundColor: AppColors.emerald,
          ),
        );
        await _refreshAfterMutation();
      }
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(SellerErrorMessages.verifyPayment(err)),
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

  /// Blocking dialog after a late payment was verified for a piece that had
  /// been resold: the seller owes the buyer a refund. Returns true when the
  /// seller wants to jump to the "Refunds owed" list.
  Future<bool> _showRefundRequiredDialog(PaymentAttempt attempt, int refundPaisa) async {
    final amount = _formatPaisa(refundPaisa);
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.obsidianSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: AppColors.crimson),
          ),
          title: Row(
            children: [
              const Icon(Icons.currency_rupee_rounded, color: AppColors.crimson),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Refund $amount to the buyer',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Text(
            'The payment for order #${attempt.orderCode ?? "Order"} was recorded, but the garment '
            'was no longer available — it had been sold after the hold expired.\n\n'
            'You must refund $amount to ${attempt.buyerName ?? "the buyer"}. After sending it, '
            'open Refunds owed and tap "Mark refunded" with the UPI reference.',
            style: const TextStyle(color: AppColors.textSecondary, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Close', style: TextStyle(color: AppColors.textMuted)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.goldPrimary,
                foregroundColor: Colors.black,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('View refunds owed'),
            ),
          ],
        ),
      ),
    );
    return result == true;
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

    if (confirmed != true || !mounted) return;

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
      await _refreshAfterMutation();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(SellerErrorMessages.rejectPayment(err)),
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

  Future<void> _contactBuyerAboutRefund(OwedRefund refund) async {
    final amount = _formatPaisa(refund.refundAmountPaisa);
    await UrlLauncherHelper.launchWhatsApp(
      context: context,
      phone: PhoneUtils.whatsAppDigits(refund.buyerPhone),
      message: 'Hi ${refund.buyerName}, about your LiveDrop order #${refund.orderCode}: '
          'your payment of $amount reached us after the piece had already been sold, '
          'so we are refunding $amount to you. We will share the UPI reference once it is sent. '
          'Sorry for the trouble!',
    );
  }

  Future<void> _markRefunded(OwedRefund refund) async {
    final amount = _formatPaisa(refund.refundAmountPaisa);
    final entry = await showDialog<_RefundEntry>(
      context: context,
      builder: (_) => _MarkRefundedDialog(refund: refund, amountLabel: amount),
    );
    if (entry == null || !mounted) return;

    setState(() => _refundProcessingIds.add(refund.orderId));
    try {
      await widget.repository.recordRefund(
        refund.orderId,
        entry.reference,
        note: entry.note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Refund of $amount recorded for #${refund.orderCode}.'),
          backgroundColor: AppColors.emerald,
        ),
      );
      setState(() {
        _refundsOwed = _refundsOwed.where((r) => r.orderId != refund.orderId).toList();
        if (_highlightedRefundOrderId == refund.orderId) _highlightedRefundOrderId = null;
      });
      await _refreshAfterMutation();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(SellerErrorMessages.recordRefund(err)),
            backgroundColor: AppColors.crimson,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _refundProcessingIds.remove(refund.orderId));
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
                  child: ListView(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16.0),
                    children: [
                      if (_refundsOwed.isNotEmpty) ..._buildRefundsSection(),
                      if (_refundsUnavailable && _refundsOwed.isEmpty) _buildRefundsUnavailableNotice(),
                      if (_pendingAttempts.isEmpty)
                        _buildEmptyClaims()
                      else ...[
                        if (_refundsOwed.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12, top: 4),
                            child: Text(
                              'Payment claims',
                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
                            ),
                          ),
                        ..._pendingAttempts.map(_buildClaimCard),
                      ],
                    ],
                  ),
                ),
    );
  }

  Widget _buildEmptyClaims() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 48),
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
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildRefundsUnavailableNotice() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: AppTheme.cardDecoration(borderColor: AppColors.amber.withValues(alpha: 0.6)),
      child: const Row(
        children: [
          Icon(Icons.info_outline_rounded, color: AppColors.amber, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              "Couldn't load refunds owed. Pull down to try again.",
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildRefundsSection() {
    final totalPaisa = _refundsOwed.fold<int>(0, (sum, r) => sum + r.refundAmountPaisa);
    return [
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          children: [
            const Icon(Icons.currency_rupee_rounded, color: AppColors.crimson, size: 20),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Refunds owed (${_refundsOwed.length})',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
              ),
            ),
            Text(
              _formatPaisa(totalPaisa),
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: AppColors.crimson),
            ),
          ],
        ),
      ),
      ..._refundsOwed.map(_buildRefundCard),
      const SizedBox(height: 8),
    ];
  }

  Widget _buildRefundCard(OwedRefund refund) {
    final isProcessing = _refundProcessingIds.contains(refund.orderId);
    final highlighted = refund.orderId == _highlightedRefundOrderId;
    final since = refund.refundRequiredAt != null
        ? DateFormat('d MMM, hh:mm a').format(refund.refundRequiredAt!.toLocal())
        : null;

    return Container(
      key: ValueKey('refund-${refund.orderId}'),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: AppTheme.cardDecoration(
        borderColor: highlighted ? AppColors.goldPrimary : AppColors.crimson.withValues(alpha: 0.55),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '#${refund.orderCode}',
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      refund.buyerName,
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: AppTheme.pillDecoration(color: AppColors.crimson, tintColor: AppColors.crimsonTint),
                child: const Text(
                  'Refund owed',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.crimson),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '${_formatPaisa(refund.refundAmountPaisa)} to refund',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: AppColors.crimson),
          ),
          const SizedBox(height: 6),
          Text(
            refund.reasonLabel,
            style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, height: 1.35),
          ),
          if (since != null) ...[
            const SizedBox(height: 4),
            Text(
              'Owed since $since',
              style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: BounceableButton(
                  onPressed: isProcessing ? null : () => _contactBuyerAboutRefund(refund),
                  variant: ButtonVariant.darkCard,
                  height: 42,
                  icon: Icons.chat,
                  text: 'WhatsApp buyer',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BounceableButton(
                  onPressed: isProcessing ? null : () => _markRefunded(refund),
                  isLoading: isProcessing,
                  variant: ButtonVariant.goldGradient,
                  height: 42,
                  text: 'Mark refunded',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildClaimCard(PaymentAttempt attempt) {
    final now = DateTime.now();
    final isProcessing = _processingIds.contains(attempt.id);
    final remarksCtrl = _remarksControllers[attempt.id] ?? TextEditingController();
    final isOverdue = attempt.isOverdue(now);
    final deadline = attempt.verificationDeadline;

    return Container(
      key: ValueKey('claim-${attempt.id}'),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: AppTheme.cardDecoration(
        borderColor: isOverdue ? AppColors.crimson : AppColors.cardBorder,
      ),
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
                    color: attempt.isLateClaim ? AppColors.crimson : AppColors.amber,
                    tintColor: attempt.isLateClaim ? AppColors.crimsonTint : AppColors.amberTint,
                  ),
                  child: Text(
                    attempt.isLateClaim ? 'Late Claim' : 'Verifying',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: attempt.isLateClaim ? AppColors.crimson : AppColors.amber,
                    ),
                  ),
                ),
              ],
            ),
            if (isOverdue) ...[
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.crimsonTint,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.crimson, width: 0.8),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.schedule_rounded, color: AppColors.crimson, size: 16),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Overdue — verify or reject',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.crimson),
                      ),
                    ),
                  ],
                ),
              ),
            ] else if (deadline != null) ...[
              const SizedBox(height: 10),
              Text(
                'Verify within ${_formatRemaining(deadline.difference(now))}',
                style: const TextStyle(fontSize: 12, color: AppColors.amber, fontWeight: FontWeight.w600),
              ),
            ],
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
  }
}

class _RefundEntry {
  final String reference;
  final String? note;

  const _RefundEntry(this.reference, this.note);
}

/// Asks for the UPI reference of the refund (validated like `record_refund`:
/// 4–64 letters, digits, spaces or `. _ / -`) and an optional note.
class _MarkRefundedDialog extends StatefulWidget {
  final OwedRefund refund;
  final String amountLabel;

  const _MarkRefundedDialog({required this.refund, required this.amountLabel});

  @override
  State<_MarkRefundedDialog> createState() => _MarkRefundedDialogState();
}

class _MarkRefundedDialogState extends State<_MarkRefundedDialog> {
  final _formKey = GlobalKey<FormState>();
  final _referenceController = TextEditingController();
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _referenceController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final note = _noteController.text.trim();
    Navigator.of(context).pop(
      _RefundEntry(_referenceController.text.trim(), note.isEmpty ? null : note),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.obsidianSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppColors.cardBorder),
      ),
      title: Text(
        'Mark #${widget.refund.orderCode} refunded',
        style: const TextStyle(color: Colors.white),
      ),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Enter the UPI reference of the ${widget.amountLabel} refund you sent to '
                '${widget.refund.buyerName}.',
                style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _referenceController,
                style: const TextStyle(color: Colors.white),
                autovalidateMode: AutovalidateMode.onUserInteraction,
                decoration: const InputDecoration(
                  labelText: 'Refund UPI reference (UTR)',
                  hintText: 'e.g. 412345678901',
                ),
                validator: (value) => SellerRepository.validateRefundReference(value ?? ''),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _noteController,
                style: const TextStyle(color: Colors.white),
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Note (optional)'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.goldPrimary,
            foregroundColor: Colors.black,
          ),
          onPressed: _submit,
          child: const Text('Save refund'),
        ),
      ],
    );
  }
}
