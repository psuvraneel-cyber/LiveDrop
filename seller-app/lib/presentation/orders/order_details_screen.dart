import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/bounceable_button.dart';
import '../../core/utils/url_launcher_helper.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';
import 'shipping_dialog.dart';

/// Screen 8: Luxury Boutique Order Details Screen
class OrderDetailsScreen extends StatefulWidget {
  final SellerOrder order;
  final SellerProfile profile;
  final SellerRepository repository;
  final VoidCallback onOrderUpdated;

  const OrderDetailsScreen({
    super.key,
    required this.order,
    required this.profile,
    required this.repository,
    required this.onOrderUpdated,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  late SellerOrder _order;

  @override
  void initState() {
    super.initState();
    _order = widget.order;
  }

  Future<void> _launchWhatsApp() async {
    final phone = _order.buyerPhone.replaceAll(RegExp(r'[^0-9]'), '');
    final cleanPhone = phone.startsWith('91') ? phone : '91$phone';
    await UrlLauncherHelper.launchWhatsApp(
      context: context,
      phone: cleanPhone,
      message: 'Hello ${_order.buyerName}, regarding your LiveDrop order #${_order.orderCode}...',
    );
  }

  Future<void> _launchCall() async {
    await UrlLauncherHelper.launchDialer(
      context: context,
      phoneNumber: _order.buyerPhone,
    );
  }

  void _copyAddress() {
    Clipboard.setData(ClipboardData(text: '${_order.shippingAddress}, ${_order.pincode}'));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Address copied to clipboard'),
        backgroundColor: AppColors.emerald,
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _openDispatch() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => ShippingDialog(
        order: _order,
        profile: widget.profile,
        repository: widget.repository,
      ),
    );

    if (result == true && mounted) {
      widget.onOrderUpdated();
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalRupees = (_order.totalPaisa / 100).toStringAsFixed(0);
    final advanceRupees = (_order.advancePaidPaisa / 100).toStringAsFixed(0);
    final balanceRupees = (_order.balanceDuePaisa / 100).toStringAsFixed(0);

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        title: Text('Order #${_order.orderCode}', style: const TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 5-Step Horizontal Progress Stepper
            _buildProgressStepper(),
            const SizedBox(height: 20),

            // Customer Card (Initials, Name, Phone, WhatsApp & Call)
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Customer', style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      CircleAvatar(
                        radius: 22,
                        backgroundColor: AppColors.goldMuted,
                        child: Text(
                          _getInitials(_order.buyerName),
                          style: const TextStyle(
                            color: AppColors.goldPrimary,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _order.buyerName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _order.buyerPhone,
                              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                            ),
                          ],
                        ),
                      ),
                      // Action Icons
                      IconButton(
                        onPressed: _launchWhatsApp,
                        icon: const Icon(Icons.chat_bubble_rounded, color: AppColors.whatsAppGreen, size: 24),
                        tooltip: 'WhatsApp',
                      ),
                      IconButton(
                        onPressed: _launchCall,
                        icon: const Icon(Icons.phone_rounded, color: AppColors.emerald, size: 24),
                        tooltip: 'Call Buyer',
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Delivery Address Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Delivery Address',
                        style: TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                      InkWell(
                        onTap: _copyAddress,
                        child: const Icon(Icons.copy_rounded, color: AppColors.goldPrimary, size: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_order.shippingAddress}, ${_order.pincode}',
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Items List
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Items (${_order.items.length})',
                    style: const TextStyle(fontSize: 12, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 12),
                  ..._order.items.map((item) {
                    final itemPrice = (item.priceAtPurchasePaisa / 100).toStringAsFixed(0);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 44,
                              height: 44,
                              color: AppColors.obsidianElevated,
                              child: item.productImageUrl != null && item.productImageUrl!.isNotEmpty
                                  ? Image.network(item.productImageUrl!, fit: BoxFit.cover)
                                  : const Icon(Icons.checkroom, color: AppColors.goldPrimary, size: 22),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '#${item.productCode ?? ""} ${item.productTitle ?? "Item"}',
                                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                                ),
                                const SizedBox(height: 2),
                                const Text('x 1', style: TextStyle(fontSize: 12, color: AppColors.textMuted)),
                              ],
                            ),
                          ),
                          Text(
                            '₹$itemPrice',
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.goldPrimary),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Financial Balance Summary Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: AppTheme.cardDecoration(),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total Amount', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                      Text('₹$totalRupees', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Advance Paid', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                      Text('₹$advanceRupees', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.emerald)),
                    ],
                  ),
                  const Divider(color: AppColors.cardBorder, height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Balance Due', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.textPrimary)),
                      Text('₹$balanceRupees', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.goldPrimary)),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Dual Action Buttons: Contact Buyer | Mark as Ready / Dispatch
            Row(
              children: [
                Expanded(
                  child: BounceableButton(
                    onPressed: _launchWhatsApp,
                    variant: ButtonVariant.darkCard,
                    height: 48,
                    text: 'Contact Buyer',
                    icon: Icons.chat_outlined,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: BounceableButton(
                    onPressed: _openDispatch,
                    variant: ButtonVariant.goldGradient,
                    height: 48,
                    text: _order.status == OrderStatus.shipped ? 'Shipped' : 'Mark as Ready',
                    icon: Icons.local_shipping_outlined,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressStepper() {
    // 5-steps: Pending -> Advance Paid -> Balance Due -> Ready -> Shipped
    final steps = ['Pending', 'Advance Paid', 'Balance Due', 'Ready', 'Shipped'];

    int activeIndex = 0;
    if (_order.status == OrderStatus.shipped) {
      activeIndex = 4;
    } else if (_order.fulfilmentStatus == OrderFulfilmentStatus.readyToShip) {
      activeIndex = 3;
    } else if (_order.paymentStatus == OrderPaymentStatus.paid) {
      activeIndex = 3;
    } else if (_order.paymentStatus == OrderPaymentStatus.advancePaid) {
      activeIndex = _order.balanceDuePaisa > 0 ? 2 : 1;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
      decoration: AppTheme.cardDecoration(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(steps.length, (i) {
          final isCompleted = i <= activeIndex;
          final isActive = i == activeIndex;
          return Column(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted ? AppColors.goldPrimary : AppColors.obsidianElevated,
                  border: Border.all(
                    color: isActive ? AppColors.goldPrimary : AppColors.cardBorder,
                    width: 1.5,
                  ),
                ),
                child: isCompleted
                    ? const Icon(Icons.check, size: 12, color: Colors.black)
                    : null,
              ),
              const SizedBox(height: 6),
              Text(
                steps[i],
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isCompleted ? FontWeight.bold : FontWeight.normal,
                  color: isCompleted ? AppColors.goldPrimary : AppColors.textMuted,
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (name.isNotEmpty) {
      return name.substring(0, 1).toUpperCase();
    }
    return 'B';
  }
}
