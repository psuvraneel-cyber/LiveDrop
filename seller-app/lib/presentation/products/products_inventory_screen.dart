import 'package:flutter/material.dart';
import '../../core/services/offline_intake_queue.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';
import '../common/skeleton_loaders.dart';
import '../drops/create_drop_screen.dart';
import '../drops/drops_list_screen.dart';
import '../intake/camera_intake_screen.dart';
import 'product_details_screen.dart';

/// Screen 3: Luxury Boutique Products & Inventory Screen
class ProductsInventoryScreen extends StatefulWidget {
  final SellerRepository repository;
  final OfflineIntakeQueue? intakeQueue;

  const ProductsInventoryScreen({
    super.key,
    required this.repository,
    this.intakeQueue,
  });

  @override
  State<ProductsInventoryScreen> createState() => _ProductsInventoryScreenState();
}

class _ProductsInventoryScreenState extends State<ProductsInventoryScreen> {
  bool _isLoading = true;
  List<SellerProduct> _allProducts = [];
  List<SellerProduct> _filteredProducts = [];
  SellerDrop? _activeDrop;
  String _searchQuery = '';
  String _selectedFilter = 'All'; // All, Available, Reserved, Sold

  @override
  void initState() {
    super.initState();
    widget.intakeQueue?.pendingCountNotifier.addListener(_onQueueChanged);
    _loadProducts();
  }

  @override
  void dispose() {
    widget.intakeQueue?.pendingCountNotifier.removeListener(_onQueueChanged);
    super.dispose();
  }

