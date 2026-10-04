import 'package:flutter/material.dart';
import '../../core/errors/exceptions.dart';
import '../../core/theme/app_colors.dart';
import '../../data/realtime/seller_live_store.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';
import '../common/live_refresh.dart';
import '../common/skeleton_loaders.dart';
import 'order_actions.dart';
import 'order_card.dart';

/// Asks the Orders board to show one pipeline tab. The home shell uses it so
/// the dashboard "Shipping" shortcut opens the Ready-to-ship list instead of
/// acting on an order by itself (SA-SHIP-001).
class OrdersTabRequest extends ChangeNotifier {
  int? _tab;

  /// The most recently requested tab index, if any.
  int? get tab => _tab;

  void show(int tab) {
    _tab = tab;
    notifyListeners();
  }
}

/// Screen 6: Luxury Boutique Orders Kanban Pipeline Screen
/// 4 Pipeline Tabs: Pending, Paid, Ready, Shipped
///
/// Live updates come from the app-level [SellerLiveStore] (SA-RT-001): the
/// board reloads its current selection — "All Drops" or one drop — whenever
/// the store's revision changes.
class KanbanBoardScreen extends StatefulWidget {
  final SellerRepository repository;
  final SellerLiveStore? liveStore;

  /// Optional external tab switching (see [OrdersTabRequest]).
  final OrdersTabRequest? tabRequest;

  static const int pendingTabIndex = 0;
  static const int paidTabIndex = 1;
  static const int readyTabIndex = 2;
  static const int shippedTabIndex = 3;

  const KanbanBoardScreen({
    super.key,
    required this.repository,
    this.liveStore,
    this.tabRequest,
  });

  @override
  State<KanbanBoardScreen> createState() => _KanbanBoardScreenState();
}

class _KanbanBoardScreenState extends State<KanbanBoardScreen>
    with SingleTickerProviderStateMixin, SellerLiveRefreshMixin<KanbanBoardScreen> {
  late TabController _tabController;
  List<SellerOrder> _allOrders = [];
  List<SellerDrop> _drops = [];
  SellerProfile? _profile;
  String? _selectedDropId;
  String _searchQuery = '';
  bool _isLoading = true;
  String? _errorMessage;
  int _ordersLoadSequence = 0;

  @override
  SellerLiveStore? get liveStore => widget.liveStore;

  @override
  void onLiveRevision() {
    _refreshOrders();
  }

  @override
  void initState() {
    super.initState();
    final requested = widget.tabRequest?.tab;
    _tabController = TabController(
      length: 5,
      vsync: this,
      initialIndex: (requested != null && requested >= 0 && requested < 4) ? requested : 0,
    );
    widget.tabRequest?.addListener(_onTabRequested);
    _loadInitialData();
  }

  @override
  void didUpdateWidget(covariant KanbanBoardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabRequest != widget.tabRequest) {
      oldWidget.tabRequest?.removeListener(_onTabRequested);
      widget.tabRequest?.addListener(_onTabRequested);
    }
  }

  @override
  void dispose() {
    widget.tabRequest?.removeListener(_onTabRequested);
    _tabController.dispose();
    super.dispose();
  }

  void _onTabRequested() {
    final tab = widget.tabRequest?.tab;
    if (!mounted || tab == null || tab < 0 || tab >= _tabController.length) return;
    _tabController.animateTo(tab);
    // Show fresh data for the requested list (e.g. orders just marked ready).
    _refreshOrders();
  }

  Future<void> _loadInitialData() async {
    final sequence = ++_ordersLoadSequence;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final profileFuture = widget.repository.getProfile();
      final dropsFuture = widget.repository.getDrops();
      final ordersFuture = widget.repository.getAllOrders(dropId: _selectedDropId);

      final results = await Future.wait([profileFuture, dropsFuture, ordersFuture]);
      if (mounted && sequence == _ordersLoadSequence) {
        setState(() {
          _profile = results[0] as SellerProfile;
          _drops = results[1] as List<SellerDrop>;
          _allOrders = results[2] as List<SellerOrder>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted && sequence == _ordersLoadSequence) {
        setState(() {
          _isLoading = false;
          _errorMessage = e is LiveDropException ? e.message : 'Could not load orders. Check your connection and retry.';
        });
      }
    }
  }

  Future<void> _refreshOrders() async {
    final sequence = ++_ordersLoadSequence;
    try {
      final orders = await widget.repository.getAllOrders(dropId: _selectedDropId);
      if (mounted && sequence == _ordersLoadSequence) {
        setState(() {
          _allOrders = orders;
        });
      }
    } catch (_) {
      // Keep the orders already on screen; the next live update or a pull
      // to refresh will try again.
    }
  }

  /// After an action on a card: refresh every tab through the live store
  /// (falls back to refreshing only this board when there is no store).
  void _onOrderMutated() {
    final store = widget.liveStore;
    if (store != null) {
      store.requestRefresh(immediate: true);
    } else {
      _refreshOrders();
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

  /// Cancelled and expired orders, with their reason on the card (SA-ORD-004).
  List<SellerOrder> get _closedOrders => _filterOrders(
        _allOrders.where(OrderActions.isClosed).toList(),
      );

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
                o.status != OrderStatus.shipped &&
                !OrderActions.isClosed(o))
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

              // Pipeline tabs + Closed (SA-ORD-004); scrollable on phones.
              TabBar(
                controller: _tabController,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                indicatorColor: AppColors.goldPrimary,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: AppColors.goldPrimary,
                unselectedLabelColor: AppColors.textSecondary,
                tabs: [
                  Tab(text: 'Pending (${_pendingOrders.length})'),
                  Tab(text: 'Paid (${_paidOrders.length})'),
                  Tab(text: 'Ready (${_readyOrders.length})'),
                  Tab(text: 'Shipped (${_shippedOrders.length})'),
                  Tab(text: 'Closed (${_closedOrders.length})'),
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
                    _buildOrderList(_closedOrders, 'No cancelled or expired orders.'),
                  ],
                ),
    );
  }

  Widget _buildOrderList(List<SellerOrder> orders, String emptyText) {
    // Cards need the real profile (store name in messages); never a
    // placeholder one (SA-UX-002).
    final profile = _profile;
    if (profile == null && orders.isNotEmpty) {
      return const Center(child: CircularProgressIndicator(color: AppColors.goldPrimary));
    }
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
            profile: profile!,
            repository: widget.repository,
            onOrderUpdated: _onOrderMutated,
          );
        },
      ),
    );
  }
}
