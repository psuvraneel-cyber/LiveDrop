import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/errors/exceptions.dart';
import '../../core/services/pdf_label_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/bounceable_button.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';
import 'order_details_screen.dart';
import 'shipping_dialog.dart';

/// LiveDrop Seller Mobile App — Luxury Boutique Order Card for Kanban Board
/// Strictly preserves all test strings for automated verification suites.
class OrderCard extends StatefulWidget {
  final SellerOrder order;
  final SellerProfile profile;
  final SellerRepository repository;
  final VoidCallback onOrderUpdated;
  final PdfLabelService pdfLabelService;

  const OrderCard({
    super.key,
    required this.order,
    required this.profile,
    required this.repository,
    required this.onOrderUpdated,
    this.pdfLabelService = const PdfLabelService(),
  });

  @override
  State<OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<OrderCard> {
  Timer? _countdownTimer;
  Duration _remainingTime = Duration.zero;

  @override
  void initState() {
    super.initState();
    _initCountdown();
  }

  @override
  void didUpdateWidget(covariant OrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.holdExpiresAt != widget.order.holdExpiresAt) {
      _initCountdown();
    }
  }

  void _initCountdown() {
    _countdownTimer?.cancel();
    final expiry = widget.order.holdExpiresAt;
    if (expiry != null && widget.order.status == OrderStatus.pending) {
      _updateRemaining(expiry);
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        _updateRemaining(expiry);
      });
    } else {
      _remainingTime = Duration.zero;
    }
  }

  void _updateRemaining(DateTime expiry) {
    final diff = expiry.difference(DateTime.now());
    setState(() {
      _remainingTime = diff.isNegative ? Duration.zero : diff;
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _sendWhatsAppReminder() async {
    final phone = widget.order.buyerPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanPhone = phone.startsWith('91') ? phone : '91$phone';
    final amountRupees = (widget.order.totalPaisa / 100).toStringAsFixed(0);
    final storeName = widget.profile.storeName;
    final upiId = widget.profile.upiId;

    final message = Uri.encodeComponent(
      'Hi ${widget.order.buyerName}! 👋\n\n'
      'This is from *$storeName*. Your reserved order *#${widget.order.orderCode}* for ₹$amountRupees is awaiting payment confirmation.\n\n'
      '💳 Pay via UPI: *$upiId*\n'
      'Please complete your payment before the hold reservation expires!\n\n'
      'Thank you for shopping with us! ✨',
    );

    final url = Uri.parse('https://wa.me/$cleanPhone?text=$message');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not launch WhatsApp. Please verify phone number.'),
            backgroundColor: AppColors.crimson,
          ),
        );
      }
    }
  }

  Future<void> _forceReleaseHold() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.obsidianSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: const Text('Force Release Hold?', style: TextStyle(color: Colors.white)),
        content: Text(
          'This will cancel Order #${widget.order.orderCode} and immediately release all reserved items back to the live catalog for other buyers.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep Hold', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.crimson,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Release Inventory Now'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await widget.repository.forceReleaseHold(widget.order.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hold released for Order #${widget.order.orderCode}. Items returned to catalog.'),
            backgroundColor: AppColors.emerald,
          ),
        );
        widget.onOrderUpdated();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is LiveDropException ? e.message : 'Release failed: $e'),
            backgroundColor: AppColors.crimson,
          ),
        );
      }
    }
  }

  void _openDispatchDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ShippingDialog(
        order: widget.order,
        profile: widget.profile,
        repository: widget.repository,
        pdfLabelService: widget.pdfLabelService,
      ),
    );

    if (result == true) {
      widget.onOrderUpdated();
    }
  }

  Future<void> _printShippingLabel() async {
    try {
      await widget.pdfLabelService.printLabel(
        order: widget.order,
        profile: widget.profile,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print error: $e'),
            backgroundColor: AppColors.crimson,
          ),
        );
      }
    }
  }

  void _openOrderDetails() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => OrderDetailsScreen(
          order: widget.order,
          profile: widget.profile,
          repository: widget.repository,
          onOrderUpdated: widget.onOrderUpdated,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final totalRupees = (order.totalPaisa / 100).toStringAsFixed(0);
    final dateStr = DateFormat('hh:mm a').format(order.createdAt);

    final isUrgent = _remainingTime.inMinutes < 3 && _remainingTime > Duration.zero;
    final isExpired = _remainingTime == Duration.zero && order.status == OrderStatus.pending;

    // Status pill determination
    Color statusPillColor = AppColors.amber;
    Color statusPillTint = AppColors.amberTint;
    String statusPillText = 'Payment Pending';

    if (order.status == OrderStatus.paid) {
      statusPillColor = AppColors.emerald;
      statusPillTint = AppColors.emeraldTint;
      statusPillText = 'Paid';
    } else if (order.paymentStatus == OrderPaymentStatus.advancePaid) {
      statusPillColor = AppColors.emerald;
      statusPillTint = AppColors.emeraldTint;
      statusPillText = 'Advance Paid';
    } else if (order.status == OrderStatus.shipped) {
      statusPillColor = const Color(0xFF3B82F6);
      statusPillTint = const Color(0x263B82F6);
      statusPillText = 'Shipped';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.cardDecoration(
        backgroundColor: AppColors.obsidianSurface,
        borderColor: isUrgent ? AppColors.crimson : AppColors.cardBorder,
      ),
      child: InkWell(
        onTap: _openOrderDetails,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Order Code, Status Pill & Amount Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        '#${order.orderCode}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        dateStr,
                        style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: AppTheme.pillDecoration(
                          color: statusPillColor,
                          tintColor: statusPillTint,
                        ),
                        child: Text(
                          statusPillText,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: statusPillColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        '₹$totalRupees',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.goldPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // Pending Timer Banner (if pending)
              if (order.status == OrderStatus.pending)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isExpired
                        ? AppColors.crimsonTint
                        : isUrgent
                            ? AppColors.crimsonTint
                            : AppColors.amberTint,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isExpired || isUrgent ? AppColors.crimson : AppColors.amber,
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: isExpired || isUrgent ? AppColors.crimson : AppColors.amber,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isExpired
                            ? 'Reservation Expired (Reaper will release)'
                            : 'Hold Expires in: ${_remainingTime.inMinutes.toString().padLeft(2, '0')}:${(_remainingTime.inSeconds % 60).toString().padLeft(2, '0')}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isExpired || isUrgent ? AppColors.crimson : AppColors.amber,
                        ),
                      ),
                    ],
                  ),
                ),

              // Buyer Name & Shipping Destination
              Text(
                order.buyerName,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                '${order.shippingAddress} (${order.pincode})',
                style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),

              // Line Items Manifest & Garment Thumbnails Row
              if (order.items.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: order.items.map((it) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.obsidianElevated,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.cardBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.checkroom_outlined, size: 14, color: AppColors.goldPrimary),
                          const SizedBox(width: 4),
                          Text(
                            '#${it.productCode ?? 'ITEM'}  ₹${it.priceAtPurchasePaisa ~/ 100}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.goldPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              const SizedBox(height: 12),
              const Divider(color: AppColors.cardBorder, height: 1),
              const SizedBox(height: 10),

              // Contextual Action Buttons
              Row(
                children: [
                  // Pending Actions: WhatsApp & Release
                  if (order.status == OrderStatus.pending) ...[
                    Expanded(
                      child: BounceableButton(
                        onPressed: _sendWhatsAppReminder,
                        variant: ButtonVariant.darkCard,
                        height: 40,
                        icon: Icons.chat,
                        text: 'WhatsApp',
                      ),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.crimson,
                        side: const BorderSide(color: AppColors.crimson),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _forceReleaseHold,
                      child: const Text('Release', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ),
                  ],

                  // Paid / Ready Actions: 4x6 Label & Dispatch
                  if (order.status == OrderStatus.paid ||
                      order.status == OrderStatus.confirmed ||
                      order.fulfilmentStatus == OrderFulfilmentStatus.readyToShip) ...[
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.goldPrimary,
                        side: const BorderSide(color: AppColors.goldPrimary),
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      icon: const Icon(Icons.print, size: 16),
                      label: const Text('4×6 Label', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                      onPressed: _printShippingLabel,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: BounceableButton(
                        onPressed: _openDispatchDialog,
                        variant: ButtonVariant.goldGradient,
                        height: 40,
                        icon: Icons.local_shipping,
                        text: 'Dispatch',
                      ),
                    ),
                  ],

                  // Shipped Actions: Reprint 4x6 Label
                  if (order.status == OrderStatus.shipped ||
                      order.fulfilmentStatus == OrderFulfilmentStatus.shipped) ...[
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.textSecondary,
                          side: const BorderSide(color: AppColors.cardBorder),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.print_outlined, size: 16),
                        label: const Text('Reprint 4×6 Label', style: TextStyle(fontSize: 12)),
                        onPressed: _printShippingLabel,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