  void _onQueueChanged() {
    if (mounted) {
      _loadProducts();
    }
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    try {
      final drops = await widget.repository.getDrops();
      final active = _activeDrop != null
          ? drops.where((d) => d.id == _activeDrop!.id).firstOrNull ?? drops.firstOrNull
          : (drops.where((d) => d.status == DropStatus.live).firstOrNull ??
              drops.where((d) => d.status == DropStatus.draft).firstOrNull ??
              drops.firstOrNull);

      _activeDrop = active;

      if (active != null) {
        final products = await widget.repository.getProducts(active.id);
        final queuedProducts = <SellerProduct>[];
        if (widget.intakeQueue != null) {
          final pending = widget.intakeQueue!.items.where(
            (i) => i.dropId == active.id && i.status != IntakeQueueStatus.completed,
          );
          for (final q in pending) {
            if (!products.any((p) => p.code == q.code)) {
              queuedProducts.add(
                SellerProduct(
                  id: q.id,
                  dropId: q.dropId,
                  code: q.code,
                  title: q.title,
                  pricePaisa: q.pricePaisa,
                  size: q.size,
                  imageUrl: q.localImagePath,
                  imageUrls: q.localImagePaths,
                  status: ProductStatus.available,
                  version: 1,
                ),
              );
            }
          }
        }
        if (mounted) {
          setState(() {
            _allProducts = [...queuedProducts, ...products];
            _applyFilters();
            _isLoading = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _allProducts = [];
            _filteredProducts = [];
            _isLoading = false;
          });
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilters() {
    var list = List<SellerProduct>.from(_allProducts);

    if (_searchQuery.isNotEmpty) {
      final q = _searchQuery.toLowerCase();
      list = list.where((p) {
        return p.code.toLowerCase().contains(q) ||
            p.title.toLowerCase().contains(q) ||
            p.status.name.toLowerCase().contains(q);
      }).toList();
    }

    if (_selectedFilter == 'Available') {
      list = list.where((p) => p.status == ProductStatus.available).toList();
    } else if (_selectedFilter == 'Reserved') {
      list = list.where((p) => p.status == ProductStatus.reserved).toList();
    } else if (_selectedFilter == 'Sold') {
      list = list.where((p) => p.status == ProductStatus.sold).toList();
    }

    setState(() {
      _filteredProducts = list;
    });
  }

  @override
  Widget build(BuildContext context) {
    final allCount = _allProducts.length;
    final availableCount = _allProducts.where((p) => p.status == ProductStatus.available).length;
    final reservedCount = _allProducts.where((p) => p.status == ProductStatus.reserved).length;
    final soldCount = _allProducts.where((p) => p.status == ProductStatus.sold).length;

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Products', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            if (_activeDrop != null)
              Text(
                'Drop: ${_activeDrop!.title}',
                style: const TextStyle(fontSize: 12, color: AppColors.goldPrimary, fontWeight: FontWeight.w500),
              ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.storefront_outlined, color: AppColors.goldPrimary),
            tooltip: 'Manage Drops',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => DropsListScreen(repository: widget.repository),
                ),
              ).then((_) => _loadProducts());
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Bar & Filter Action Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                      onChanged: (val) {
                        _searchQuery = val;
                        _applyFilters();
                      },
                      decoration: InputDecoration(
                        hintText: 'Search by code, name or status...',
                        prefixIcon: const Icon(Icons.search, color: AppColors.textMuted, size: 20),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 18, color: AppColors.textMuted),
                                onPressed: () {
                                  setState(() => _searchQuery = '');
                                  _applyFilters();
                                },
                              )
                            : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    height: 48,
                    width: 48,
                    decoration: BoxDecoration(
                      color: AppColors.obsidianSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.cardBorder),
                    ),
                    child: const Icon(Icons.tune_rounded, color: AppColors.goldPrimary, size: 20),
                  ),
                ],
              ),
            ),

            // Sync & Failure Banners
            if (widget.intakeQueue != null && widget.intakeQueue!.failedCount > 0)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.crimson.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.crimson),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_rounded,
                        color: AppColors.crimson, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${widget.intakeQueue!.failedCount} upload(s) failed',
                            style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                fontSize: 13),
                          ),
                          const Text(
                            'Storage or network error. Tap to retry.',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () async {
                        await widget.intakeQueue!.retryFailed(widget.repository);
                        _loadProducts();
                      },
                      icon: const Icon(Icons.refresh,
                          size: 16, color: AppColors.goldPrimary),
                      label: const Text('Retry',
                          style: TextStyle(
                              color: AppColors.goldPrimary,
                              fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              )
            else if (widget.intakeQueue != null && widget.intakeQueue!.pendingCount > 0)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: AppColors.obsidianElevated,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: AppColors.goldPrimary.withValues(alpha: 0.5)),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: AppColors.goldPrimary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Syncing ${widget.intakeQueue!.pendingCount} piece(s) to cloud...',
                        style: const TextStyle(
                            color: AppColors.goldPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),

            // 4 Filter Chips: All, Available, Reserved, Sold
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  _buildFilterChip('All', allCount),
                  const SizedBox(width: 8),
                  _buildFilterChip('Available', availableCount),
                  const SizedBox(width: 8),
                  _buildFilterChip('Reserved', reservedCount),
                  const SizedBox(width: 8),
                  _buildFilterChip('Sold', soldCount),
                ],
              ),
            ),
            const SizedBox(height: 8),

            // Products List / Skeleton
            Expanded(
              child: _isLoading
                  ? const DropsListSkeleton()
                  : _filteredProducts.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.checkroom_outlined, size: 56, color: AppColors.textMuted),
                              const SizedBox(height: 12),
                              Text(
                                _activeDrop == null
                                    ? 'No drop selected or created'
                                    : (_searchQuery.isEmpty ? 'No products in this drop yet' : 'No matching products found'),
                                style: const TextStyle(fontSize: 15, color: AppColors.textSecondary),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _activeDrop == null
                                    ? 'Create your first drop to begin camera intake'
                                    : 'Tap the + button below to snap and add items',
                                style: const TextStyle(fontSize: 13, color: AppColors.textMuted),
                              ),
                              if (_activeDrop == null) ...[
                                const SizedBox(height: 16),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.goldPrimary,
                                    foregroundColor: Colors.black,
                                  ),
                                  icon: const Icon(Icons.add),
                                  label: const Text('Create Drop'),
                                  onPressed: () async {
                                    final created = await Navigator.push<SellerDrop?>(
                                      context,
                                      MaterialPageRoute<SellerDrop?>(
                                        builder: (_) => CreateDropScreen(repository: widget.repository),
                                      ),
                                    );
                                    if (mounted && created != null) {
                                      _loadProducts();
                                    }
                                  },
                                ),
                              ],
                            ],
                          ),
                        )
                      : RefreshIndicator(
                          color: AppColors.goldPrimary,
                          backgroundColor: AppColors.obsidianSurface,
                          onRefresh: _loadProducts,
                          child: ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: _filteredProducts.length,
                            itemBuilder: (context, index) {
                              final product = _filteredProducts[index];
                              return _buildProductCard(product);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.goldPrimary,
        foregroundColor: Colors.black,
        shape: const CircleBorder(),
        elevation: 6,
        onPressed: () async {
          if (_activeDrop != null) {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CameraIntakeScreen(
                  repository: widget.repository,
                  drop: _activeDrop,
                  intakeQueue: widget.intakeQueue,
                ),
              ),
            ).then((_) => _loadProducts());
          } else {
            final created = await Navigator.push<SellerDrop?>(
              context,
              MaterialPageRoute<SellerDrop?>(
                builder: (_) => CreateDropScreen(repository: widget.repository),
              ),
            );
            if (!mounted || !context.mounted || created == null) return;
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CameraIntakeScreen(
                  repository: widget.repository,
                  drop: created,
                  intakeQueue: widget.intakeQueue,
                ),
              ),
            ).then((_) => _loadProducts());
          }
        },
        child: const Icon(Icons.add, size: 30),
      ),
    );
  }

  Widget _buildFilterChip(String label, int count) {
    final isSelected = _selectedFilter == label;
    return InkWell(
      onTap: () {
        setState(() {
          _selectedFilter = label;
          _applyFilters();
        });
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.goldPrimary : AppColors.obsidianSurface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? AppColors.goldPrimary : AppColors.cardBorder,
            width: 1,
          ),
        ),
        child: Text(
          '$label ($count)',
          style: TextStyle(
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            color: isSelected ? Colors.black : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildProductCard(SellerProduct product) {
    final isSold = product.status == ProductStatus.sold;
    final isReserved = product.status == ProductStatus.reserved;

    Color pillColor = AppColors.emerald;
    Color pillTint = AppColors.emeraldTint;
    String pillText = 'Available';

    if (isSold) {
      pillColor = AppColors.crimson;
      pillTint = AppColors.crimsonTint;
      pillText = 'Sold';
    } else if (isReserved) {
      pillColor = AppColors.amber;
      pillTint = AppColors.amberTint;
      pillText = 'On Hold';
    }

    final priceRupees = '₹${(product.pricePaisa / 100).toStringAsFixed(0)}';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.cardDecoration(),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => ProductDetailsScreen(
                product: product,
                repository: widget.repository,
                onProductUpdated: _loadProducts,
              ),
            ),
          );
        },
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 54,
            height: 54,
            color: AppColors.obsidianElevated,
            child: product.imageUrl.isNotEmpty
                ? Image.network(
                    product.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.checkroom_rounded, color: AppColors.goldPrimary, size: 28),
                    ),
                  )
                : const Center(
                    child: Icon(Icons.checkroom_rounded, color: AppColors.goldPrimary, size: 28),
                  ),
          ),
        ),
        title: Text(
          '#${product.code}',
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: AppColors.textPrimary,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              product.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              priceRupees,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppColors.goldPrimary,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: AppTheme.pillDecoration(
                color: pillColor,
                tintColor: pillTint,
              ),
              child: Text(
                pillText,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: pillColor,
                ),
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.more_vert_rounded, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
