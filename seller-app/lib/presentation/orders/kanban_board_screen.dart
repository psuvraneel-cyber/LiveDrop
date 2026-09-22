import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/errors/exceptions.dart';
import '../../core/theme/app_colors.dart';
import '../../data/realtime/seller_order_realtime.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';
import '../common/skeleton_loaders.dart';
import 'order_card.dart';

/// Screen 6: Luxury Boutique Orders Kanban Pipeline Screen
/// 4 Pipeline Tabs: Pending, Paid, Ready, Shipped
class KanbanBoardScreen extends StatefulWidget {
  final SellerRepository repository;

  const KanbanBoardScreen({
    super.key,
    required this.repository,
  });

  @override
  State<KanbanBoardScreen> createState() => _KanbanBoardScreenState();
}

class _KanbanBoardScreenState extends State<KanbanBoardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<SellerOrder> _allOrders = [];
  List<SellerDrop> _drops = [];
  SellerProfile? _profile;
  String? _selectedDropId;
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;

  SellerOrderRealtimeSubscription? _realtimeSubscription;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadInitialData();
  }

  @override
  void dispose() {
    _realtimeSubscription?.unsubscribe();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profileFuture = widget.repository.getProfile();
      final dropsFuture = widget.repository.getDrops();
      final ordersFuture = widget.repository.getAllOrders(dropId: _selectedDropId);

      final results = await Future.wait([profileFuture, dropsFuture, ordersFuture]);
      if (mounted) {
        setState(() {
          _profile = results[0] as SellerProfile;
          _drops = results[1] as List<SellerDrop>;
          _allOrders = results[2] as List<SellerOrder>;
          _isLoading = false;
        });

        _setupRealtime();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e is LiveDropException ? e.message : e.toString();
        });
      }
    }
  }

  Future<void> _refreshOrders() async {
    try {
      final orders = await widget.repository.getAllOrders(dropId: _selectedDropId);
      if (mounted) {
        setState(() {
          _allOrders = orders;
        });
      }
    } catch (_) {}
  }

  void _setupRealtime() {
    _realtimeSubscription?.unsubscribe();
    if (_selectedDropId != null) {
      _realtimeSubscription = SellerOrderRealtimeSubscription(
        dropId: _selectedDropId!,
        onOrderCreated: (newOrder) => _refreshOrders(),
        onOrderUpdated: (updatedOrder) => _refreshOrders(),
      );
      _realtimeSubscription!.subscribe();
    }
  }

  List<SellerOrder> _filterOrders(List<SellerOrder> orders) {
    if (_searchQuery.trim().isEmpty) return orders;
    final q = _searchQuery.trim().toLowerCase();

    return orders.where((o) {
      final matchCode = o.orderCode.toLowerCase().contains(q);
      final matchBuyer = o.buyerName.toLowerCase().contains(q);
      final matchPhone = o.buyerPhone.contains(q);
      final matchItems = o.items.any((it) =>
          (it.productCode?.toLowerCase().contains(q) ?? false) ||
          (it.productTitle?.toLowerCase().contains(q) ?? false));
      return matchCode || matchBuyer || matchPhone || matchItems;
    }).toList();
  }

  List<SellerOrder> get _pendingOrders => _filterOrders(
        _allOrders.where((o) => o.status == OrderStatus.pending).toList(),
      );

  List<SellerOrder> get _paidOrders => _filterOrders(
        _allOrders
            .where((o) =>
                (o.status == OrderStatus.paid ||
                    o.status == OrderStatus.confirmed ||
                    o.paymentStatus == OrderPaymentStatus.advancePaid) &&
                o.fulfilmentStatus != OrderFulfilmentStatus.readyToShip &&
                o.status != OrderStatus.shipped)
            .toList(),
      );

  List<SellerOrder> get _readyOrders => _filterOrders(
        _allOrders
            .where((o) =>
                o.fulfilmentStatus == OrderFulfilmentStatus.readyToShip &&
                o.status != OrderStatus.shipped)
            .toList(),
      );

  List<SellerOrder> get _shippedOrders => _filterOrders(
        _allOrders
            .where((o) =>
                o.status == OrderStatus.shipped ||
                o.fulfilmentStatus == OrderFulfilmentStatus.shipped)
            .toList(),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      appBar: AppBar(
        title: const Text('Orders', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _refreshOrders,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(105),
          child: Column(
            children: [
              // Search & Drop Selector Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    // Search Input
                    Expanded(
                      flex: 5,
                      child: TextField(
                        style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                        decoration: InputDecoration(
                          hintText: 'Search by order, buyer, code...',
                          prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.textMuted),
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 16, color: AppColors.textMuted),
                                  onPressed: () => setState(() => _searchQuery = ''),
                                )
                              : null,
                        ),
                        onChanged: (val) => setState(() => _searchQuery = val),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Drop Selector
                    Expanded(
                      flex: 4,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: AppColors.obsidianSurface,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppColors.cardBorder),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String?>(
                            value: _selectedDropId,
                            isExpanded: true,
                            dropdownColor: AppColors.obsidianSurface,
                            style: const TextStyle(color: AppColors.textPrimary, fontSize: 13),
                            hint: const Text('All Drops', style: TextStyle(color: AppColors.textSecondary)),
                            items: [
                              const DropdownMenuItem<String?>(
                                value: null,
                                child: Text('All Drops'),
                              ),
                              ..._drops.map((d) => DropdownMenuItem<String?>(
                                    value: d.id,
                                    child: Text(d.title, overflow: TextOverflow.ellipsis),
                                  )),
                            ],
                            onChanged: (val) {
                              setState(() => _selectedDropId = val);
                              _loadInitialData();
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 4 Pipeline Tabs
              TabBar(
                controller: _tabController,
                indicatorColor: AppColors.goldPrimary,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: AppColors.goldPrimary,
                unselectedLabelColor: AppColors.textSecondary,
                tabs: [
                  Tab(text: 'Pending (${_pendingOrders.length})'),
                  Tab(text: 'Paid (${_paidOrders.length})'),
                  Tab(text: 'Ready (${_readyOrders.length})'),
                  Tab(text: 'Shipped (${_shippedOrders.length})'),
                ],
              ),
            ],
          ),
        ),
      ),
      body: _isLoading
          ? const KanbanSkeleton()
          : _errorMessage != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: AppColors.crimson),
                      const SizedBox(height: 12),
                      Text(_errorMessage!, style: const TextStyle(color: AppColors.textSecondary)),
                      const SizedBox(height: 16),
                      ElevatedButton(onPressed: _loadInitialData, child: const Text('Retry')),
                    ],
                  ),
                )
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildOrderList(_pendingOrders, 'No pending orders awaiting payment.'),
                    _buildOrderList(_paidOrders, 'No paid orders waiting for verification or packing.'),
                    _buildOrderList(_readyOrders, 'No orders marked ready for shipping.'),
                    _buildOrderList(_shippedOrders, 'No dispatched orders yet.'),
                  ],
                ),
    );
  }

  Widget _buildOrderList(List<SellerOrder> orders, String emptyText) {
    if (orders.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.inbox_outlined, size: 52, color: AppColors.textMuted),
            const SizedBox(height: 12),
            Text(
              emptyText,
              style: const TextStyle(color: AppColors.textSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: AppColors.goldPrimary,
      backgroundColor: AppColors.obsidianSurface,
      onRefresh: _refreshOrders,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: orders.length,
        itemBuilder: (ctx, i) {
          final order = orders[i];
          return OrderCard(
            order: order,
            profile: _profile ??
                SellerProfile(
                  id: order.dropId,
                  storeName: 'Boutique Store',
                  storeSlug: 'store',
                  phoneNumber: '+91 9999999999',
                  upiId: 'store@upi',
                  returnAddress: 'Boutique Studio, India',
                  defaultShippingFeePaisa: 8000,
                  advanceConfirmationEnabled: false,
                  advanceAmountPaisa: 25000,
                  holdDurationDays: 30,
                ),
            repository: widget.repository,
            onOrderUpdated: _refreshOrders,
          );
        },
      ),
    );
  }
}
