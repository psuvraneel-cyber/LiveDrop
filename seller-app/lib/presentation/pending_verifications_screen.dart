import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../data/repositories/seller_repository.dart';
import '../domain/models/models.dart';

/// LiveDrop Seller Mobile App — Pending Payment Verifications Screen (TASK-2.4B)
///
/// Enables sellers to review unverified buyer payment claims (UTRs), cross-check
/// their actual bank/UPI transaction history, and submit manual verification or rejection.
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

  @override
  void initState() {
    super.initState();
    _loadVerifications();
  }

  Future<void> _loadVerifications() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final attempts = await widget.repository.getPendingVerifications();
      setState(() {
        _pendingAttempts = attempts;
        _isLoading = false;
      });
    } catch (err) {
      setState(() {
        _errorMessage = err.toString();
        _isLoading = false;
      });
    }
  }

  String _formatPaisa(int paisa) {
    final inr = paisa / 100.0;
    return '₹${inr.toStringAsFixed(2)}';
  }

  Future<void> _verifyPayment(PaymentAttempt attempt) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Manual Verification'),
        content: Text(
          'Have you verified receipt of ${_formatPaisa(attempt.expectedAmountPaisa)} '
          'with UTR "${attempt.buyerSubmittedUtr}" in your UPI/bank app?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, Payment Verified'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      _processingIds.add(attempt.id);
    });

    try {
      await widget.repository.verifyManualUpiPayment(attempt.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment for ${attempt.orderCode ?? 'Order'} verified successfully!'),
            backgroundColor: const Color(0xFF16A34A),
          ),
        );
      }
      await _loadVerifications();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: $err'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingIds.remove(attempt.id);
        });
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
          title: const Text('Reject Payment Claim'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Please select the reason why this payment claim cannot be verified:',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selectedReason,
                decoration: const InputDecoration(
                  labelText: 'Rejection Reason',
                  border: OutlineInputBorder(),
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
                    setDialogState(() {
                      selectedReason = val;
                    });
                  }
                },
              ),
              if (selectedReason == 'other') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: customReasonController,
                  decoration: const InputDecoration(
                    labelText: 'Specify Reason',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFDC2626),
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

    setState(() {
      _processingIds.add(attempt.id);
    });

    try {
      await widget.repository.rejectManualUpiPayment(attempt.id, finalReason);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment claim for ${attempt.orderCode ?? 'Order'} marked as rejected.'),
            backgroundColor: const Color(0xFFD97706),
          ),
        );
      }
      await _loadVerifications();
    } catch (err) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Rejection failed: $err'),
            backgroundColor: const Color(0xFFDC2626),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _processingIds.remove(attempt.id);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify UPI Payments'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0F172A),
        elevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVerifications,
            tooltip: 'Refresh Pending Payments',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadVerifications,
              child: _pendingAttempts.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: const [
                          Icon(Icons.check_circle_outline, size: 64, color: Color(0xFF16A34A)),
                          SizedBox(height: 16),
                          Text(
                            'All Payments Verified!',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'No pending buyer payment claims awaiting verification.',
                            style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16.0),
                      itemCount: _pendingAttempts.length + 1,
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          // Instructional Banner
                          return Container(
                            margin: const EdgeInsets.bottom(16.0),
                            padding: const EdgeInsets.all(14.0),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(8.0),
                              border: Border.all(color: const Color(0xFFFDE68A)),
                            ),
                            child: Row(
                              children: const [
                                Icon(Icons.info_outline, color: Color(0xFF92400E), size: 20),
                                SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Check your bank account/UPI app before confirming. '
                                    'Manual verification records an immutable transaction on the order ledger.',
                                    style: TextStyle(
                                      color: Color(0xFF92400E),
                                      fontSize: 13,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }

                        final attempt = _pendingAttempts[index - 1];
                        final isProcessing = _processingIds.contains(attempt.id);

                        return Card(
                          margin: const EdgeInsets.only(bottom: 16.0),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12.0),
                            side: const BorderSide(color: Color(0xFFE2E8F0)),
                          ),
                          elevation: 1,
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Order & Buyer Header
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF1F5F9),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        attempt.orderCode ?? 'Order',
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'monospace',
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 3,
                                      ),
                                      decoration: BoxDecoration(
                                        color: attempt.paymentType == 'advance'
                                            ? const Color(0xFFFEF3C7)
                                            : const Color(0xFFDCFCE7),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        attempt.paymentType.toUpperCase(),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 11,
                                          color: attempt.paymentType == 'advance'
                                              ? const Color(0xFF78350F)
                                              : const Color(0xFF14532D),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),

                                // Buyer & Expected Amount
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      'Buyer: ${attempt.buyerName ?? 'Customer'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 15,
                                      ),
                                    ),
                                    Text(
                                      _formatPaisa(attempt.expectedAmountPaisa),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 18,
                                        color: Color(0xFF16A34A),
                                      ),
                                    ),
                                  ],
                                ),
                                const Divider(height: 20),

                                // Submitted UTR Details
                                Row(
                                  children: [
                                    const Text(
                                      'Submitted UTR: ',
                                      style: TextStyle(color: Color(0xFF64748B), fontSize: 13),
                                    ),
                                    SelectableText(
                                      attempt.buyerSubmittedUtr ?? 'Pending Submission',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'monospace',
                                        fontSize: 14,
                                        color: Color(0xFF0F172A),
                                      ),
                                    ),
                                    const Spacer(),
                                    IconButton(
                                      icon: const Icon(Icons.copy, size: 16),
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Copy UTR',
                                      onPressed: attempt.buyerSubmittedUtr != null
                                          ? () {
                                              Clipboard.setData(
                                                ClipboardData(text: attempt.buyerSubmittedUtr!),
                                              );
                                              ScaffoldMessenger.of(context).showSnackBar(
                                                const SnackBar(
                                                  content: Text('UTR copied to clipboard'),
                                                  duration: Duration(seconds: 1),
                                                ),
                                              );
                                            }
                                          : null,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 6),

                                // Reference & Timestamp
                                Text(
                                  'Reference: ${attempt.transactionReference}',
                                  style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                ),
                                const SizedBox(height: 16),

                                // Verification Actions
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: const Color(0xFFDC2626),
                                          side: const BorderSide(color: Color(0xFFDC2626)),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: isProcessing
                                            ? null
                                            : () => _rejectPayment(attempt),
                                        child: const Text('Payment Not Found'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF16A34A),
                                          foregroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                        ),
                                        onPressed: isProcessing
                                            ? null
                                            : () => _verifyPayment(attempt),
                                        child: isProcessing
                                            ? const SizedBox(
                                                width: 18,
                                                height: 18,
                                                child: CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<Color>(Colors.white),
                                                ),
                                              )
                                            : const Text(
                                                'Verify Payment',
                                                style: TextStyle(fontWeight: FontWeight.bold),
                                              ),
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
