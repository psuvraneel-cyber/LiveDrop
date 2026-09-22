import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Procedural Vector Painter for the LiveDrop Luxury Coat Hanger Emblem.
/// Mathematically renders the hanger hook, neck, shoulders, and horizontal trouser bar.
class CoatHangerPainter extends CustomPainter {
  final double strokeWidth;
  final bool withGlow;
  final double animationProgress; // 0.0 to 1.0 for path drawing

  CoatHangerPainter({
    this.strokeWidth = 3.5,
    this.withGlow = true,
    this.animationProgress = 1.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final rect = Rect.fromLTWH(0, 0, w, h);
    const gradient = AppColors.goldGradient;
    final paintShader = gradient.createShader(rect);

    // Subtle glow if requested
    if (withGlow) {
      final glowPaint = Paint()
        ..shader = paintShader
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth * 2.5
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;

      _drawHangerPath(canvas, size, glowPaint);
    }

    final mainPaint = Paint()
      ..shader = paintShader
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    _drawHangerPath(canvas, size, mainPaint);
  }

  void _drawHangerPath(Canvas canvas, Size size, Paint paint) {
    final w = size.width;
    final h = size.height;

    final path = Path();

    // 1. Hook (starts from curl tip at top right, loops down into neck)
    final hookStart = Offset(w * 0.58, h * 0.16);
    path.moveTo(hookStart.dx, hookStart.dy);
    path.cubicTo(
      w * 0.58,
      h * 0.06,
      w * 0.42,
      h * 0.06,
      w * 0.42,
      h * 0.18,
    );
    path.cubicTo(
      w * 0.42,
      h * 0.28,
      w * 0.50,
      h * 0.32,
      w * 0.50,
      h * 0.38,
    );

    // 2. Neck ring / junction
    path.lineTo(w * 0.50, h * 0.44);

    // 3. Right Shoulder
    path.lineTo(w * 0.92, h * 0.76);

    // 4. Bottom Horizontal Bar
    path.lineTo(w * 0.08, h * 0.76);

    // 5. Left Shoulder
    path.lineTo(w * 0.50, h * 0.44);

    if (animationProgress >= 1.0) {
      canvas.drawPath(path, paint);
    } else {
      final metrics = path.computeMetrics();
      for (final metric in metrics) {
        final length = metric.length * animationProgress;
        final extract = metric.extractPath(0.0, length);
        canvas.drawPath(extract, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CoatHangerPainter oldDelegate) {
    return oldDelegate.animationProgress != animationProgress ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.withGlow != withGlow;
  }
}

/// Brand Emblem Widget (Coat Hanger + LiveDrop Branding)
class BrandEmblem extends StatelessWidget {
  final double size;
  final bool showText;
  final bool isAnimated;
  final String? subtitle;

  const BrandEmblem({
    super.key,
    this.size = 56.0,
    this.showText = true,
    this.isAnimated = false,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        CustomPaint(
          size: Size(size, size * 0.85),
          painter: CoatHangerPainter(
            strokeWidth: math.max(2.5, size * 0.05),
            withGlow: true,
          ),
        ),
        if (showText) ...[
          const SizedBox(height: 12),
          Text(
            'LiveDrop Seller',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size * 0.36,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle ?? 'Small Boutiques, Big Stories',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: size * 0.20,
              fontStyle: FontStyle.italic,
              color: AppColors.goldLight.withValues(alpha: 0.85),
              letterSpacing: 0.2,
            ),
          ),
        ],
      ],
    );
  }
}
