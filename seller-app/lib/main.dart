import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/env_config.dart';
import 'core/services/supabase_service.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'data/repositories/seller_repository.dart';
import 'domain/models/models.dart';
import 'presentation/analytics/seller_analytics_screen.dart';
import 'presentation/auth/seller_login_screen.dart';
import 'presentation/configuration_error_screen.dart';
import 'presentation/dashboard/seller_dashboard_screen.dart';
import 'presentation/drops/create_drop_screen.dart';
import 'presentation/drops/drops_list_screen.dart';
import 'presentation/intake/camera_intake_screen.dart';
import 'presentation/orders/kanban_board_screen.dart';
import 'presentation/orders/shipping_label_screen.dart';
import 'presentation/pending_verifications_screen.dart';
import 'presentation/products/products_inventory_screen.dart';
import 'presentation/settings/seller_settings_screen.dart';
import 'presentation/splash/animated_splash_screen.dart';

export 'presentation/auth/seller_login_screen.dart' show SellerLoginScreen;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
class SellerHomeScreen extends StatefulWidget {
  final SellerRepository repository;

  const SellerHomeScreen({super.key, required this.repository});

  @override
  State<SellerHomeScreen> createState() => _SellerHomeScreenState();
}

class _SellerHomeScreenState extends State<SellerHomeScreen> {
  int _currentIndex = 0;

  void _navigateToTab(int index) {
    setState(() => _currentIndex = index);
  }

  void _openAddProduct() async {
    try {
      final drops = await widget.repository.getDrops();
      final active = drops.where((d) => d.status == DropStatus.live).firstOrNull ??
          drops.where((d) => d.status == DropStatus.draft).firstOrNull ??
          drops.firstOrNull;

      if (!mounted) return;

      if (active != null) {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => CameraIntakeScreen(
              drop: active,
              repository: widget.repository,
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
        builder: (_) => DropsListScreen(repository: widget.repository),
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

  void _openShipping() async {
    try {
      final orders = await widget.repository.getAllOrders();
      final profile = await widget.repository.getProfile();
      final paidOrShipped = orders.firstOrNull;

      if (!mounted) return;

      if (paidOrShipped != null) {
        Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ShippingLabelScreen(
              order: paidOrShipped,
              profile: profile,
              repository: widget.repository,
            ),
          ),
        );
      } else {
        _navigateToTab(2); // Orders tab
      }
    } catch (_) {
      _navigateToTab(2);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: IndexedStack(
        index: _currentIndex,
        children: [
          // Tab 0: Home / Live Dashboard (Screen 2)
          SellerDashboardScreen(
            repository: widget.repository,
            onNavigateToAddProduct: _openAddProduct,
            onNavigateToOrders: () => _navigateToTab(2),
            onNavigateToPayments: () => _navigateToTab(3),
            onNavigateToAnalytics: _openAnalytics,
            onNavigateToShipping: _openShipping,
            onManageDrop: _openManageDrops,
          ),
          // Tab 1: Products & Inventory (Screen 3)
          ProductsInventoryScreen(repository: widget.repository),
          // Tab 2: Orders Kanban (Screen 6)
          KanbanBoardScreen(repository: widget.repository),
          // Tab 3: Payment Verifications (Screen 7)
          Scaffold(
            backgroundColor: AppColors.obsidian,
            appBar: AppBar(
              title: const Text('Verify Payments', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            body: PendingVerificationsScreen(repository: widget.repository),
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
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.home_outlined, Icons.home_rounded, 'Home'),
                _buildNavItem(1, Icons.inventory_2_outlined, Icons.inventory_2_rounded, 'Products'),
                _buildNavItem(2, Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Orders'),
                _buildNavItem(3, Icons.verified_outlined, Icons.verified_rounded, 'Payments'),
                _buildNavItem(4, Icons.more_horiz_rounded, Icons.more_horiz_rounded, 'More'),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData unselectedIcon, IconData selectedIcon, String label) {
    final isSelected = _currentIndex == index;

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
            Icon(
              isSelected ? selectedIcon : unselectedIcon,
              color: isSelected ? AppColors.goldPrimary : AppColors.textMuted,
              size: 22,
            ),
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
