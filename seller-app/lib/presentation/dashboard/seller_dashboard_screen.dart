import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/config/env_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../core/theme/boutique_haptics.dart';
import '../../core/utils/url_launcher_helper.dart';
import '../../data/realtime/seller_live_store.dart';
import '../../data/repositories/seller_repository.dart';
import '../../domain/models/models.dart';
import '../common/load_error_banner.dart';
import '../common/live_refresh.dart';
import '../common/skeleton_loaders.dart';
import '../../core/services/app_log.dart';

/// Screen 2: Luxury Boutique Live Dashboard Screen
class SellerDashboardScreen extends StatefulWidget {
  final SellerRepository repository;
  final VoidCallback onNavigateToAddProduct;
  final VoidCallback onNavigateToOrders;
  final VoidCallback onNavigateToPayments;
  final VoidCallback onNavigateToAnalytics;
  final VoidCallback onNavigateToShipping;
  final VoidCallback onManageDrop;

  /// App-level live store (SA-RT-001); the dashboard reloads when its
  /// revision changes and shows its live counts.
  final SellerLiveStore? liveStore;

  const SellerDashboardScreen({
    super.key,
    required this.repository,
    required this.onNavigateToAddProduct,
    required this.onNavigateToOrders,
    required this.onNavigateToPayments,
    required this.onNavigateToAnalytics,
    required this.onNavigateToShipping,
    required this.onManageDrop,
    this.liveStore,
  });

  @override
  State<SellerDashboardScreen> createState() => _SellerDashboardScreenState();
}

