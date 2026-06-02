import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Renders a semi-circular visual meter indicating pitch deviation in cents
class GaugePainter extends CustomPainter {
  final double cents;
  final Color gaugeColor;

  GaugePainter({required this.cents, required this.gaugeColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height);
    final radius = size.width / 2;

    // --- RENDER GAUGE DROP SHADOW ---
    final Paint shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = 60.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 12.0);

    final Rect shadowRect = Rect.fromCircle(
      center: Offset(center.dx, center.dy + 6),
      radius: radius,
    );
    canvas.drawArc(shadowRect, pi, pi, false, shadowPaint);

    // --- RENDER ACCENTUATED COLOR GRADIENT ARC ---
    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final Paint bgArcPaint = Paint()
      ..shader = LinearGradient(
        colors: [gaugeColor, Colors.white, Colors.white, gaugeColor],
        stops: const [0.0, 0.35, 0.65, 1.0],
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = 60.0;

    canvas.drawArc(rect, pi, pi, false, bgArcPaint);

    // --- RENDER PERFECT TUNING CENTER COORD TICK ---
    final Paint centerTickPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(center.dx, center.dy - radius - 24 - 5),
      Offset(center.dx, center.dy - radius - 8 - 5),
      centerTickPaint,
    );

    // --- RENDER ROTATING DYNAMIC NEEDLE Vector ---
    final double clampedCents = cents.clamp(-50.0, 50.0);
    final double maxAngle = pi / 2.5;
    final double angle = -pi / 2 + (clampedCents / 50) * maxAngle;

    final double innerRadius = radius - 24 - 5;
    final double outerRadius = radius + 8 - 5;

    final Offset needleStart = Offset(
      center.dx + innerRadius * cos(angle),
      center.dy + innerRadius * sin(angle),
    );
    final Offset needleEnd = Offset(
      center.dx + outerRadius * cos(angle),
      center.dy + outerRadius * sin(angle),
    );

    final Paint needlePaint = Paint()
      ..color = AppColors.textDark
      ..strokeWidth = 5.0
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(needleStart, needleEnd, needlePaint);
  }

  @override
  bool shouldRepaint(covariant GaugePainter oldDelegate) {
    return oldDelegate.cents != cents || oldDelegate.gaugeColor != gaugeColor;
  }
}
