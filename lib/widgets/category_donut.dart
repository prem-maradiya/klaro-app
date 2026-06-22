import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/klaro.dart';

/// Spending-by-category breakdown drawn as a donut + legend on the home screen.
/// Bespoke [CustomPainter] (no chart dependency), fed by `categoryTotals`.
class CategoryDonutCard extends StatelessWidget {
  const CategoryDonutCard({super.key, required this.totals});

  /// Category -> spend this month (income/unlabeled already excluded upstream).
  final Map<String, double> totals;

  @override
  Widget build(BuildContext context) {
    final entries = totals.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    if (entries.isEmpty) return const SizedBox.shrink();

    final total = entries.fold<double>(0, (s, e) => s + e.value);
    final top = entries.first;
    final topPct = (top.value / total * 100).round();

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Klaro.surface,
        borderRadius: BorderRadius.circular(Klaro.radiusXl),
        border: Border.all(color: Klaro.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Spending by category',
            style: TextStyle(
              color: Klaro.text,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 116,
                height: 116,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(116, 116),
                      painter: _DonutPainter(entries: entries, total: total),
                    ),
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          top.key,
                          style: const TextStyle(
                              color: Klaro.textMuted, fontSize: 11),
                        ),
                        Text(
                          '$topPct%',
                          style:
                              Klaro.figures(size: 18, weight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in entries.take(6))
                      _LegendRow(
                        name: e.key,
                        amount: e.value,
                        pct: e.value / total * 100,
                      ),
                    if (entries.length > 6)
                      Padding(
                        padding: const EdgeInsets.only(top: 5, left: 16),
                        child: Text(
                          '+${entries.length - 6} more',
                          style: const TextStyle(
                              color: Klaro.textFaint, fontSize: 11),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.name,
    required this.amount,
    required this.pct,
  });

  final String name;
  final double amount;
  final double pct;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: Klaro.categoryColor(name),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Klaro.text, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '${pct.toStringAsFixed(0)}%',
            style: const TextStyle(color: Klaro.textFaint, fontSize: 11),
          ),
          const SizedBox(width: 8),
          Text(
            '₹${amount.toStringAsFixed(0)}',
            style: Klaro.figures(size: 12, weight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.entries, required this.total});

  final List<MapEntry<String, double>> entries;
  final double total;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 16.0;
    final rect = Offset(stroke / 2, stroke / 2) &
        Size(size.width - stroke, size.height - stroke);
    // Small gap between segments for definition (skipped when there's only one).
    final gap = entries.length > 1 ? 0.04 : 0.0;
    var start = -math.pi / 2 + gap / 2;

    for (final e in entries) {
      final sweep = (e.value / total) * (2 * math.pi) - gap;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = Klaro.categoryColor(e.key);
      canvas.drawArc(rect, start, sweep < 0 ? 0 : sweep, false, paint);
      start += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.entries != entries || old.total != total;
}
