import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/env_config.dart';
import 'core/errors/seller_error_messages.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/boutique_haptics.dart';
import 'core/validation/drop_rules.dart';
import 'data/realtime/seller_live_store.dart';
import 'data/repositories/seller_repository.dart';
import 'domain/models/models.dart';
import 'core/services/offline_intake_queue.dart';
import 'presentation/analytics/seller_analytics_screen.dart';
import 'presentation/auth/seller_login_screen.dart';
import 'presentation/auth/seller_pending_approval_screen.dart';
import 'presentation/common/live_refresh.dart';
import 'presentation/configuration_error_screen.dart';
import 'presentation/dashboard/seller_dashboard_screen.dart';
import 'presentation/drops/create_drop_screen.dart';
import 'presentation/drops/drops_list_screen.dart';
import 'presentation/intake/camera_intake_screen.dart';
import 'presentation/orders/kanban_board_screen.dart';
import 'presentation/pending_verifications_screen.dart';
import 'presentation/products/products_inventory_screen.dart';
import 'presentation/settings/seller_settings_screen.dart';
import 'presentation/splash/animated_splash_screen.dart';

export 'presentation/auth/seller_login_screen.dart' show SellerLoginScreen;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BoutiqueHaptics.loadPreference();

  String? initError;
  try {
    EnvConfig.validate();
    await SupabaseService.instance.initialize();
  } catch (err) {
    debugPrint('[LiveDrop Seller] Error initializing Supabase: $err');
    initError = err.toString();
  }

  runApp(LiveDropSellerApp(initializationError: initError));
}

/// Root Application Widget for LiveDrop Seller App
class LiveDropSellerApp extends StatelessWidget {
  final SellerRepository? repository;
  final String? initializationError;
  final bool? enableSplash;

  const LiveDropSellerApp({
    super.key,
    this.repository,
    this.initializationError,
    this.enableSplash,
  });

  bool get _shouldShowSplash {
    if (enableSplash != null) return enableSplash!;
    // In widget tests, avoid holding the test pump with splash timer
    final binding = WidgetsBinding.instance;
    final isTest = binding.runtimeType.toString().contains('TestWidgetsFlutterBinding');
    return !isTest;
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LiveDrop Seller',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.darkTheme,
      home: initializationError != null
          ? ConfigurationErrorScreen(
              errorMessage: initializationError!,
              onRetry: () async {
                try {
                  EnvConfig.validate();
                  await SupabaseService.instance.initialize();
                  runApp(const LiveDropSellerApp());
                } catch (e) {
                  debugPrint('[LiveDrop Seller] Retry failed: $e');
                }
              },
            )
          : _shouldShowSplash
              ? AnimatedSplashScreen(
                  onNavigationTarget: (isAuth) =>
                      SellerAuthGate(customRepository: repository),
                )
              : SellerAuthGate(customRepository: repository),
    );
  }
}

/// Authentication Gate: Directs to Login or Home Screen based on session
class SellerAuthGate extends StatefulWidget {
  final SellerRepository? customRepository;

  const SellerAuthGate({super.key, this.customRepository});

  @override
  State<SellerAuthGate> createState() => _SellerAuthGateState();
}

class _SellerAuthGateState extends State<SellerAuthGate> {
  bool _isChecking = true;
  bool _isAuthenticated = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _checkAuth();

    if (SupabaseService.instance.isInitialized) {
      _authSubscription = SupabaseService.instance.authStateChanges.listen((data) {
        if (mounted) {
          setState(() {
            _isAuthenticated = data.session != null;
          });
        }
      });
    }
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    super.dispose();
  }

  void _checkAuth() {
    try {
      final isAuth = SupabaseService.instance.isAuthenticated;
      setState(() {
        _isAuthenticated = isAuth;
        _isChecking = false;
      });
    } catch (_) {
      setState(() {
        _isAuthenticated = false;
        _isChecking = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        backgroundColor: AppColors.obsidian,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.goldPrimary),
        ),
      );
    }

    if (_isAuthenticated) {
      final repo = widget.customRepository ?? SellerRepository();
      return SellerHomeScreen(repository: repo);
    }

    return SellerLoginScreen(
      onLoginSuccess: () {
        setState(() {
          _isAuthenticated = true;
        });
      },
    );
  }
}

/// Seller Main Navigation Shell (5-Tab Luxury Boutique Operations)
///
/// Owns the app-level [SellerLiveStore] for the signed-in seller (SA-RT-001):
/// one Realtime channel drives live reloads of Home, Products, Orders and
/// Payments and the Payments badge. The shell only exists while a session
/// exists, so signing out disposes the store and closes the channel.
class SellerHomeScreen extends StatefulWidget {
  final SellerRepository repository;

  /// Injected store (tests). When null the shell creates and owns one.
  final SellerLiveStore? liveStore;

