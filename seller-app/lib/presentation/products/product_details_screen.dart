import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/config/env_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/bounceable_button.dart';
import '../../core/utils/url_launcher_helper.dart';
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
  late final PageController _pageController;
  int _currentImageIndex = 0;
  bool _isMarkingSold = false;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _product = widget.product;
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  List<String> get _allImages {
    if (_product.imageUrls.isNotEmpty) {
      return _product.imageUrls;
    }
    if (_product.imageUrl.isNotEmpty) {
      return [_product.imageUrl];
    }
    return const [];
  }

  String get _displayCode =>
      _product.code.startsWith('#') ? _product.code : '#${_product.code}';

  Future<void> _handleEditProduct() async {
    if (_product.status != ProductStatus.available) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Cannot edit $_displayCode: item is ${_product.status.name}. Only available items can be edited.',
          ),
          backgroundColor: AppColors.crimson,
        ),
      );
      return;
    }

    final titleController = TextEditingController(text: _product.title);
    final priceController = TextEditingController(
      text: (_product.pricePaisa / 100).toStringAsFixed(0),
    );
    final sizeController = TextEditingController(text: _product.size);

    final updated = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.obsidianSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder),
        ),
        title: Text(
          'Edit $_displayCode',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: titleController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Product Title',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: priceController,
                keyboardType: TextInputType.number,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
                decoration: const InputDecoration(
                  prefixText: '₹ ',
                  prefixStyle: TextStyle(
                    color: AppColors.emerald,
                    fontWeight: FontWeight.bold,
                  ),
                  labelText: 'Price (₹ INR)',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: sizeController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  labelText: 'Size (e.g. Free Size, S, M, L)',
                  labelStyle: TextStyle(color: AppColors.textSecondary),
                ),
              ),
            ],
          ),
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
            child: const Text('Save Changes'),
          ),
        ],
      ),
    );

    if (updated != true) return;

    final newTitle = titleController.text.trim();
    final newSize = sizeController.text.trim();
    final priceVal = int.tryParse(priceController.text.trim());

    if (newTitle.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Title cannot be empty'),
          backgroundColor: AppColors.crimson,
        ),
      );
      return;
    }

    if (priceVal == null || priceVal <= 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please enter a valid price in ₹'),
          backgroundColor: AppColors.crimson,
        ),
      );
      return;
    }

    if (newSize.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Size cannot be empty'),
          backgroundColor: AppColors.crimson,
        ),
      );
      return;
    }

    setState(() => _isEditing = true);
    try {
      final updatedProduct = await widget.repository.updateProduct(
        productId: _product.id,
        title: newTitle,
        pricePaisa: priceVal * 100,
        size: newSize,
      );

      if (!mounted) return;
      setState(() {
        _product = updatedProduct;
        _isEditing = false;
      });
      widget.onProductUpdated?.call();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Product updated successfully!'),
          backgroundColor: AppColors.emerald,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isEditing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Update failed: $e'),
          backgroundColor: AppColors.crimson,
        ),
      );
    }
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
          imageUrls: _product.imageUrls,
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

  Future<void> _handleShareProduct() async {
    String dropSlug = '';
    try {
      final drops = await widget.repository.getDrops();
      final drop = drops.where((d) => d.id == _product.dropId).firstOrNull;
      if (drop != null) {
        dropSlug = drop.slug;
      }
    } catch (_) {}

    final productUrl = dropSlug.isNotEmpty
        ? EnvConfig.getProductUrl(dropSlug, _product.code)
        : EnvConfig.buyerBaseUrl;

    final priceRupees = (_product.pricePaisa / 100).toStringAsFixed(0);
    final shareText = '✨ $_displayCode ${_product.title} (₹$priceRupees)\n'
        'Direct link to shop: $productUrl';

    if (!mounted) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.obsidianSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Share $_displayCode ${_product.title}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.copy_rounded, color: AppColors.goldPrimary),
                title: const Text('Copy Direct Link', style: TextStyle(color: Colors.white)),
                subtitle: Text(productUrl, style: const TextStyle(color: AppColors.textMuted, fontSize: 12), overflow: TextOverflow.ellipsis),
                onTap: () => Navigator.pop(ctx, 'copy'),
              ),
              ListTile(
                leading: const Icon(Icons.share_outlined, color: AppColors.emerald),
                title: const Text('Share via WhatsApp', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Send link directly to customers', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'whatsapp'),
              ),
              ListTile(
                leading: const Icon(Icons.open_in_browser_rounded, color: Colors.blueAccent),
                title: const Text('Open on Buyer Website', style: TextStyle(color: Colors.white)),
                subtitle: const Text('Preview product in mobile browser', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'open'),
              ),
            ],
          ),
        ),
      ),
    );

    if (choice == null || !mounted) return;

    if (choice == 'copy') {
      await Clipboard.setData(ClipboardData(text: productUrl));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Product link copied: $productUrl'),
          backgroundColor: AppColors.emerald,
        ),
      );
    } else if (choice == 'whatsapp') {
      UrlLauncherHelper.launchExternalWebUrl(
        context: context,
        url: 'https://wa.me/?text=${Uri.encodeComponent(shareText)}',
      );
    } else if (choice == 'open') {
      UrlLauncherHelper.launchExternalWebUrl(
        context: context,
        url: productUrl,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final priceRupees = (_product.pricePaisa / 100).toStringAsFixed(0);
    final isSold = _product.status == ProductStatus.sold;
    final isReserved = _product.status == ProductStatus.reserved;
    final images = _allImages;
    final activeIndex = _currentImageIndex.clamp(0, images.isEmpty ? 0 : images.length - 1);

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
            // Hero Image Container with status overlay & carousel
            Stack(
              children: [
                Container(
                  height: 360,
                  width: double.infinity,
                  color: AppColors.obsidianElevated,
                  child: images.isNotEmpty
                      ? PageView.builder(
                          controller: _pageController,
                          itemCount: images.length,
                          onPageChanged: (index) {
                            setState(() => _currentImageIndex = index);
                          },
                          itemBuilder: (context, index) {
                            return Image.network(
                              images[index],
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Center(
                                child: Icon(Icons.checkroom_rounded, size: 80, color: AppColors.goldPrimary),
                              ),
                            );
                          },
                        )
                      : const Center(
                          child: Icon(Icons.checkroom_rounded, size: 80, color: AppColors.goldPrimary),
                        ),
                ),
                // Status Overlay (Top Right)
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
                // Angle Counter Badge (Top Left)
                if (images.length > 1)
                  Positioned(
                    top: 16,
                    left: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.cardBorder.withValues(alpha: 0.6)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.camera_alt_rounded, size: 13, color: AppColors.goldPrimary),
                          const SizedBox(width: 5),
                          Text(
                            '${activeIndex + 1} / ${images.length}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Dot Indicators (Bottom Center)
                if (images.length > 1)
                  Positioned(
                    bottom: 12,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(images.length, (index) {
                        final isActive = index == activeIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 250),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: isActive ? 22 : 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: isActive ? AppColors.goldPrimary : Colors.white.withValues(alpha: 0.4),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        );
                      }),
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
                    '$_displayCode ${_product.title}',
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
                          onPressed: (isSold || isReserved) ? null : _handleEditProduct,
                          isLoading: _isEditing,
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
                          onPressed: _handleShareProduct,
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
                        : 'Authentic boutique garment $_displayCode. Listed at ₹$priceRupees.',
                    style: const TextStyle(fontSize: 14, color: AppColors.textSecondary, height: 1.4),
                  ),
                  const SizedBox(height: 24),

                  // Photos Gallery Strip
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Photos',
                        style: TextStyle(fontSize: 13, color: AppColors.textMuted, fontWeight: FontWeight.w600),
                      ),
                      if (images.length > 1)
                        Text(
                          '${images.length} angles',
                          style: const TextStyle(fontSize: 12, color: AppColors.goldPrimary, fontWeight: FontWeight.w600),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (images.isNotEmpty)
                    SizedBox(
                      height: 76,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: images.length,
                        separatorBuilder: (context, index) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final isSelected = index == activeIndex;
                          final imgUrl = images[index];
                          return GestureDetector(
                            onTap: () {
                              setState(() => _currentImageIndex = index);
                              _pageController.animateToPage(
                                index,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: isSelected ? AppColors.goldPrimary : AppColors.cardBorder,
                                  width: isSelected ? 2.0 : 1.0,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(
                                  imgUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Center(
                                    child: Icon(Icons.checkroom_rounded, color: AppColors.goldPrimary, size: 28),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: AppColors.obsidianElevated,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.cardBorder, width: 1),
                      ),
                      child: const Icon(Icons.checkroom_rounded, color: AppColors.goldPrimary, size: 28),
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
                                _displayCode,
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
