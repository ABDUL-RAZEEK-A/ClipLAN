import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Animated radar / sonar pulse effect with warm brown/peach tones
/// and floating glow particles.
class RadarAnimation extends StatefulWidget {
  const RadarAnimation({super.key});

  @override
  State<RadarAnimation> createState() => _RadarAnimationState();
}

class _RadarAnimationState extends State<RadarAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _pulse;
  late final AnimationController _rotate;
  late final AnimationController _particles;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();
    _rotate = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _particles = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
  }

  @override
  void dispose() {
    _pulse.dispose();
    _rotate.dispose();
    _particles.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_pulse, _rotate, _particles]),
      builder: (context, _) {
        return CustomPaint(
          painter: _RadarPainter(
            pulseProgress: _pulse.value,
            rotation: _rotate.value * 2 * pi,
            particlePhase: _particles.value,
          ),
          size: const Size(200, 200),
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  final double pulseProgress;
  final double rotation;
  final double particlePhase;

  _RadarPainter({
    required this.pulseProgress,
    required this.rotation,
    required this.particlePhase,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxR = size.width / 2;

    // Outer warm glow
    canvas.drawCircle(
      center,
      maxR * 1.05,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.primaryLight.withValues(alpha: 0.05),
            AppColors.primaryLight.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: maxR * 1.05)),
    );

    // Concentric grid circles in warm brown
    for (var i = 1; i <= 3; i++) {
      canvas.drawCircle(
        center,
        maxR * (i / 3),
        Paint()
          ..color = AppColors.primaryLight.withValues(alpha: 0.08)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    // Cross lines
    final linePaint = Paint()
      ..color = AppColors.primaryLight.withValues(alpha: 0.04)
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, center.dy),
      Offset(size.width, center.dy),
      linePaint,
    );
    canvas.drawLine(
      Offset(center.dx, 0),
      Offset(center.dx, size.height),
      linePaint,
    );

    // Sweep gradient (radar arm) — warm peach tones
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: rotation,
        endAngle: rotation + pi / 2,
        colors: [
          AppColors.primaryLight.withValues(alpha: 0.35),
          AppColors.primaryLight.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxR));
    canvas.drawCircle(center, maxR, sweepPaint);

    // Expanding pulse rings in warm tones
    for (var i = 0; i < 3; i++) {
      final p = (pulseProgress + i * 0.33) % 1.0;
      canvas.drawCircle(
        center,
        maxR * p,
        Paint()
          ..color = AppColors.primaryLight.withValues(alpha: (1.0 - p) * 0.35)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // Floating glow particles
    final rng = Random(42);
    for (var i = 0; i < 8; i++) {
      final angle = rng.nextDouble() * 2 * pi + particlePhase * 2 * pi;
      final dist = maxR * (0.3 + rng.nextDouble() * 0.55);
      final px = center.dx + cos(angle) * dist;
      final py = center.dy + sin(angle) * dist;
      final opacity = (0.2 + 0.4 * sin(particlePhase * 2 * pi + i * 0.8).abs());
      final radius = 1.5 + rng.nextDouble() * 2.0;

      canvas.drawCircle(
        Offset(px, py),
        radius,
        Paint()..color = AppColors.primaryLight.withValues(alpha: opacity),
      );

      // Particle glow
      canvas.drawCircle(
        Offset(px, py),
        radius * 3,
        Paint()
          ..shader =
              RadialGradient(
                colors: [
                  AppColors.primaryLight.withValues(alpha: opacity * 0.3),
                  AppColors.primaryLight.withValues(alpha: 0.0),
                ],
              ).createShader(
                Rect.fromCircle(center: Offset(px, py), radius: radius * 3),
              ),
      );
    }

    // Center dot — warm gradient
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..shader = const RadialGradient(
          colors: [AppColors.primaryLight, AppColors.primary],
        ).createShader(Rect.fromCircle(center: center, radius: 6)),
    );

    // Center glow
    canvas.drawCircle(
      center,
      22,
      Paint()
        ..shader = RadialGradient(
          colors: [
            AppColors.primaryLight.withValues(alpha: 0.35),
            AppColors.primaryLight.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 22)),
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => true;
}