  /// Injected intake queue (tests). When null the shell creates and owns one.
  final OfflineIntakeQueue? intakeQueue;

  const SellerHomeScreen({
    super.key,
    required this.repository,
    this.liveStore,
    this.intakeQueue,
  });

  @override
  State<SellerHomeScreen> createState() => _SellerHomeScreenState();
}

class _SellerHomeScreenState extends State<SellerHomeScreen> with WidgetsBindingObserver {
  int _currentIndex = 0;
  SellerProfile? _profile;

  /// Approval gate state (SA-AUTH-002): the dashboard is shown only for a
  /// loaded, approved profile. Loading and load errors never fail open.
  bool _profileLoading = true;
  Object? _profileError;
  late final OfflineIntakeQueue _sharedIntakeQueue;
  late final bool _ownsIntakeQueue;
  final OrdersTabRequest _ordersTabRequest = OrdersTabRequest();
  late final SellerLiveStore _liveStore;
  late final bool _ownsLiveStore;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ownsIntakeQueue = widget.intakeQueue == null;
    _sharedIntakeQueue = widget.intakeQueue ?? OfflineIntakeQueue();
    _ownsLiveStore = widget.liveStore == null;
    _liveStore = widget.liveStore ??
        SellerLiveStore(
          repository: widget.repository,
          source: SellerLiveStore.defaultSource(),
        );
    unawaited(_liveStore.start());
    unawaited(_startUp());
  }

  /// The shell only exists while a seller is signed in: load the profile,
  /// then resume any intake pieces queued on this phone (SA-OFF-001) instead
  /// of waiting for the camera screen to be reopened.
  Future<void> _startUp() async {
    await _loadProfile();
    await _syncIntakeQueue();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_syncIntakeQueue());
    }
  }

  /// Uploads queued intake pieces. Skipped for a seller known to be awaiting
  /// approval; the queue itself classifies failures (transient vs. needs
  /// attention) and never throws here.
  Future<void> _syncIntakeQueue() async {
    if (!mounted) return;
    final profile = _profile;
    if (profile == null || !profile.isApproved) return;
    try {
      await _sharedIntakeQueue.initialize();
      if (!mounted) return;
      await _sharedIntakeQueue.processQueue(widget.repository);
    } catch (e) {
      debugPrint('[LiveDrop Seller] Intake queue sync skipped: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_ownsLiveStore) {
      _liveStore.dispose();
    }
    if (_ownsIntakeQueue) {
      _sharedIntakeQueue.dispose();
    }
    _ordersTabRequest.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    if (mounted && _profile == null) {
      setState(() {
        _profileLoading = true;
        _profileError = null;
      });
    }
    try {
      final p = await widget.repository.getProfile();
      if (mounted) {
        setState(() {
          _profile = p;
          _profileLoading = false;
          _profileError = null;
        });
      }
    } catch (e) {
      debugPrint('[LiveDrop Seller] Profile load failed: $e');
      if (mounted) {
        setState(() {
          _profileLoading = false;
          // A refresh failure keeps an already loaded profile (and its gate).
          if (_profile == null) _profileError = e;
        });
      }
    }
  }

  Future<void> _retryProfile() async {
    await _loadProfile();
    await _syncIntakeQueue();
  }

  void _navigateToTab(int index) {
    setState(() => _currentIndex = index);
  }

  void _openAddProduct() async {
    try {
      final drops = await widget.repository.getDrops();
      // Never a closed drop (SA-INV-002): without a live or draft drop the
      // seller creates a new one first.
      final active = DropRules.intakeTarget(drops);

      if (!mounted) return;

      if (active != null) {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => CameraIntakeScreen(
              drop: active,
              repository: widget.repository,
              intakeQueue: _sharedIntakeQueue,
            ),
          ),
        );
      } else {
        final created = await Navigator.push<SellerDrop?>(
          context,
          MaterialPageRoute<SellerDrop?>(
            builder: (_) => CreateDropScreen(repository: widget.repository),
          ),
        );
        if (!mounted || created == null) return;
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => CameraIntakeScreen(
              drop: created,
              repository: widget.repository,
              intakeQueue: _sharedIntakeQueue,
            ),
          ),
        );
      }
    } catch (_) {
      _navigateToTab(1);
    }
  }

  void _openManageDrops() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => DropsListScreen(
          repository: widget.repository,
          intakeQueue: _sharedIntakeQueue,
        ),
      ),
    );
  }

  void _openAnalytics() {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SellerAnalyticsScreen(repository: widget.repository),
      ),
    );
  }

  /// Dashboard "Shipping" shortcut (SA-SHIP-001): never ships anything by
  /// itself. It opens the Orders tab on the "Ready" (ready-to-ship) list,
  /// where each order is dispatched with the seller's real tracking number.
  void _openShipping() {
    _ordersTabRequest.show(KanbanBoardScreen.readyTabIndex);
    _navigateToTab(2); // Orders tab
  }

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    if (profile == null) {
      if (_profileLoading) {
        return const Scaffold(
          backgroundColor: AppColors.obsidian,
          body: Center(child: CircularProgressIndicator(color: AppColors.goldPrimary)),
        );
      }
      return _ProfileLoadErrorScreen(
        error: _profileError,
        onRetry: _retryProfile,
        onSignOut: () async {
          await SupabaseService.instance.signOut();
        },
      );
    }
    if (!profile.isApproved) {
      return SellerPendingApprovalScreen(
        onRefreshStatus: _loadProfile,
        onSignOut: () async {
          await SupabaseService.instance.signOut();
        },
      );
    }

    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Home / Live Dashboard (Screen 2)
          LiveTabVisibility(
            visible: _currentIndex == 0,
            child: SellerDashboardScreen(
              repository: widget.repository,
              liveStore: _liveStore,
              onNavigateToAddProduct: _openAddProduct,
              onNavigateToOrders: () => _navigateToTab(2),
              onNavigateToPayments: () => _navigateToTab(3),
              onNavigateToAnalytics: _openAnalytics,
              onNavigateToShipping: _openShipping,
              onManageDrop: _openManageDrops,
            ),
          ),
          // Tab 1: Products & Inventory (Screen 3)
          LiveTabVisibility(
            visible: _currentIndex == 1,
            child: ProductsInventoryScreen(
              repository: widget.repository,
              intakeQueue: _sharedIntakeQueue,
              liveStore: _liveStore,
            ),
          ),
          // Tab 2: Orders Kanban (Screen 6)
          LiveTabVisibility(
            visible: _currentIndex == 2,
            child: KanbanBoardScreen(
              repository: widget.repository,
              liveStore: _liveStore,
              tabRequest: _ordersTabRequest,
            ),
          ),
          // Tab 3: Payment Verifications (Screen 7)
          LiveTabVisibility(
            visible: _currentIndex == 3,
            child: Scaffold(
              backgroundColor: AppColors.obsidian,
              appBar: AppBar(
                title: const Text('Verify Payments', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              body: PendingVerificationsScreen(
                repository: widget.repository,
                liveStore: _liveStore,
              ),
            ),
          ),
          // Tab 4: Settings & More (Screen 11)
          SellerSettingsScreen(repository: widget.repository),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: AppColors.obsidianSurface,
          border: Border(top: BorderSide(color: AppColors.cardBorder, width: 1)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: ListenableBuilder(
              listenable: _liveStore,
              builder: (context, _) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
                  _buildNavItem(1, Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Products'),
                  _buildNavItem(2, Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Orders'),
                  _buildNavItem(
                    3,
                    Icons.verified_outlined,
                    Icons.verified_rounded,
                    'Payments',
                    badgeCount: _liveStore.paymentsBadgeCount,
                  ),
                  _buildNavItem(4, Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More'),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(
    int index,
    IconData unselectedIcon,
    IconData selectedIcon,
    String label, {
    int badgeCount = 0,
  }) {
    final isSelected = _currentIndex == index;
    final icon = Icon(
      isSelected ? selectedIcon : unselectedIcon,
      color: isSelected ? AppColors.goldPrimary : AppColors.textMuted,
      size: 22,
    );

    return InkWell(
      onTap: () => _navigateToTab(index),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.goldMuted : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (badgeCount > 0)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  icon,
                  Positioned(
                    right: -10,
                    top: -6,
                    child: Container(
                      key: ValueKey('nav-badge-$label'),
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      constraints: const BoxConstraints(minWidth: 16),
                      decoration: BoxDecoration(
                        color: AppColors.crimson,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              )
            else
              icon,
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                color: isSelected ? AppColors.goldPrimary : AppColors.textMuted,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when the seller's profile cannot be loaded (SA-AUTH-002). The app
/// does not know whether the account is approved, so nothing operational is
/// offered until the profile loads.
class _ProfileLoadErrorScreen extends StatelessWidget {
  final Object? error;
  final Future<void> Function() onRetry;
  final Future<void> Function() onSignOut;

  const _ProfileLoadErrorScreen({
    required this.error,
    required this.onRetry,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final offline = SellerErrorMessages.isNetworkError(error);
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                    color: AppColors.goldPrimary, size: 48),
                const SizedBox(height: 16),
                const Text(
                  'Could not load your boutique',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  offline
                      ? 'No connection to LiveDrop. Check your internet and try again.'
                      : 'Something went wrong while loading your account. Please try again.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Try again'),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: onSignOut,
                  child: const Text('Sign out', style: TextStyle(color: AppColors.textMuted)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
