import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/services/supabase_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/brand_emblem.dart';

/// Hardware-accelerated Animated Splash Screen.
/// Performs parallel Supabase session validation while executing a 1.5s orchestrated
/// vector brand mark reveal, followed by a fluid cross-fade into Home or Login.
class AnimatedSplashScreen extends StatefulWidget {
  final Duration minDuration;
  final Widget Function(bool isAuthenticated) onNavigationTarget;

  const AnimatedSplashScreen({
    super.key,
    this.minDuration = const Duration(milliseconds: 1600),
    required this.onNavigationTarget,
  });

  @override
  State<AnimatedSplashScreen> createState() => _AnimatedSplashScreenState();
}

class _AnimatedSplashScreenState extends State<AnimatedSplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _drawController;
  bool _authResolved = false;
  bool _isAuthenticated = false;
  bool _minDurationElapsed = false;

  @override
  void initState() {
    super.initState();
    _drawController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();

    _runParallelStartup();
  }

  @override
  void dispose() {
    _drawController.dispose();
    super.dispose();
  }

  Future<void> _runParallelStartup() async {
    // 1. Minimum duration timer to ensure elegant brand presence
    final timerFuture = Future.delayed(widget.minDuration, () {
      _minDurationElapsed = true;
    });

    // 2. Parallel Supabase Auth check
    try {
      if (SupabaseService.instance.isInitialized) {
        _isAuthenticated = SupabaseService.instance.isAuthenticated;
      } else {
        _isAuthenticated = false;
      }
    } catch (_) {
      _isAuthenticated = false;
    }
    _authResolved = true;

    await timerFuture;

    if (!mounted) return;

    if (_authResolved && _minDurationElapsed) {
      _navigateToDestination();
    }
  }

  void _navigateToDestination() {
    final nextScreen = widget.onNavigationTarget(_isAuthenticated);
    Navigator.of(context).pushReplacement(
      PageRouteBuilder<void>(
        transitionDuration: const Duration(milliseconds: 600),
        pageBuilder: (context, animation, secondaryAnimation) => nextScreen,
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(
              parent: animation,
              curve: Curves.easeInOutCubic,
            ),
            child: child,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.obsidian,
      body: Stack(
        children: [
          // Background ambient radial gradient
          Center(
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    AppColors.goldPrimary.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                  radius: 0.7,
                ),
              ),
            )
                .animate(onPlay: (controller) => controller.repeat(reverse: true))
                .scale(
                  begin: const Offset(0.9, 0.9),
                  end: const Offset(1.15, 1.15),
                  duration: 1500.ms,
                  curve: Curves.easeInOut,
                ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Animated Vector Coat Hanger Emblem
                AnimatedBuilder(
                  animation: _drawController,
                  builder: (context, child) {
                    return CustomPaint(
                      size: const Size(100, 85),
                      painter: CoatHangerPainter(
                        strokeWidth: 4.0,
                        withGlow: true,
                        animationProgress: _drawController.value,
                      ),
                    );
                  },
                )
                    .animate()
                    .scale(
                      begin: const Offset(0.85, 0.85),
                      end: const Offset(1.0, 1.0),
                      duration: 900.ms,
                      curve: Curves.easeOutCubic,
                    ),
                const SizedBox(height: 24),
                // Brand Name
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'LiveDrop',
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.0,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.goldMuted,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.goldPrimary, width: 1.0),
                      ),
                      child: const Text(
                        'SELLER',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.5,
                          color: AppColors.goldPrimary,
                        ),
                      ),
                    ),
                  ],
                )
                    .animate()
                    .fadeIn(delay: 350.ms, duration: 600.ms)
                    .slideY(begin: 0.2, end: 0.0, curve: Curves.easeOutCubic),
                const SizedBox(height: 8),
                // Brand Tagline
                Text(
                  'Small Boutiques, Big Stories',
                  style: TextStyle(
                    fontSize: 16,
                    fontStyle: FontStyle.italic,
                    color: AppColors.goldLight.withValues(alpha: 0.85),
                    letterSpacing: 0.4,
                  ),
                )
                    .animate()
                    .fadeIn(delay: 550.ms, duration: 600.ms)
                    .slideY(begin: 0.2, end: 0.0, curve: Curves.easeOutCubic),
              ],
            ),
          ),
          // Subtle footer credit
          const Positioned(
            bottom: 32,
            left: 0,
            right: 0,
            child: Center(
              child: Text(
                'Live-Stream Commerce for Indian Boutiques',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textMuted,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          )
              .animate()
              .fadeIn(delay: 800.ms, duration: 500.ms),
        ],
      ),
    );
  }
}
