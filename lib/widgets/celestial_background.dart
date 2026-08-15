import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../app/theme/app_theme.dart';

class CelestialBackground extends StatelessWidget {
  final Widget child;

  const CelestialBackground({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.topLightBlue,
                Color(0xFF1E3547),
                AppColors.deepMidnight,
              ],
              stops: [0.0, 0.45, 1.0],
            ),
          ),
        ),

        const ExcludeSemantics(child: _TopIlluminationWash()),

        const ExcludeSemantics(child: _StarOverlay()),

        child,
      ],
    );
  }
}

class _TopIlluminationWash extends StatelessWidget {
  const _TopIlluminationWash();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: const Alignment(0.0, -1.1),
          radius: 1.2,
          colors: [
            AppColors.electricCyan.withValues(alpha: 0.35),
            AppColors.topLightBlue.withValues(alpha: 0.15),
            Colors.transparent,
          ],
          stops: const [0.0, 0.5, 1.0],
        ),
      ),
    );
  }
}

class _StarOverlay extends StatelessWidget {
  const _StarOverlay();

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _StarPainter());
  }
}

class _StarPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rng = math.Random(
      42,
    ); // Deterministic seed for stable particle locations
    final paint = Paint()..color = Colors.white;

    for (int i = 0; i < 45; i++) {
      final dx = rng.nextDouble() * size.width;
      final dy = rng.nextDouble() * size.height;
      final radius = rng.nextDouble() * 1.6 + 0.4;
      final opacity = rng.nextDouble() * 0.4 + 0.15;

      paint.color = (i % 3 == 0 ? AppColors.electricCyan : Colors.white)
          .withValues(alpha: opacity);
      canvas.drawCircle(Offset(dx, dy), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
