import 'dart:ui';
import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final VoidCallback? onTap;
  final String? semanticsLabel;
  final double borderRadius;
  final Color? borderColor;
  final Color? fillColor;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20.0),
    this.margin = EdgeInsets.zero,
    this.onTap,
    this.semanticsLabel,
    this.borderRadius = 24.0,
    this.borderColor,
    this.fillColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveBorderColor = borderColor ?? AppColors.glassBorder;
    final effectiveFillColor = fillColor ?? AppColors.glassFill;

    Widget cardContent = Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16.0, sigmaY: 16.0),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: effectiveFillColor,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(color: effectiveBorderColor, width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: AppColors.deepMidnight.withValues(alpha: 0.3),
                  blurRadius: 20,
                  spreadRadius: 2,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null || semanticsLabel != null) {
      return Semantics(
        button: onTap != null,
        label: semanticsLabel,
        excludeSemantics: semanticsLabel != null,
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(borderRadius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(borderRadius),
            focusColor: AppColors.electricCyan.withValues(alpha: 0.3),
            highlightColor: AppColors.electricCyan.withValues(alpha: 0.2),
            splashColor: AppColors.electricCyan.withValues(alpha: 0.25),
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                minWidth: 48.0,
                minHeight: 48.0,
              ),
              child: cardContent,
            ),
          ),
        ),
      );
    }

    return cardContent;
  }
}
