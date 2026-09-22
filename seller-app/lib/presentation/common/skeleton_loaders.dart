import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';

/// Luxury Shimmer Skeleton Block
class ShimmerBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const ShimmerBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppColors.obsidianElevated,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    )
        .animate(onPlay: (controller) => controller.repeat())
        .shimmer(
          duration: 1200.ms,
          color: AppColors.goldPrimary.withValues(alpha: 0.12),
        );
  }
}

/// Shimmer Skeleton for Active Drop & Drops List
class DropsListSkeleton extends StatelessWidget {
  const DropsListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        // Hero Active Drop Skeleton
        Container(
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ShimmerBox(width: 72, height: 72, borderRadius: 12),
                  SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ShimmerBox(width: 160, height: 18),
                        SizedBox(height: 8),
                        ShimmerBox(width: 100, height: 14),
                      ],
                    ),
                  ),
                  ShimmerBox(width: 64, height: 26, borderRadius: 16),
                ],
              ),
              SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ShimmerBox(width: 70, height: 44, borderRadius: 8),
                  ShimmerBox(width: 70, height: 44, borderRadius: 8),
                  ShimmerBox(width: 70, height: 44, borderRadius: 8),
                  ShimmerBox(width: 80, height: 44, borderRadius: 8),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // Secondary items
        ...List.generate(
          3,
          (index) => Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: AppTheme.cardDecoration(),
            child: const Row(
              children: [
                ShimmerBox(width: 56, height: 56, borderRadius: 10),
                SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ShimmerBox(width: 140, height: 16),
                      SizedBox(height: 6),
                      ShimmerBox(width: 80, height: 12),
                    ],
                  ),
                ),
                ShimmerBox(width: 60, height: 28, borderRadius: 14),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shimmer Skeleton for Kanban Orders Board
class KanbanSkeleton extends StatelessWidget {
  const KanbanSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 4,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(16),
          decoration: AppTheme.cardDecoration(),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ShimmerBox(width: 90, height: 18),
                  ShimmerBox(width: 70, height: 18),
                ],
              ),
              SizedBox(height: 10),
              ShimmerBox(width: 140, height: 14),
              SizedBox(height: 12),
              Row(
                children: [
                  ShimmerBox(width: 48, height: 48, borderRadius: 8),
                  SizedBox(width: 8),
                  ShimmerBox(width: 48, height: 48, borderRadius: 8),
                  Spacer(),
                  ShimmerBox(width: 90, height: 36, borderRadius: 10),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Shimmer Skeleton for Pending Payment Verifications Queue
class VerificationsSkeleton extends StatelessWidget {
  const VerificationsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(18),
          decoration: AppTheme.cardDecoration(),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  ShimmerBox(width: 100, height: 18),
                  ShimmerBox(width: 70, height: 24, borderRadius: 12),
                ],
              ),
              SizedBox(height: 14),
              ShimmerBox(width: double.infinity, height: 50, borderRadius: 10),
              SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: ShimmerBox(width: double.infinity, height: 44, borderRadius: 10)),
                  SizedBox(width: 12),
                  Expanded(child: ShimmerBox(width: double.infinity, height: 44, borderRadius: 10)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
