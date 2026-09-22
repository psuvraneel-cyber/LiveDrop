import 'package:flutter/material.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/bounceable_button.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';

/// Screen 5: Luxury Boutique Product Details Screen
class ProductDetailsScreen extends StatefulWidget {
  final SellerProduct product;
  final SellerRepository repository;
  final VoidCallback? onProductUpdated;

  const ProductDetailsScreen({
    super.key,
    required this.product,
    required this.repository,
    this.onProductUpdated,
  });

  @override
  State<ProductDetailsScreen> createState() => _ProductDetailsScreenState();
}

class _ProductDetailsScreenState extends State<ProductDetailsScreen> {
  late SellerProduct _product;
  bool _isMarkingSold = false;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
  }

  Future<void> _handleMarkSold() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.obsidianSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: const Text('Mark as Sold Offline?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Marking ${_product.code} as sold offline will immediately update its status.',
          style: const TextStyle(color: AppColors.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.goldPrimary,
              foregroundColor: Colors.black,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isMarkingSold = true);
    try {
      await widget.repository.markProductSoldOffline(_product.id);
      setState(() {
        _product = SellerProduct(
          id: _product.id,
          dropId: _product.dropId,
          code: _product.code,
          title: _product.title,
          pricePaisa: _product.pricePaisa,
          size: _product.size,
          imageUrl: _product.imageUrl,
          status: ProductStatus.sold,
          version: _product.version + 1,
        );
        _isMarkingSold = false;
      });
      widget.onProductUpdated?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isMarkingSold = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: $e'),
          backgroundColor: AppColors.crimson,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final priceRupees = (_product.pricePaisa / 100).toStringAsFixed(0);
    final isSold = _product.status == ProductStatus.sold;
    final isReserved = _product.status == ProductStatus.reserved;

    Color statusColor = AppColors.emerald;
    Color statusTint = AppColors.emeraldTint;
    String statusText = 'Available';

    if (isSold) {
      statusColor = AppColors.crimson;
      statusTint = AppColors.crimsonTint;
      statusText = 'Sold';
    } else if (isReserved) {
      statusColor = AppColors.amber;
      statusTint = AppColors.amberTint;
      statusText = 'On Hold';
    }

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        title: const Text('Product Details', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_vert_rounded),
            onPressed: () {},
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Hero Image Container with status overlay
            Stack(
              children: [
                Container(
                  height: 340,
                  width: double.infinity,
                  color: AppColors.obsidianElevated,
                  child: _product.imageUrl.isNotEmpty
                      ? Image.network(
                          _product.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => const Center(
                            child: Icon(Icons.checkroom_rounded, size: 80, color: AppColors.goldPrimary),
                          ),
                        )
                      : const Center(
                          child: Icon(Icons.checkroom_rounded, size: 80, color: AppColors.goldPrimary),
                        ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: AppTheme.pillDecoration(
                      color: statusColor,
                      tintColor: statusTint.withValues(alpha: 0.9),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isSold ? Icons.close : (isReserved ? Icons.lock_clock : Icons.check_circle_outline),
                          size: 14,
                          color: statusColor,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: statusColor,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Title & Code
                  Text(
                    '#${_product.code} ${_product.title}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '₹$priceRupees',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: AppColors.goldPrimary,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3-Button Action Row
                  Row(
                    children: [
                      Expanded(
                        child: BounceableButton(
                          onPressed: () {},
                          variant: ButtonVariant.darkCard,
                          height: 44,
                          icon: Icons.edit_outlined,
                          text: 'Edit',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: BounceableButton(
                          onPressed: isSold ? null : _handleMarkSold,
                          isLoading: _isMarkingSold,
                          variant: ButtonVariant.darkCard,
                          height: 44,
                          icon: Icons.sell_outlined,
                          text: isSold ? 'Sold' : 'Mark Sold',
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: BounceableButton(
                          onPressed: () {},
                          variant: ButtonVariant.darkCard,
                          height: 44,
                          icon: Icons.share_outlined,
                          text: 'Share',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Category & Description
                  const Text(
                    'Category',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _product.size.isNotEmpty ? 'Apparel / Size ${_product.size}' : 'Boutique Apparel',
                    style: const TextStyle(fontSize: 15, color: AppColors.textPrimary, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 16),

                  const Text(
                    'Description',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _product.title.isNotEmpty
                        ? '${_product.title} (Piece ${_product.code}). Authentic boutique garment. Listed at ₹$priceRupees.'
                        : 'Authentic boutique garment #${_product.code}. Listed at ₹$priceRupees.',
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 24),

                  // Photos
                  const Text(
                    'Photos',
                    style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (_product.imageUrl.isNotEmpty)
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              border: Border.all(color: AppColors.goldPrimary, width: 1.5),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Image.network(
                              _product.imageUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Center(
                                child: Icon(Icons.checkroom_rounded, color: AppColors.goldPrimary, size: 28),
                              ),
                            ),
                          ),
                        )
                      else
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.obsidianElevated,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.cardBorder, width: 1),
                          ),
                          child: const Icon(Icons.checkroom_rounded, color: AppColors.goldPrimary, size: 28),
                        ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // Detail Attributes Grid
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: AppTheme.cardDecoration(),
                    child: Column(
                      children: [
                        _buildAttributeRow(
                          'Product Code',
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _product.code,
                                style: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: AppColors.goldMuted,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text(
                                  'Auto',
                                  style: TextStyle(fontSize: 10, color: AppColors.goldPrimary, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Divider(color: AppColors.cardBorder, height: 20),
                        _buildAttributeRow(
                          'Size',
                          Text(
                            _product.size.isNotEmpty ? _product.size : 'Free Size',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                        const Divider(color: AppColors.cardBorder, height: 20),
                        _buildAttributeRow(
                          'Stock Status',
                          Text(
                            statusText,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: statusColor,
                            ),
                          ),
                        ),
                        const Divider(color: AppColors.cardBorder, height: 20),
                        _buildAttributeRow(
                          'Price (₹)',
                          Text(
                            '₹$priceRupees',
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttributeRow(String label, Widget valueWidget) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        valueWidget,
      ],
    );
  }
}
