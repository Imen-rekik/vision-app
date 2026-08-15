import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../app/theme/app_theme.dart';
import 'orb_state.dart';

class VoiceOrb extends StatefulWidget {
  final OrbState state;
  final double size;

  const VoiceOrb({super.key, required this.state, this.size = 200.0});

  @override
  State<VoiceOrb> createState() => _VoiceOrbState();
}

class _VoiceOrbState extends State<VoiceOrb> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _rotationController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);

    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
  }

  @override
  void didUpdateWidget(VoiceOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _updateAnimations(widget.state);
    }
  }

  void _updateAnimations(OrbState state) {
    switch (state) {
      case OrbState.idle:
        _pulseController.duration = const Duration(seconds: 3);
        _pulseController.repeat(reverse: true);
        _rotationController.stop();
        break;
      case OrbState.listening:
        _pulseController.duration = const Duration(milliseconds: 600);
        _pulseController.repeat(reverse: true);
        _rotationController.stop();
        break;
      case OrbState.thinking:
        _pulseController.stop();
        _rotationController.duration = const Duration(seconds: 2);
        _rotationController.repeat();
        break;
      case OrbState.speaking:
        _pulseController.duration = const Duration(milliseconds: 900);
        _pulseController.repeat(reverse: true);
        _rotationController.stop();
        break;
      case OrbState.error:
        _pulseController.stop();
        _rotationController.stop();
        break;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _rotationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _rotationController]),
      builder: (context, child) {
        double scale = 1.0;
        Color primaryColor = AppColors.electricCyan;
        Color secondaryColor = AppColors.topLightBlue;

        if (widget.state == OrbState.listening) {
          scale = 1.0 + (_pulseController.value * 0.18);
          primaryColor = AppColors.electricCyan;
          secondaryColor = Colors.white;
        } else if (widget.state == OrbState.idle) {
          scale = 1.0 + (_pulseController.value * 0.06);
          primaryColor = AppColors.electricCyan;
          secondaryColor = AppColors.topLightBlue;
        } else if (widget.state == OrbState.thinking) {
          primaryColor = AppColors.electricCyan;
          secondaryColor = AppColors.topLightBlue;
        } else if (widget.state == OrbState.speaking) {
          scale = 1.0 + (_pulseController.value * 0.12);
          primaryColor = const Color(0xFF00FFB2); // Glowing mint-cyan
          secondaryColor = AppColors.electricCyan;
        } else if (widget.state == OrbState.error) {
          primaryColor = AppColors.errorRed;
          secondaryColor = AppColors.warningOrange;
        }

        return ExcludeSemantics(
          child: Transform.scale(
            scale: scale,
            child: SizedBox(
              width: widget.size * 1.4,
              height: widget.size * 1.4,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Outer Atmospheric Glow Ring
                  Container(
                    width: widget.size * 1.3,
                    height: widget.size * 1.3,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.35 * scale),
                          blurRadius: 40 * scale,
                          spreadRadius: 15 * scale,
                        ),
                      ],
                    ),
                  ),

                  // Rotating Celestial Arc Ring (for thinking/active state)
                  Transform.rotate(
                    angle: widget.state == OrbState.thinking
                        ? _rotationController.value * 2 * math.pi
                        : 0,
                    child: CustomPaint(
                      size: Size(widget.size * 1.15, widget.size * 1.15),
                      painter: _CelestialRingPainter(
                        color: primaryColor,
                        secondaryColor: secondaryColor,
                      ),
                    ),
                  ),

                  // Central Glowing Core Orb
                  Container(
                    width: widget.size,
                    height: widget.size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          secondaryColor.withValues(alpha: 0.95),
                          primaryColor.withValues(alpha: 0.8),
                          primaryColor.withValues(alpha: 0.25),
                          Colors.transparent,
                        ],
                        stops: const [0.2, 0.55, 0.85, 1.0],
                      ),
                      border: Border.all(
                        color: AppColors.electricCyan.withValues(alpha: 0.6),
                        width: 2.0,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: primaryColor.withValues(alpha: 0.6),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: Center(
                      child: Container(
                        padding: EdgeInsets.all(widget.size * 0.18),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: AppColors.deepMidnight.withValues(alpha: 0.35),
                        ),
                        child: Icon(
                          _getIconForState(widget.state),
                          size: widget.size * 0.32,
                          color: AppColors.crispWhite,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getIconForState(OrbState state) {
    switch (state) {
      case OrbState.idle:
        return Icons.mic_none_rounded;
      case OrbState.listening:
        return Icons.mic_rounded;
      case OrbState.thinking:
        return Icons.auto_awesome_rounded;
      case OrbState.speaking:
        return Icons.volume_up_rounded;
      case OrbState.error:
        return Icons.warning_rounded;
    }
  }
}

class _CelestialRingPainter extends CustomPainter {
  final Color color;
  final Color secondaryColor;

  _CelestialRingPainter({required this.color, required this.secondaryColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0.9),
          secondaryColor.withValues(alpha: 0.4),
          Colors.transparent,
          color.withValues(alpha: 0.9),
        ],
        stops: const [0.0, 0.4, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, paint);
  }

  @override
  bool shouldRepaint(covariant _CelestialRingPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.secondaryColor != secondaryColor;
}
