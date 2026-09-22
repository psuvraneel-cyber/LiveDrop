import 'package:flutter/material.dart';
import '../../core/services/pdf_label_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/bounceable_button.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';

/// Screen 9: Luxury Boutique Shipping & Fulfilment Screen
/// Displays 4×6" vector thermal label preview, courier partner selection, and label generation.
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
  String _selectedCourier = 'Delhivery';
  late final TextEditingController _trackingController;
  bool _isGenerating = false;

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
    _trackingController = TextEditingController(
      text: widget.order.trackingNumber ?? 'DVA123456789',
    );
  }

  @override
  void dispose() {
    _trackingController.dispose();
    super.dispose();
  }

  void _generateAutoTracking() {
    final prefix = _selectedCourier.substring(0, 3).toUpperCase();
    final randomDigits = DateTime.now().millisecondsSinceEpoch.toString().substring(5);
    setState(() {
      _trackingController.text = '$prefix$randomDigits';
    });
  }

  Future<void> _handlePrintOrShare() async {
    setState(() => _isGenerating = true);
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
    } finally {
      if (mounted) {
        setState(() => _isGenerating = false);
      }
    }
  }

  Future<void> _handleMarkDispatched() async {
    final tracking = _trackingController.text.trim();
    if (tracking.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please provide or generate a tracking number.'),
          backgroundColor: AppColors.crimson,
        ),
      );
      return;
    }

    setState(() => _isGenerating = true);
    try {
      await widget.repository.markOrderShipped(
        orderId: widget.order.id,
        trackingNumber: tracking,
        courierPartner: _selectedCourier,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Order #${widget.order.orderCode} dispatched via $_selectedCourier!'),
            backgroundColor: AppColors.emerald,
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Dispatch failed: $e'),
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
                  isExpanded: true,
                  dropdownColor: AppColors.obsidianSurface,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                  items: _courierPartners
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _selectedCourier = val);
                      _generateAutoTracking();
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Tracking Number Field with Auto Button
            const Text(
              'Tracking Number',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _trackingController,
                    style: const TextStyle(color: Colors.white, fontFamily: 'monospace', fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      hintText: 'e.g. DVA123456789',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                BounceableButton(
                  onPressed: _generateAutoTracking,
                  variant: ButtonVariant.darkCard,
                  height: 48,
                  text: 'Auto',
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Primary Generate & Share Label Button
            BounceableButton(
              onPressed: _isGenerating ? null : _handleMarkDispatched,
              isLoading: _isGenerating,
              variant: ButtonVariant.goldGradient,
              height: 52,
              text: 'Generate & Share Label',
              icon: Icons.local_shipping,
            ),
            const SizedBox(height: 16),

            // Secondary Actions: Share, Print, Download
            Row(
              children: [
                Expanded(
                  child: BounceableButton(
                    onPressed: _handlePrintOrShare,
                    variant: ButtonVariant.darkCard,
                    height: 44,
                    icon: Icons.share_outlined,
                    text: 'Share',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BounceableButton(
                    onPressed: _handlePrintOrShare,
                    variant: ButtonVariant.darkCard,
                    height: 44,
                    icon: Icons.print_outlined,
                    text: 'Print',
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: BounceableButton(
                    onPressed: _handlePrintOrShare,
                    variant: ButtonVariant.darkCard,
                    height: 44,
                    icon: Icons.download_outlined,
                    text: 'Download',
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
