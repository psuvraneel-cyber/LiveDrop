import 'dart:io';

import 'package:flutter/material.dart';
import '../../core/services/offline_intake_queue.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/validation/drop_rules.dart';
import '../../data/realtime/seller_live_store.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';
import '../common/load_error_banner.dart';
import '../common/live_refresh.dart';
import '../common/skeleton_loaders.dart';
import '../drops/create_drop_screen.dart';
import '../drops/drops_list_screen.dart';
import '../intake/camera_intake_screen.dart';
import 'product_details_screen.dart';
import 'queued_piece_editor.dart';
import '../../core/services/app_log.dart';

/// Screen 3: Luxury Boutique Products & Inventory Screen
///
/// Pieces captured on this phone that are not live yet are listed separately
/// with their real state — "Syncing", "Retrying" or "Needs attention" — and
/// are never shown as "Available" (SA-INT-001). The list reloads when the
/// [SellerLiveStore] revision changes (SA-RT-001).
class ProductsInventoryScreen extends StatefulWidget {
  final SellerRepository repository;
  final OfflineIntakeQueue? intakeQueue;
  final SellerLiveStore? liveStore;

  const ProductsInventoryScreen({
    super.key,
    required this.repository,
    this.intakeQueue,
    this.liveStore,
  });

  @override
  State<ProductsInventoryScreen> createState() => _ProductsInventoryScreenState();
}

