import 'package:flutter/material.dart';
import '../theme/klaro.dart';

/// Daily spending for the current month, drawn as a compact bar chart on the
/// home screen. Bespoke [CustomPainter] (no chart dependency) to match Klaro's
/// hand-built visual language. The bars' sum equals the headline month total;
/// the highest-spend day is highlighted with the brand gradient.
class SpendingChartCard extends StatelessWidget {
  const SpendingChartCard({
    super.key,
    required this.daily,
    required this.monthLabel,
  });

  /// Spend per day, index 0 = the 1st. Length = days elapsed this month.
  final List<double> daily;

  /// Full month name, e.g. "June".
  final String monthLabel;

  @override
  Widget build(BuildContext context) {
    final total = daily.fold<double>(0, (s, v) => s + v);
    final avg = daily.isEmpty ? 0.0 : total / daily.length;

    var peakIdx = 0;
    for (var i = 1; i < daily.length; i++) {
      if (daily[i] > daily[peakIdx]) peakIdx = i;
    }
    final peak = daily.isEmpty ? 0.0 : daily[peakIdx];
    final mon = monthLabel.length >= 3 ? monthLabel.substring(0, 3) : monthLabel;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        color: Klaro.surface,
        borderRadius: BorderRadius.circular(Klaro.radiusXl),
        border: Border.all(color: Klaro.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Daily spending · $monthLabel',
                    style: const TextStyle(
                      color: Klaro.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Avg ₹${avg.toStringAsFixed(0)}/day',
                    style: const TextStyle(color: Klaro.textMuted, fontSize: 12),
                  ),
                ],
              ),
              if (peak > 0)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text(
                      'Top day',
                      style: TextStyle(color: Klaro.textFaint, fontSize: 11),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '₹${peak.toStringAsFixed(0)} · $mon ${peakIdx + 1}',
                      style: Klaro.figures(
                        size: 12.5,
                        weight: FontWeight.w500,
                        color: Klaro.violetLt,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 96,
            width: double.infinity,
            child: CustomPaint(
              painter: _DailyBarsPainter(daily: daily, peakIdx: peakIdx),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$mon 1',
                style: const TextStyle(color: Klaro.textFaint, fontSize: 10.5),
              ),
              const Text(
                'Today',
                style: TextStyle(color: Klaro.textFaint, fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DailyBarsPainter extends CustomPainter {
  _DailyBarsPainter({required this.daily, required this.peakIdx});

  final List<double> daily;
  final int peakIdx;

  @override
  void paint(Canvas canvas, Size size) {
    if (daily.isEmpty) return;
    final baseY = size.height;

    // Baseline hairline.
    canvas.drawLine(
      Offset(0, baseY - 0.5),
      Offset(size.width, baseY - 0.5),
      Paint()
        ..color = Klaro.line
        ..strokeWidth = 1,
    );

    final maxV = daily.reduce((a, b) => a > b ? a : b);
    if (maxV <= 0) return;

    final n = daily.length;
    const gap = 3.0;
    final barW = ((size.width - gap * (n - 1)) / n).clamp(1.5, 28.0);
    final radius = (barW / 2).clamp(0.0, 3.5);

    for (var i = 0; i < n; i++) {
      final v = daily[i];
      if (v <= 0) continue;
      final h = (v / maxV) * (size.height - 6); // headroom so the peak isn't clipped
      final x = i * (barW + gap);
      final top = baseY - (h < 2 ? 2 : h); // min visible nub for tiny days
      final rect = RRect.fromRectAndCorners(
        Rect.fromLTRB(x, top, x + barW, baseY),
        topLeft: Radius.circular(radius),
        topRight: Radius.circular(radius),
      );

      final paint = Paint();
      if (i == peakIdx) {
        paint.shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Klaro.violet, Klaro.blue],
        ).createShader(Rect.fromLTRB(x, top, x + barW, baseY));
      } else {
        paint.color = Klaro.violet.withValues(alpha: 0.32);
      }
      canvas.drawRRect(rect, paint);
    }
  }

  @override
  bool shouldRepaint(_DailyBarsPainter old) =>
      old.daily != daily || old.peakIdx != peakIdx;
}
