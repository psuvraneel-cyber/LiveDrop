import 'package:flutter/material.dart';
import 'app_colors.dart';
import 'boutique_haptics.dart';

enum ButtonVariant {
  goldGradient,
  darkCard,
  crimsonOutline,
  ghost,
}

/// Tactile Button with spring physics (scale down to 0.97 on tap down)
/// and embedded asynchronous loading indicator.
class BounceableButton extends StatefulWidget {
  final VoidCallback? onPressed;
  final Widget? child;
  final String? text;
  final IconData? icon;
  final ButtonVariant variant;
  final bool isLoading;
  final double? width;
  final double height;
  final double borderRadius;
  final EdgeInsetsGeometry padding;

  const BounceableButton({
    super.key,
    required this.onPressed,
    this.child,
    this.text,
    this.icon,
    this.variant = ButtonVariant.goldGradient,
    this.isLoading = false,
    this.width,
    this.height = 48.0,
    this.borderRadius = 12.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  @override
  State<BounceableButton> createState() => _BounceableButtonState();
}

class _BounceableButtonState extends State<BounceableButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 90),
      reverseDuration: const Duration(milliseconds: 140),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      BoutiqueHaptics.light();
      _controller.forward();
    }
  }

  void _onTapUp(TapUpDetails details) {
    if (widget.onPressed != null && !widget.isLoading) {
      _controller.reverse();
    }
  }

  void _onTapCancel() {
    if (widget.onPressed != null && !widget.isLoading) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEnabled = widget.onPressed != null && !widget.isLoading;

    BoxDecoration decoration;
    Color textColor;
    Color spinnerColor;

    switch (widget.variant) {
      case ButtonVariant.goldGradient:
        decoration = BoxDecoration(
          gradient: isEnabled ? AppColors.goldGradient : null,
          color: isEnabled ? null : AppColors.cardBorder,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          boxShadow: isEnabled
              ? [
                  BoxShadow(
                    color: AppColors.goldPrimary.withValues(alpha: 0.25),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ]
              : null,
        );
        textColor = isEnabled ? Colors.black : AppColors.textMuted;
        spinnerColor = Colors.black;
        break;

      case ButtonVariant.darkCard:
        decoration = BoxDecoration(
          color: AppColors.obsidianSurface,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(color: AppColors.cardBorder, width: 1),
        );
        textColor = AppColors.textPrimary;
        spinnerColor = AppColors.goldPrimary;
        break;

      case ButtonVariant.crimsonOutline:
        decoration = BoxDecoration(
          color: AppColors.crimsonTint,
          borderRadius: BorderRadius.circular(widget.borderRadius),
          border: Border.all(
            color: isEnabled ? AppColors.crimson : AppColors.cardBorder,
            width: 1.2,
          ),
        );
        textColor = isEnabled ? AppColors.crimson : AppColors.textMuted;
        spinnerColor = AppColors.crimson;
        break;

      case ButtonVariant.ghost:
        decoration = BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(widget.borderRadius),
        );
        textColor = AppColors.goldPrimary;
        spinnerColor = AppColors.goldPrimary;
        break;
    }

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      onTap: isEnabled ? widget.onPressed : null,
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) => Transform.scale(
          scale: _scaleAnimation.value,
          child: child,
        ),
        child: Container(
          width: widget.width,
          height: widget.height,
          padding: widget.padding,
          decoration: decoration,
          alignment: Alignment.center,
          child: widget.isLoading
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(spinnerColor),
                  ),
                )
              : widget.child ??
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (widget.icon != null) ...[
                          Icon(widget.icon, size: 18, color: textColor),
                          const SizedBox(width: 8),
                        ],
                        if (widget.text != null)
                          Text(
                            widget.text!,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.3,
                              color: textColor,
                            ),
                          ),
                      ],
                    ),
                  ),
        ),
      ),
    );
  }
}