class _ProductsInventoryScreenState extends State<ProductsInventoryScreen>
    with SellerLiveRefreshMixin<ProductsInventoryScreen> {
  bool _isLoading = true;
  Object? _loadError;
  List<SellerProduct> _allProducts = [];
  List<IntakeQueueItem> _queuedItems = [];
  Set<String> _knownCompletedIds = {};
  SellerDrop? _activeDrop;
  String _searchQuery = '';
  String _selectedFilter = 'All'; // All, Available, Reserved, Sold
  int _loadSequence = 0;

  @override
  SellerLiveStore? get liveStore => widget.liveStore;

  @override
  void onLiveRevision() {
    _loadProducts(silent: true);
  }

  @override
  void initState() {
    super.initState();
    widget.intakeQueue?.changes.addListener(_onQueueChanged);
    _loadProducts();
  }

  @override
  void didUpdateWidget(covariant ProductsInventoryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.intakeQueue, widget.intakeQueue)) {
      oldWidget.intakeQueue?.changes.removeListener(_onQueueChanged);
      widget.intakeQueue?.changes.addListener(_onQueueChanged);
      _onQueueChanged();
    }
  }

  @override
  void dispose() {
    widget.intakeQueue?.changes.removeListener(_onQueueChanged);
    super.dispose();
  }

  Set<String> _completedIdsFor(SellerDrop? drop) {
    final queue = widget.intakeQueue;
    if (queue == null || drop == null) return {};
    return queue.items
        .where((i) => i.dropId == drop.id && i.status == IntakeQueueStatus.completed)
        .map((i) => i.id)
        .toSet();
  }

  /// Queue changes are local: recompute the "not live yet" list without a
  /// network call, and refetch products only when a piece has just gone live.
  void _onQueueChanged() {
    if (!mounted) return;
    final completed = _completedIdsFor(_activeDrop);
    final newlyLive = completed.difference(_knownCompletedIds);
    _knownCompletedIds = completed;
    setState(() {
      _queuedItems = _computeQueuedItems(_activeDrop, _allProducts);
    });
    if (newlyLive.isNotEmpty) {
      _loadProducts(silent: true);
    }
  }

  List<IntakeQueueItem> _computeQueuedItems(SellerDrop? drop, List<SellerProduct> products) {
    final queue = widget.intakeQueue;
    if (queue == null || drop == null) return const [];
    final productIds = products.map((p) => p.id).toSet();
    final liveImageUrls = <String>{
      for (final p in products) ...[p.imageUrl, ...p.imageUrls],
    };
    final items = queue.items.where((item) {
      if (item.dropId != drop.id || item.status == IntakeQueueStatus.completed) return false;
      if (item.serverProductId != null && productIds.contains(item.serverProductId)) return false;
      // Uploaded and already live on the server, queue not updated yet.
      if (item.isSyncing && item.remoteImageUrls.any(liveImageUrls.contains)) return false;
      return true;
    }).toList()
      ..sort((a, b) {
        final byPriority = _queuedPriority(a).compareTo(_queuedPriority(b));
        return byPriority != 0 ? byPriority : a.createdAt.compareTo(b.createdAt);
      });
    return items;
  }

  static int _queuedPriority(IntakeQueueItem item) {
    switch (item.status) {
      case IntakeQueueStatus.needsAttention:
        return 0;
      case IntakeQueueStatus.failed:
        return 1;
      default:
        return 2;
    }
  }

  Future<void> _loadProducts({bool silent = false}) async {
    final sequence = ++_loadSequence;
    if (!silent) setState(() => _isLoading = true);
    try {
      final drops = await widget.repository.getDrops();
      final active = _activeDrop != null
          ? drops.where((d) => d.id == _activeDrop!.id).firstOrNull ?? drops.firstOrNull
          : (drops.where((d) => d.status == DropStatus.live).firstOrNull ??
              drops.where((d) => d.status == DropStatus.draft).firstOrNull ??
              drops.firstOrNull);

      final products = active != null
          ? await widget.repository.getProducts(active.id)
          : <SellerProduct>[];
      if (!mounted || sequence != _loadSequence) return;
      setState(() {
        _activeDrop = active;
        _allProducts = products;
        _queuedItems = _computeQueuedItems(active, products);
        _knownCompletedIds = _completedIdsFor(active);
        _isLoading = false;
        _loadError = null;
      });
    } catch (e, st) {
      AppLog.error('products_inventory_screen:161', e, st);
      if (mounted && sequence == _loadSequence) {
        setState(() {
          _isLoading = false;
          _loadError = e;
        });
      }
    }
  }

  bool _matchesSearch(String code, String title, String status) {
    if (_searchQuery.isEmpty) return true;
    final q = _searchQuery.toLowerCase();
    return code.toLowerCase().contains(q) ||
        title.toLowerCase().contains(q) ||
        status.toLowerCase().contains(q);
  }

  /// Pieces not live yet are only listed under "All".
  List<IntakeQueueItem> get _visibleQueuedItems {
    if (_selectedFilter != 'All') return const [];
    return _queuedItems
        .where((i) => _matchesSearch(i.code, i.title, queuedStatusLabel(i)))
        .toList();
  }

  List<SellerProduct> get _visibleProducts {
    var list = _allProducts.where((p) => _matchesSearch(p.code, p.title, p.status.name));
    if (_selectedFilter == 'Available') {
      list = list.where((p) => p.status == ProductStatus.available);
    } else if (_selectedFilter == 'Reserved') {
      list = list.where((p) => p.status == ProductStatus.reserved);
    } else if (_selectedFilter == 'Sold') {
      list = list.where((p) => p.status == ProductStatus.sold);
    }
    return list.toList();
  }

  void _applyFilters() {
    setState(() {});
  }

  Iterable<String> _otherCodesInDrop(IntakeQueueItem item) sync* {
    for (final p in _allProducts) {
      if (p.dropId == item.dropId) yield p.code;
    }
    final queue = widget.intakeQueue;
    if (queue == null) return;
    for (final other in queue.items) {
      if (other.id != item.id &&
          other.dropId == item.dropId &&
          other.status != IntakeQueueStatus.completed) {
        yield other.code;
      }
    }
  }

  /// After an edit / "mark sold" on a product: refresh every tab through the
  /// live store (falls back to reloading only this list without a store).
  void _onProductMutated() {
    final store = widget.liveStore;
    if (store != null) {
      store.requestRefresh(immediate: true);
    } else {
      _loadProducts(silent: true);
    }
  }

  Future<void> _openAttentionSheet() async {
    final queue = widget.intakeQueue;
    if (queue == null) return;
    await showPiecesNeedingAttention(
      context,
      queue: queue,
      repository: widget.repository,
      otherCodesFor: (item) => _otherCodesInDrop(item).toList(),
    );
  }

  Future<void> _onQueuedItemTap(IntakeQueueItem item) async {
    final queue = widget.intakeQueue;
    if (queue == null) return;
    if (item.status == IntakeQueueStatus.needsAttention ||
        item.status == IntakeQueueStatus.failed) {
      await fixQueuedPiece(
        context,
        queue: queue,
        repository: widget.repository,
        item: item,
        otherCodesInDrop: _otherCodesInDrop(item).toList(),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${item.code} is still uploading. It goes live as soon as the upload finishes.'),
        backgroundColor: AppColors.obsidianElevated,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleQueued = _visibleQueuedItems;
    final visibleProducts = _visibleProducts;
    final allCount = _allProducts.length + _queuedItems.length;
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
                  builder: (_) => DropsListScreen(
                    repository: widget.repository,
                    intakeQueue: widget.intakeQueue,
                  ),
                ),
              ).then((_) => _loadProducts());
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: LoadErrorBanner(error: _loadError!, what: 'your pieces', onRetry: _loadProducts),
              ),
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

            // Sync / retry / needs-attention banner
            ?_buildQueueBanner(),

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
                  : visibleProducts.isEmpty && visibleQueued.isEmpty
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
                            itemCount: visibleQueued.length + visibleProducts.length,
                            itemBuilder: (context, index) {
                              if (index < visibleQueued.length) {
                                return _buildQueuedCard(visibleQueued[index]);
                              }
                              return _buildProductCard(visibleProducts[index - visibleQueued.length]);
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
          // A closed drop never receives new pieces (SA-INV-002).
          final target = DropRules.acceptsNewPieces(_activeDrop) ? _activeDrop : null;
          if (target != null) {
            Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => CameraIntakeScreen(
                  repository: widget.repository,
                  drop: target,
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

  /// Banner above the list: pieces needing attention first (tap to fix),
  /// then pieces waiting to retry, then pieces syncing.
  Widget? _buildQueueBanner() {
    final queue = widget.intakeQueue;
    if (queue == null) return null;
    final attention = queue.needsAttentionCount;
    final retrying = queue.failedCount;
    final syncing = queue.syncingCount;

    if (attention > 0) {
      final firstReason = queue.items
          .where((i) => i.status == IntakeQueueStatus.needsAttention)
          .map((i) => i.attentionReason)
          .whereType<String>()
          .firstOrNull;
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: const ValueKey('queue-attention-banner'),
            borderRadius: BorderRadius.circular(10),
            onTap: _openAttentionSheet,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.crimson.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.crimson),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline_rounded, color: AppColors.crimson, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          attention == 1
                              ? '1 piece needs attention — not live yet'
                              : '$attention pieces need attention — not live yet',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          firstReason ?? 'Tap to fix or discard.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
                        ),
                        if (retrying > 0 || syncing > 0)
                          Text(
                            [
                              if (retrying > 0) '$retrying retrying',
                              if (syncing > 0) '$syncing syncing',
                            ].join(' · '),
                            style: const TextStyle(color: AppColors.textMuted, fontSize: 11),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Fix',
                    style: TextStyle(color: AppColors.goldPrimary, fontWeight: FontWeight.bold),
                  ),
                  const Icon(Icons.chevron_right_rounded, color: AppColors.goldPrimary),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (retrying > 0) {
      return Container(
        key: const ValueKey('queue-retry-banner'),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.amberTint,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.amber),
        ),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded, color: AppColors.amber, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    retrying == 1
                        ? '1 upload waiting to retry'
                        : '$retrying uploads waiting to retry',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white, fontSize: 13),
                  ),
                  const Text(
                    'No connection or server busy — retrying automatically.',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  ),
                ],
              ),
            ),
            TextButton.icon(
              onPressed: () async {
                await queue.retryFailed(widget.repository);
              },
              icon: const Icon(Icons.refresh, size: 16, color: AppColors.goldPrimary),
              label: const Text(
                'Retry now',
                style: TextStyle(color: AppColors.goldPrimary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      );
    }

    if (syncing > 0) {
      return Container(
        key: const ValueKey('queue-syncing-banner'),
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
              child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.goldPrimary),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Syncing $syncing piece(s) to cloud...',
                style: const TextStyle(
                  color: AppColors.goldPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return null;
  }

  /// A piece captured on this phone that is not live yet. Never "Available".
  Widget _buildQueuedCard(IntakeQueueItem item) {
    final label = queuedStatusLabel(item);
    final Color pillColor;
    final Color pillTint;
    switch (item.status) {
      case IntakeQueueStatus.needsAttention:
        pillColor = AppColors.crimson;
        pillTint = AppColors.crimsonTint;
        break;
      case IntakeQueueStatus.failed:
        pillColor = AppColors.amber;
        pillTint = AppColors.amberTint;
        break;
      default:
        pillColor = AppColors.goldPrimary;
        pillTint = AppColors.goldMuted;
    }
    final localPhoto = item.localImagePath;

    return Container(
      key: ValueKey('queued-${item.id}'),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: AppTheme.cardDecoration(
        borderColor: item.status == IntakeQueueStatus.needsAttention
            ? AppColors.crimson.withValues(alpha: 0.7)
            : AppColors.cardBorder,
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        onTap: () => _onQueuedItemTap(item),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: 54,
            height: 54,
            color: AppColors.obsidianElevated,
            child: localPhoto.isNotEmpty
                ? Image.file(
                    File(localPhoto),
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => const Center(
                      child: Icon(Icons.cloud_upload_outlined, color: AppColors.goldPrimary, size: 26),
                    ),
                  )
                : const Center(
                    child: Icon(Icons.cloud_upload_outlined, color: AppColors.goldPrimary, size: 26),
                  ),
          ),
        ),
        title: Text(
          item.code,
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
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
            const SizedBox(height: 4),
            Text(
              '₹${(item.pricePaisa / 100).toStringAsFixed(0)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.goldPrimary),
            ),
            if (item.status == IntakeQueueStatus.needsAttention && item.attentionReason != null) ...[
              const SizedBox(height: 4),
              Text(
                item.attentionReason!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: AppColors.crimson, height: 1.3),
              ),
            ],
          ],
        ),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: AppTheme.pillDecoration(color: pillColor, tintColor: pillTint),
          child: Text(
            label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: pillColor),
          ),
        ),
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
    final displayCode = product.code.startsWith('#') ? product.code : '#${product.code}';
    final photoCount = product.imageUrls.isNotEmpty
        ? product.imageUrls.length
        : (product.imageUrl.isNotEmpty ? 1 : 0);

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
                onProductUpdated: _onProductMutated,
              ),
            ),
          );
        },
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 54,
            height: 54,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Container(
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
                if (photoCount > 1)
                  Positioned(
                    bottom: 2,
                    right: 2,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.8),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: AppColors.cardBorder.withValues(alpha: 0.6),
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.collections_rounded, size: 9, color: AppColors.goldPrimary),
                          const SizedBox(width: 2),
                          Text(
                            '$photoCount',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        title: Text(
          displayCode,
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
