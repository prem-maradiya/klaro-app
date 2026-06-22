import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../theme/klaro.dart';

/// "Spending trends" — total spend per month across the last 6 months, so the
/// user can see whether they're trending up or down beyond the current month.
/// Fed by `ExpenseProvider.monthlySpend` (all local data, fully offline).
class TrendsScreen extends StatelessWidget {
  const TrendsScreen({super.key});

  static final _inr = NumberFormat.decimalPattern('en_IN');

  static String _money(double v) => '₹${_inr.format(v.round())}';

  /// Compact form for bar labels: ₹12.3k above a thousand, else the round value.
  static String _compact(double v) =>
      v >= 1000 ? '₹${(v / 1000).toStringAsFixed(v >= 10000 ? 0 : 1)}k' : '₹${v.round()}';

  @override
  Widget build(BuildContext context) {
    final data = context.watch<ExpenseProvider>().monthlySpend(count: 6);
    final totals = [for (final m in data) m.total];
    final maxV = totals.fold<double>(0, (a, b) => a > b ? a : b);
    final current = data.isEmpty ? 0.0 : data.last.total;
    final prev = data.length >= 2 ? data[data.length - 2].total : 0.0;
    final avg = totals.isEmpty ? 0.0 : totals.reduce((a, b) => a + b) / totals.length;
    final hasAny = maxV > 0;

    // For spending, a rise is "bad" (alert) and a drop is "good" (positive).
    double? momPct = prev > 0 ? (current - prev) / prev * 100 : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Spending trends')),
      body: !hasAny
          ? const _EmptyTrends()
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _SummaryCard(
                  current: current,
                  momPct: momPct,
                  avg: avg,
                  months: data.length,
                ),
                const SizedBox(height: 16),
                _ChartCard(data: data, maxV: maxV),
                const SizedBox(height: 16),
                _MonthList(data: data, maxV: maxV),
                const SizedBox(height: 12),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    'Spend only (income excluded). The current month is still in '
                    'progress, so its bar will keep growing.',
                    style: TextStyle(
                        color: Klaro.textFaint, fontSize: 11.5, height: 1.4),
                  ),
                ),
              ],
            ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.current,
    required this.momPct,
    required this.avg,
    required this.months,
  });

  final double current;
  final double? momPct;
  final double avg;
  final int months;

  @override
  Widget build(BuildContext context) {
    final pct = momPct;
    final up = (pct ?? 0) >= 0;
    final deltaColor = up ? Klaro.alert : Klaro.positive;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: Klaro.gradient,
        borderRadius: BorderRadius.circular(Klaro.radiusLg),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'This month so far',
            style: TextStyle(color: Colors.white70, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Text(
            TrendsScreen._money(current),
            style: Klaro.figures(size: 30, weight: FontWeight.w600, color: Colors.white),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              if (pct != null) ...[
                Icon(up ? Icons.trending_up : Icons.trending_down,
                    size: 16, color: deltaColor),
                const SizedBox(width: 4),
                Text(
                  '${up ? '+' : '−'}${pct.abs().toStringAsFixed(0)}% vs last month',
                  style: TextStyle(
                      color: deltaColor, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ] else
                const Text(
                  'No prior month to compare',
                  style: TextStyle(color: Colors.white60, fontSize: 12.5),
                ),
              const Spacer(),
              Text(
                'Avg ${TrendsScreen._money(avg)}/mo',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({required this.data, required this.maxV});

  final List<MonthSpend> data;
  final double maxV;

  @override
  Widget build(BuildContext context) {
    const chartH = 150.0;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: Klaro.surface,
        borderRadius: BorderRadius.circular(Klaro.radiusXl),
        border: Border.all(color: Klaro.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Last 6 months',
              style: TextStyle(
                  color: Klaro.text, fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
          SizedBox(
            height: chartH,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (var i = 0; i < data.length; i++)
                  Expanded(
                    child: _Bar(
                      spend: data[i],
                      maxV: maxV,
                      maxBarH: chartH - 38, // headroom for the value label
                      isCurrent: i == data.length - 1,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({
    required this.spend,
    required this.maxV,
    required this.maxBarH,
    required this.isCurrent,
  });

  final MonthSpend spend;
  final double maxV;
  final double maxBarH;
  final bool isCurrent;

  @override
  Widget build(BuildContext context) {
    final h = maxV > 0 ? (spend.total / maxV) * maxBarH : 0.0;
    final label = DateFormat('MMM').format(spend.month);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Text(
          spend.total > 0 ? TrendsScreen._compact(spend.total) : '',
          style: TextStyle(
            color: isCurrent ? Klaro.violetLt : Klaro.textMuted,
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 26,
          height: spend.total > 0 ? (h < 3 ? 3 : h) : 0,
          decoration: BoxDecoration(
            gradient: isCurrent ? Klaro.gradient : null,
            color: isCurrent ? null : Klaro.violet.withValues(alpha: 0.34),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(5)),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: TextStyle(
            color: isCurrent ? Klaro.text : Klaro.textFaint,
            fontSize: 11,
            fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ],
    );
  }
}

class _MonthList extends StatelessWidget {
  const _MonthList({required this.data, required this.maxV});

  final List<MonthSpend> data;
  final double maxV;

  @override
  Widget build(BuildContext context) {
    // Newest first in the list.
    final rows = data.reversed.toList();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      decoration: BoxDecoration(
        color: Klaro.surface,
        borderRadius: BorderRadius.circular(Klaro.radiusXl),
        border: Border.all(color: Klaro.line),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            _MonthRow(
              spend: rows[i],
              // Previous calendar month is the next item in this reversed list.
              prev: i + 1 < rows.length ? rows[i + 1].total : null,
              maxV: maxV,
              isCurrent: i == 0,
              showDivider: i < rows.length - 1,
            ),
        ],
      ),
    );
  }
}

class _MonthRow extends StatelessWidget {
  const _MonthRow({
    required this.spend,
    required this.prev,
    required this.maxV,
    required this.isCurrent,
    required this.showDivider,
  });

  final MonthSpend spend;
  final double? prev;
  final double maxV;
  final bool isCurrent;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final p = prev;
    double? pct = (p != null && p > 0) ? (spend.total - p) / p * 100 : null;
    final up = (pct ?? 0) >= 0;
    final frac = maxV > 0 ? (spend.total / maxV).clamp(0.0, 1.0) : 0.0;

    return Container(
      decoration: BoxDecoration(
        border: showDivider
            ? const Border(bottom: BorderSide(color: Klaro.line))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              DateFormat('MMM yyyy').format(spend.month),
              style: TextStyle(
                color: isCurrent ? Klaro.text : Klaro.textMuted,
                fontSize: 12.5,
                fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Mini share bar.
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Klaro.radiusPill),
              child: LinearProgressIndicator(
                value: frac.toDouble(),
                minHeight: 6,
                backgroundColor: Klaro.raised,
                valueColor: AlwaysStoppedAnimation(
                  isCurrent ? Klaro.violetLt : Klaro.violet.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            TrendsScreen._money(spend.total),
            style: Klaro.figures(size: 12.5, weight: FontWeight.w600),
          ),
          SizedBox(
            width: 52,
            child: pct == null
                ? const SizedBox.shrink()
                : Text(
                    '${up ? '+' : '−'}${pct.abs().toStringAsFixed(0)}%',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: up ? Klaro.alert : Klaro.positive,
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTrends extends StatelessWidget {
  const _EmptyTrends();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 96, 28, 28),
      children: const [
        Icon(Icons.bar_chart_rounded, size: 44, color: Klaro.textFaint),
        SizedBox(height: 16),
        Text(
          'No spending yet',
          textAlign: TextAlign.center,
          style: TextStyle(
              fontFamily: Klaro.display, fontSize: 17, color: Klaro.text),
        ),
        SizedBox(height: 8),
        Text(
          'Your month-by-month spending trend appears here once Klaro has '
          'captured a few transactions.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, height: 1.5, color: Klaro.textMuted),
        ),
      ],
    );
  }
}
