import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/expense.dart';
import '../theme/klaro.dart';

/// Bottom sheet breaking this month's income (credits) down by source.
/// Opened from the home net-flow line. Groups deposits by merchant, newest
/// source first, with each source's running total, deposit count and dates.
class IncomeSheet extends StatelessWidget {
  const IncomeSheet({super.key, required this.entries, required this.monthLabel});

  /// This month's credit rows, newest first (from `incomeThisMonthEntries`).
  final List<Expense> entries;
  final String monthLabel;

  static Future<void> show(
    BuildContext context, {
    required List<Expense> entries,
    required String monthLabel,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => IncomeSheet(entries: entries, monthLabel: monthLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final total = entries.fold<double>(0, (s, e) => s + e.amount);
    final groups = _groupBySource(entries);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: Klaro.overlay,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Klaro.radiusXl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle.
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 14),
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Klaro.line,
                borderRadius: BorderRadius.circular(Klaro.radiusPill),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Income · $monthLabel',
                        style: const TextStyle(
                          color: Klaro.text,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${entries.length} deposit${entries.length == 1 ? '' : 's'}'
                        ' · ${groups.length} source${groups.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                            color: Klaro.textMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                Text(
                  '+₹${total.toStringAsFixed(0)}',
                  style: Klaro.figures(size: 22, weight: FontWeight.w600)
                      .copyWith(color: Klaro.positive),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Klaro.line),
          Flexible(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              shrinkWrap: true,
              itemCount: groups.length,
              itemBuilder: (_, i) => _SourceTile(group: groups[i], total: total),
            ),
          ),
        ],
      ),
    );
  }

  /// Collapse credits sharing the same merchant into one source row, ordered
  /// by total received (largest first — salary tends to dominate).
  List<_Source> _groupBySource(List<Expense> rows) {
    final map = <String, _Source>{};
    for (final e in rows) {
      final s = map.putIfAbsent(e.merchant, () => _Source(e.merchant));
      s.amount += e.amount;
      s.count++;
      if (e.date.isAfter(s.latest)) s.latest = e.date;
    }
    final list = map.values.toList()
      ..sort((a, b) => b.amount.compareTo(a.amount));
    return list;
  }
}

class _Source {
  _Source(this.merchant) : latest = DateTime.fromMillisecondsSinceEpoch(0);
  final String merchant;
  double amount = 0;
  int count = 0;
  DateTime latest;
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.group, required this.total});
  final _Source group;
  final double total;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? group.amount / total * 100 : 0.0;
    final sub = group.count == 1
        ? DateFormat('d MMM').format(group.latest)
        : '${group.count} deposits · latest ${DateFormat('d MMM').format(group.latest)}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Klaro.positive.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(Klaro.radiusMd),
            ),
            child: const Icon(Icons.south_west, size: 18, color: Klaro.positive),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  group.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Klaro.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 2),
                Text(
                  sub,
                  style: const TextStyle(color: Klaro.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${group.amount.toStringAsFixed(0)}',
                style: Klaro.figures(size: 13.5, weight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                '${pct.toStringAsFixed(0)}%',
                style: const TextStyle(color: Klaro.textFaint, fontSize: 10.5),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
