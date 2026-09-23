import 'package:flutter/material.dart';
import '../../core/errors/exceptions.dart';
import '../../core/services/pdf_label_service.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';

/// LiveDrop Seller Mobile App — Order Shipping & Dispatch Dialog
///
/// Prompts for courier details, generates 4×6" thermal label, and calls `mark_order_shipped` RPC.
class ShippingDialog extends StatefulWidget {
  final SellerOrder order;
  final SellerProfile profile;
  final SellerRepository repository;
  final PdfLabelService pdfLabelService;

  const ShippingDialog({
    super.key,
    required this.order,
    required this.profile,
    required this.repository,
    this.pdfLabelService = const PdfLabelService(),
  });

  @override
  State<ShippingDialog> createState() => _ShippingDialogState();
}

class _ShippingDialogState extends State<ShippingDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _trackingController;
  late TextEditingController _courierController;
  late TextEditingController _notesController;
  bool _isDispatching = false;
  bool _isPrinting = false;

  final _couriers = [
    'Delhivery Express',
    'Blue Dart Express',
    'Xpressbees Logistics',
    'DTDC Express',
    'Shadowfax',
    'India Post Speed Post',
  ];

  @override
  void initState() {
    super.initState();
    _trackingController = TextEditingController(
      text: widget.order.trackingNumber ?? '',
    );
    _courierController = TextEditingController(
      text: widget.order.courierPartner ?? 'Delhivery Express',
    );
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _trackingController.dispose();
    _courierController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _printLabel() async {
    setState(() => _isPrinting = true);
    try {
      final tracking = _trackingController.text.trim().isNotEmpty
          ? _trackingController.text.trim()
          : 'TRK-${widget.order.orderCode}';

      await widget.pdfLabelService.printLabel(
        order: widget.order,
        profile: widget.profile,
        courierPartner: _courierController.text.trim(),
        trackingNumber: tracking,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print spooler error: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isPrinting = false);
    }
  }

  Future<void> _shareLabel() async {
    try {
      final tracking = _trackingController.text.trim().isNotEmpty
          ? _trackingController.text.trim()
          : 'TRK-${widget.order.orderCode}';

      await widget.pdfLabelService.shareLabel(
        order: widget.order,
        profile: widget.profile,
        courierPartner: _courierController.text.trim(),
        trackingNumber: tracking,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Share error: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  Future<void> _confirmDispatch() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isDispatching = true);

    try {
      final tracking = _trackingController.text.trim();
      final courier = _courierController.text.trim();
      final notes = _notesController.text.trim().isNotEmpty ? _notesController.text.trim() : null;

      if (widget.order.fulfilmentStatus == OrderFulfilmentStatus.notReady) {
        await widget.repository.markOrderReadyToShip(widget.order.id);
      }

      await widget.repository.markOrderShipped(
        orderId: widget.order.id,
        trackingNumber: tracking,
        courierPartner: courier,
        notes: notes,
      );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDispatching = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e is LiveDropException ? e.message : 'Dispatch failed: $e'),
            backgroundColor: Colors.red.shade800,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF1E1E24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Dispatch & Print Label',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Order #${widget.order.orderCode}  •  ${widget.order.buyerName}',
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade400),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white54),
                    onPressed: () => Navigator.of(context).pop(false),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(color: Colors.white10),
              const SizedBox(height: 12),

              // Destination Preview Box
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF2A2A32),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'DESTINATION (${widget.order.pincode})',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFF59E0B),
                          ),
                        ),
                        Text(
                          '₹${widget.order.totalPaisa ~/ 100} PREPAID',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.order.shippingAddress,
                      style: const TextStyle(fontSize: 12, color: Colors.white70),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Buyer Phone: ${widget.order.buyerPhone}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Courier Partner Field & Quick Chips
              TextFormField(
                controller: _courierController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Courier Partner *',
                  labelStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: const Color(0xFF2A2A32),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Courier partner is required' : null,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _couriers.map((c) {
                  return ActionChip(
                    label: Text(c, style: const TextStyle(fontSize: 11)),
                    backgroundColor: const Color(0xFF2A2A32),
                    labelStyle: TextStyle(
                      color: _courierController.text == c ? const Color(0xFFF59E0B) : Colors.white70,
                    ),
                    onPressed: () => setState(() => _courierController.text = c),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              // Tracking Number Field
              TextFormField(
                controller: _trackingController,
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                decoration: InputDecoration(
                  labelText: 'Tracking / AWB Number *',
                  hintText: 'e.g. 142129849204 or TRK-DEL-889',
                  hintStyle: TextStyle(color: Colors.grey.shade600),
                  labelStyle: TextStyle(color: Colors.grey.shade400),
                  filled: true,
                  fillColor: const Color(0xFF2A2A32),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                validator: (val) =>
                    val == null || val.trim().isEmpty ? 'Tracking number is required' : null,
              ),
              const SizedBox(height: 16),

              // Thermal Label Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFF59E0B),
                        side: const BorderSide(color: Color(0xFFF59E0B)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                      onPressed: _isPrinting ? null : _printLabel,
                      icon: _isPrinting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFF59E0B)),
                            )
                          : const Icon(Icons.print, size: 18),
                      label: const Text('Print 4×6 Label', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.share, color: Colors.white70),
                    tooltip: 'Share Label PDF',
                    onPressed: _shareLabel,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Confirm Dispatch Button
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF10B981),
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isDispatching ? null : _confirmDispatch,
                icon: _isDispatching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.local_shipping, color: Colors.black),
                label: Text(
                  _isDispatching ? 'Marking Shipped...' : 'Confirm Dispatch',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
