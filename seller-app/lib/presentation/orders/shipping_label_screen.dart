import 'package:flutter/material.dart';
import '../../core/errors/exceptions.dart';
import '../../core/services/pdf_label_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/bounceable_button.dart';
import '../../core/validation/shipping_rules.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';

/// Screen 9: Luxury Boutique Shipping & Fulfilment Screen
/// Displays 4×6" vector thermal label preview, courier partner selection, and label generation.
///
/// SA-SHIP-001: printing/sharing a label never ships the order. "Mark as
/// Shipped" requires the courier's real tracking number (no placeholder, no
/// generated numbers) and an explicit confirmation.
class ShippingLabelScreen extends StatefulWidget {
  final SellerOrder order;
  final SellerProfile profile;
  final SellerRepository repository;
  final PdfLabelService pdfLabelService;

  const ShippingLabelScreen({
    super.key,
    required this.order,
    required this.profile,
    required this.repository,
    this.pdfLabelService = const PdfLabelService(),
  });

  @override
  State<ShippingLabelScreen> createState() => _ShippingLabelScreenState();
}

class _ShippingLabelScreenState extends State<ShippingLabelScreen> {
  String? _selectedCourier;
  late final TextEditingController _trackingController;
  bool _isGenerating = false;
  String? _trackingError;
  String? _courierError;

  final List<String> _courierPartners = [
    'Delhivery',
    'BlueDart',
    'Shiprocket',
    'DTDC',
    'India Post Speed Post',
    'Custom Courier',
  ];

  @override
  void initState() {
    super.initState();
    final existingCourier = widget.order.courierPartner;
    if (existingCourier != null && _courierPartners.contains(existingCourier)) {
      _selectedCourier = existingCourier;
    }
    _trackingController = TextEditingController(text: widget.order.trackingNumber ?? '');
  }

  @override
  void dispose() {
    _trackingController.dispose();
    super.dispose();
  }

  String? get _typedTracking {
    final t = ShippingRules.normalizeTracking(_trackingController.text);
    return t.isEmpty ? null : t;
  }

  Future<void> _handleShare() async {
    setState(() => _isGenerating = true);
    try {
      await widget.pdfLabelService.shareLabel(
        order: widget.order,
        profile: widget.profile,
        courierPartner: _selectedCourier,
        trackingNumber: _typedTracking,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is LiveDropException ? e.message : 'Could not share the label. Try again.'),
            backgroundColor: AppColors.crimson,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _handlePrintOrShare() async {
    setState(() => _isGenerating = true);
    try {
      await widget.pdfLabelService.printLabel(
        order: widget.order,
        profile: widget.profile,
        courierPartner: _selectedCourier,
        trackingNumber: _typedTracking,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is LiveDropException ? e.message : 'Could not print the label. Try again.'),
            backgroundColor: AppColors.crimson,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _handleMarkDispatched() async {
    final tracking = ShippingRules.normalizeTracking(_trackingController.text);
    final courierError = ShippingRules.validateCourier(_selectedCourier);
    final trackingError = ShippingRules.validateTracking(tracking);
    setState(() {
      _courierError = courierError;
      _trackingError = trackingError;
    });
    if (courierError != null || trackingError != null) return;
    final courier = _selectedCourier!;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.obsidianSurface,
        title: const Text('Mark as shipped?'),
        content: Text(
          'Order #${widget.order.orderCode} will be marked shipped via $courier '
          'with tracking number $tracking. The buyer will see this tracking number.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark Shipped')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isGenerating = true);
    try {
      await widget.repository.markOrderShipped(
        orderId: widget.order.id,
        trackingNumber: tracking,
        courierPartner: courier,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order #${widget.order.orderCode} dispatched via $courier!'),
            backgroundColor: AppColors.emerald,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is LiveDropException ? e.message : 'Dispatch failed. Try again.'),
            backgroundColor: AppColors.crimson,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        title: const Text('Shipping Label', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 4×6" Vector Label Preview Card (White thermal ticket design)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.5),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Label Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'LiveDrop',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w900,
                              color: Colors.black,
                              letterSpacing: 0.5,
                            ),
                          ),
                          Text(
                            'Order #${order.orderCode}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.black,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'PREPAID',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(color: Colors.black, thickness: 1.5, height: 1),
                  const SizedBox(height: 14),

                  // Barcode & QR Code simulation
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 48,
                              color: Colors.grey.shade100,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: List.generate(
                                  36,
                                  (i) => Container(
                                    width: i % 3 == 0 ? 3.0 : (i % 2 == 0 ? 1.5 : 2.0),
                                    color: Colors.black,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${order.orderCode}001234',
                              style: const TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      // QR Box
                      Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.black, width: 2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Center(
                          child: Icon(Icons.qr_code_2, size: 48, color: Colors.black),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const Divider(color: Colors.black, thickness: 1, height: 1),
                  const SizedBox(height: 12),

                  // Ship To Details
                  const Text(
                    'SHIP TO:',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.buyerName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Colors.black,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${order.shippingAddress}, ${order.pincode}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black87,
                      height: 1.3,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    order.buyerPhone,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: Colors.black,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Courier Partner Selector
            const Text(
              'Courier Partner',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: AppTheme.cardDecoration(),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCourier,
                  hint: const Text('Select courier', style: TextStyle(color: AppColors.textMuted, fontSize: 14)),
                  isExpanded: true,
                  dropdownColor: AppColors.obsidianSurface,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  items: _courierPartners
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCourier = val;
                        _courierError = null;
                      });
                    }
                  },
                ),
              ),
            ),
            if (_courierError != null) ...[
              const SizedBox(height: 6),
              Text(_courierError!, style: const TextStyle(color: AppColors.crimson, fontSize: 12)),
            ],
            const SizedBox(height: 16),

            // Tracking Number Field (entered by the seller — never generated)
            const Text(
              'Tracking Number',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _trackingController,
              style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold),
              onChanged: (_) {
                if (_trackingError != null) setState(() => _trackingError = null);
              },
              decoration: InputDecoration(
                hintText: 'From your courier receipt',
                errorText: _trackingError,
              ),
            ),
            const SizedBox(height: 24),

            // Primary: print the label (does NOT ship the order)
            BounceableButton(
              onPressed: _isGenerating ? null : _handlePrintOrShare,
              isLoading: _isGenerating,
              variant: ButtonVariant.goldGradient,
              height: 52,
              text: 'Print Label',
              icon: Icons.print_outlined,
            ),
            const SizedBox(height: 12),

            // Explicit, confirmed dispatch with the seller's tracking number
            BounceableButton(
              onPressed: _isGenerating ? null : _handleMarkDispatched,
              variant: ButtonVariant.darkCard,
              height: 48,
              text: 'Mark as Shipped',
              icon: Icons.local_shipping,
            ),
            const SizedBox(height: 16),

            // Secondary Actions: Share / Save the label PDF
            Row(
              children: [
                Expanded(
                  child: BounceableButton(
                    onPressed: _isGenerating ? null : _handleShare,
                    variant: ButtonVariant.darkCard,
                    height: 44,
                    icon: Icons.share_outlined,
                    // One button: the system share sheet also offers "Save to
                    // Files" (SA-UX-002: no second button doing the same).
                    text: 'Share or save PDF',
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