class _SellerDashboardScreenState extends State<SellerDashboardScreen>
    with SellerLiveRefreshMixin<SellerDashboardScreen> {
  bool _isLoading = true;
  Object? _loadError;
  SellerProfile? _profile;
  SellerDrop? _activeDrop;
  List<SellerProduct> _activeDropProducts = [];
  int _pendingVerificationCount = 0;
  int _overdueClaimsCount = 0;
  int _refundsOwedCount = 0;
  int _refundsOwedPaisa = 0;
  int _totalOrdersCount = 0;
  List<SellerActivityItem> _recentActivities = [];
  int _loadSequence = 0;

  @override
  SellerLiveStore? get liveStore => widget.liveStore;

  @override
  void onLiveRevision() {
    _loadDashboardData(silent: true);
  }

  @override
  void onLiveStoreNotified() {
    // Live counts (pending claims, refunds owed) changed.
    setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData({bool silent = false}) async {
    final sequence = ++_loadSequence;
    if (!silent) setState(() => _isLoading = true);
    try {
      final profile = await widget.repository.getProfile();
      final drops = await widget.repository.getDrops();
      final active = drops.where((d) => d.status == DropStatus.live).firstOrNull ??
          drops.where((d) => d.status == DropStatus.draft).firstOrNull ??
          drops.firstOrNull;

      List<SellerProduct> products = [];
      if (active != null) {
        try {
          products = await widget.repository.getProducts(active.id);
        } catch (e, st) {
          AppLog.error('seller_dashboard_screen:92', e, st);
        }
      }

      List<SellerOrder> orders = [];
      try {
        orders = await widget.repository.getAllOrders(dropId: active?.id);
      } catch (e, st) {
        AppLog.error('seller_dashboard_screen:98', e, st);
      }

      List<SellerActivityItem> activities = [];
      try {
        activities = await widget.repository.getRecentActivity(dropId: active?.id);
      } catch (e, st) {
        AppLog.error('seller_dashboard_screen:103', e, st);
      }

      int pendingCount = 0;
      int overdueCount = 0;
      try {
        final verifications = await widget.repository.getPendingVerifications();
        final now = DateTime.now();
        pendingCount = verifications.length;
        overdueCount = verifications.where((v) => v.isOverdue(now)).length;
      } catch (e, st) {
        AppLog.error('seller_dashboard_screen:112', e, st);
      }

      int refundsCount = 0;
      int refundsPaisa = 0;
      try {
        final refunds = await widget.repository.getRefundsOwed();
        refundsCount = refunds.length;
        refundsPaisa = refunds.fold<int>(0, (sum, r) => sum + r.refundAmountPaisa);
      } catch (e, st) {
        AppLog.error('seller_dashboard_screen:120', e, st);
      }

      if (mounted && sequence == _loadSequence) {
        setState(() {
          _profile = profile;
          _activeDrop = active;
          _activeDropProducts = products;
          _pendingVerificationCount = pendingCount;
          _overdueClaimsCount = overdueCount;
          _refundsOwedCount = refundsCount;
          _refundsOwedPaisa = refundsPaisa;
          _totalOrdersCount = orders.length;
          _recentActivities = activities;
          _isLoading = false;
          _loadError = null;
        });
      }
    } catch (e, st) {
      AppLog.error('seller_dashboard_screen:136', e, st);
      if (mounted && sequence == _loadSequence) {
        setState(() {
          _isLoading = false;
          _loadError = e;
        });
      }
    }
  }

  /// Live counts from the store once loaded, else this screen's own fetch.
  int get _livePendingCount {
    final store = widget.liveStore;
    return store != null && store.countsLoaded ? store.pendingVerifications : _pendingVerificationCount;
  }

  int get _liveOverdueCount {
    final store = widget.liveStore;
    return store != null && store.countsLoaded ? store.overdueClaims : _overdueClaimsCount;
  }

  int get _liveRefundsCount {
    final store = widget.liveStore;
    return store != null && store.countsLoaded ? store.refundsOwed : _refundsOwedCount;
  }

  int get _liveRefundsPaisa {
    final store = widget.liveStore;
    return store != null && store.countsLoaded ? store.refundsOwedPaisa : _refundsOwedPaisa;
  }

  String _formatDropSubtitle(SellerDrop? drop) {
    if (drop == null) {
      return 'No active drop';
    }
    if (drop.status == DropStatus.live) {
      if (drop.liveStartedAt != null) {
        final diff = DateTime.now().toUtc().difference(drop.liveStartedAt!.toUtc());
        if (diff.inMinutes < 1) return 'Started just now';
        if (diff.inMinutes < 60) return 'Started ${diff.inMinutes} min ago';
        if (diff.inHours < 24) return 'Started ${diff.inHours}h ${diff.inMinutes % 60}m ago';
        return 'Started ${diff.inDays}d ago';
      }
      return 'Currently live';
    } else if (drop.status == DropStatus.draft) {
      return 'Draft — not visible to buyers';
    } else {
      return 'Closed drop';
    }
  }

  Widget _buildDropStatusBadge(SellerDrop? drop) {
    if (drop == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: AppTheme.pillDecoration(
          color: AppColors.textMuted,
          tintColor: AppColors.cardBorder,
        ),
        child: const Text(
          'NO DROP',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
      );
    }

    if (drop.status == DropStatus.live) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: AppTheme.pillDecoration(
          color: AppColors.emerald,
          tintColor: AppColors.emeraldTint,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: AppColors.emerald.withValues(alpha: 0.35),
                    shape: BoxShape.circle,
                  ),
                )
                    .animate(onPlay: (c) => c.repeat())
                    .scale(begin: const Offset(0.6, 0.6), end: const Offset(1.8, 1.8), duration: 1200.ms, curve: Curves.easeOut)
                    .fadeOut(duration: 1200.ms, curve: Curves.easeIn),
                Container(
                  width: 7,
                  height: 7,
                  decoration: const BoxDecoration(
                    color: AppColors.emerald,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 6),
            const Text(
              'LIVE',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: AppColors.emerald,
                letterSpacing: 0.8,
              ),
            ),
          ],
        ),
      );
    } else if (drop.status == DropStatus.draft) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: AppTheme.pillDecoration(
          color: AppColors.amber,
          tintColor: AppColors.amberTint,
        ),
        child: const Text(
          'DRAFT',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: AppColors.amber,
            letterSpacing: 0.8,
          ),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: AppTheme.pillDecoration(
          color: AppColors.textMuted,
          tintColor: AppColors.cardBorder,
        ),
        child: const Text(
          'CLOSED',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            color: AppColors.textMuted,
            letterSpacing: 0.8,
          ),
        ),
      );
    }
  }

  String _formatRelativeTime(DateTime timestamp) {
    final diff = DateTime.now().toUtc().difference(timestamp.toUtc());
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: AppColors.obsidian,
        body: SafeArea(child: DropsListSkeleton()),
      );
    }

    final pendingVerificationCount = _livePendingCount;
    final overdueClaimsCount = _liveOverdueCount;
    final refundsOwedCount = _liveRefundsCount;
    final refundsOwedPaisa = _liveRefundsPaisa;
    final storeName = _profile?.storeName ?? 'Seller Boutique';
    final dropTitle = _activeDrop?.title ?? 'No Active Drop';
    final totalItems = _activeDropProducts.length;
    final onHold = _activeDropProducts.where((p) => p.status == ProductStatus.reserved).length;
    final sold = _activeDropProducts.where((p) => p.status == ProductStatus.sold).length;
    final revenuePaisa = _activeDropProducts
        .where((p) => p.status == ProductStatus.sold)
        .fold<int>(0, (sum, p) => sum + p.pricePaisa);
    final revenueFormatted = '₹${(revenuePaisa / 100).toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))'),
          (m) => '${m[1]},',
        )}';

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.goldPrimary,
          backgroundColor: AppColors.obsidianSurface,
          onRefresh: _loadDashboardData,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              if (_loadError != null)
                LoadErrorBanner(error: _loadError!, what: 'your dashboard', onRetry: _loadDashboardData),
              // Top Greeting & Avatar Row
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Good morning',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.textMuted,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$storeName 👋',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Stack(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.goldPrimary, width: 1.5),
                          color: AppColors.obsidianElevated,
                        ),
                        child: const Center(
                          child: Icon(Icons.person, color: AppColors.goldPrimary, size: 24),
                        ),
                      ),
                      if (pendingVerificationCount > 0)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.crimson,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$pendingVerificationCount',
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 18),

              // Active Drop Hero Card
              Container(
                padding: const EdgeInsets.all(16),
                decoration: AppTheme.cardDecoration(
                  backgroundColor: AppColors.obsidianSurface,
                  shadows: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.4),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Garment Thumbnail
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Container(
                            width: 60,
                            height: 60,
                            color: AppColors.obsidianElevated,
                            child: const Icon(
                              Icons.checkroom_rounded,
                              color: AppColors.goldPrimary,
                              size: 32,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                dropTitle,
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _formatDropSubtitle(_activeDrop),
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              InkWell(
                                onTap: () {
                                  if (_activeDrop != null) {
                                    final url = EnvConfig.getDropUrl(_activeDrop!.slug);
                                    UrlLauncherHelper.launchExternalWebUrl(context: context, url: url);
                                  } else {
                                    widget.onManageDrop();
                                  }
                                },
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'View on Web',
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.goldPrimary,
                                      ),
                                    ),
                                    SizedBox(width: 3),
                                    Icon(Icons.north_east_rounded, size: 12, color: AppColors.goldPrimary),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        // Drop Status Badge (LIVE pulsing, DRAFT, CLOSED)
                        _buildDropStatusBadge(_activeDrop),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const Divider(color: AppColors.cardBorder, height: 1),
                    const SizedBox(height: 14),

                    // 4-Metric Grid Row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _buildMetricCol('$totalItems', 'Items'),
                        _buildMetricCol('$onHold', 'On Hold', valueColor: AppColors.amber),
                        _buildMetricCol('$sold', 'Sold', valueColor: AppColors.crimson),
                        _buildMetricCol(revenueFormatted, 'Revenue', valueColor: AppColors.goldPrimary),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // Money that needs the seller's action (SA-PAY-003 / SA-PAY-004)
              if (refundsOwedCount > 0) ...[
                _buildAlertTile(
                  key: const ValueKey('home-refunds-owed'),
                  icon: Icons.currency_rupee_rounded,
                  title: 'Refunds owed: $refundsOwedCount',
                  subtitle: '${_formatRupees(refundsOwedPaisa)} to send back to buyers — tap to settle',
                  onTap: widget.onNavigateToPayments,
                ),
                const SizedBox(height: 10),
              ],
              if (overdueClaimsCount > 0) ...[
                _buildAlertTile(
                  key: const ValueKey('home-overdue-claims'),
                  icon: Icons.schedule_rounded,
                  title: overdueClaimsCount == 1
                      ? '1 payment claim is overdue'
                      : '$overdueClaimsCount payment claims are overdue',
                  subtitle: 'Buyers are waiting — verify or reject in Payments',
                  onTap: widget.onNavigateToPayments,
                ),
                const SizedBox(height: 10),
              ],
              if (refundsOwedCount > 0 || overdueClaimsCount > 0) const SizedBox(height: 12),

              // 6 Quick Action Grid
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1.05,
                children: [
                  _buildQuickActionTile(
                    title: 'Add Product',
                    icon: Icons.camera_alt_outlined,
                    onTap: widget.onNavigateToAddProduct,
                  ),
                  _buildQuickActionTile(
                    title: 'View Orders',
                    icon: Icons.receipt_long_outlined,
                    badgeCount: _totalOrdersCount > 0 ? _totalOrdersCount : null,
                    onTap: widget.onNavigateToOrders,
                  ),
                  _buildQuickActionTile(
                    title: 'Verify Payments',
                    icon: Icons.verified_outlined,
                    badgeCount: pendingVerificationCount > 0 ? pendingVerificationCount : null,
                    badgeColor: AppColors.crimson,
                    onTap: widget.onNavigateToPayments,
                  ),
                  _buildQuickActionTile(
                    title: 'Manage Drop',
                    icon: Icons.storefront_outlined,
                    onTap: widget.onManageDrop,
                  ),
                  _buildQuickActionTile(
                    title: 'Analytics',
                    icon: Icons.bar_chart_rounded,
                    onTap: widget.onNavigateToAnalytics,
                  ),
                  _buildQuickActionTile(
                    title: 'Shipping',
                    icon: Icons.local_shipping_outlined,
                    onTap: widget.onNavigateToShipping,
                  ),
                ],
              ),
              const SizedBox(height: 22),

              // Recent Activity Section
              const Text(
                'Recent Activity',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),

              if (_recentActivities.isEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: AppTheme.cardDecoration(),
                  child: const Center(
                    child: Column(
                      children: [
                        Icon(Icons.history_toggle_off_rounded, size: 40, color: AppColors.textMuted),
                        SizedBox(height: 8),
                        Text(
                          'No activity in this drop yet',
                          style: TextStyle(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Orders and payment claims will appear here in real-time.',
                          style: TextStyle(fontSize: 12, color: AppColors.textMuted),
                        ),
                      ],
                    ),
                  ),
                )
              else
                ..._recentActivities.map((act) {
                  IconData icon;
                  Color iconColor;
                  Color iconBg;

                  switch (act.type) {
                    case 'payment_claim':
                      icon = Icons.credit_card_rounded;
                      iconColor = AppColors.emerald;
                      iconBg = AppColors.emeraldTint;
                      break;
                    case 'order_shipped':
                      icon = Icons.local_shipping_outlined;
                      iconColor = AppColors.goldPrimary;
                      iconBg = AppColors.goldMuted;
                      break;
                    case 'order_paid':
                      icon = Icons.verified_outlined;
                      iconColor = AppColors.emerald;
                      iconBg = AppColors.emeraldTint;
                      break;
                    case 'order_placed':
                    default:
                      icon = Icons.lock_clock_rounded;
                      iconColor = AppColors.amber;
                      iconBg = AppColors.amberTint;
                      break;
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildActivityRow(
                      icon: icon,
                      iconColor: iconColor,
                      iconBg: iconBg,
                      title: act.title,
                      time: _formatRelativeTime(act.timestamp),
                    ),
                  );
                }),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  String _formatRupees(int paisa) {
    final rupees = (paisa / 100).toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d+?)(?=(\d\d)+(\d)(?!\d))'),
          (m) => '${m[1]},',
        );
    return '₹$rupees';
  }

  Widget _buildAlertTile({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: () {
        BoutiqueHaptics.light();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: AppTheme.cardDecoration(
          backgroundColor: AppColors.crimsonTint,
          borderColor: AppColors.crimson.withValues(alpha: 0.7),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: AppColors.crimsonTint,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: AppColors.crimson, size: 18),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: AppColors.crimson),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCol(String value, String label, {Color valueColor = AppColors.textPrimary}) {
    final isRupee = value.startsWith('₹');
    final numStr = isRupee ? value.replaceFirst('₹', '').replaceAll(',', '') : value;
    final numVal = double.tryParse(numStr);

    Widget textWidget;
    if (numVal != null && numVal > 0) {
      textWidget = TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: numVal),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (context, val, child) {
          final formatted = isRupee
              ? (val >= 1000 ? '₹${(val / 1000).toStringAsFixed(1)}k' : '₹${val.toStringAsFixed(0)}')
              : val.toInt().toString();
          return Text(
            formatted,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: valueColor,
            ),
          );
        },
      );
    } else {
      textWidget = Text(
        value,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: valueColor,
        ),
      );
    }

    return Column(
      children: [
        textWidget,
        const SizedBox(height: 2),
        Text(
          label,
          style: const TextStyle(
            fontSize: 11,
            color: AppColors.textMuted,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildQuickActionTile({
    required String title,
    required IconData icon,
    required VoidCallback onTap,
    int? badgeCount,
    Color badgeColor = AppColors.crimson,
  }) {
    return InkWell(
      onTap: () {
        BoutiqueHaptics.light();
        onTap();
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: AppTheme.cardDecoration(
          backgroundColor: AppColors.obsidianSurface,
        ),
        padding: const EdgeInsets.all(10),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: AppColors.goldPrimary, size: 26),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
            if (badgeCount != null && badgeCount > 0)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '$badgeCount',
                    style: const TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildActivityRow({
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String time,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: AppTheme.cardDecoration(backgroundColor: AppColors.obsidianSurface),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          Text(
            time,
            style: const TextStyle(
              fontSize: 11,
              color: AppColors.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
