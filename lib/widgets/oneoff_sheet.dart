import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../theme/klaro.dart';

/// Bottom sheet listing this month's payments held OUT of the budget (large
/// one-offs / fees). Opened from the home "+ one-off" line. Each row can be
/// pulled back into the budget with one tap; the list updates live as it empties.
class OneOffSheet extends StatelessWidget {
  const OneOffSheet({super.key, required this.provider, required this.monthLabel});

  final ExpenseProvider provider;
  final String monthLabel;

  static Future<void> show(
    BuildContext context, {
    required ExpenseProvider provider,
    required String monthLabel,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => OneOffSheet(provider: provider, monthLabel: monthLabel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.78,
      ),
      decoration: const BoxDecoration(
        color: Klaro.overlay,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Klaro.radiusXl)),
      ),
      // Rebuilds as items are re-included so the list (and total) stay in sync.
      child: ListenableBuilder(
        listenable: provider,
        builder: (context, _) {
          final entries = provider.oneoffEntriesThisMonth;
          final total = entries.fold<double>(0, (s, e) => s + e.amount);
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                            'Not in budget · $monthLabel',
                            style: const TextStyle(
                              color: Klaro.text,
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '${entries.length} one-off payment'
                            '${entries.length == 1 ? '' : 's'} · not counted in your budget',
                            style: const TextStyle(
                                color: Klaro.textMuted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '₹${total.toStringAsFixed(0)}',
                      style: Klaro.figures(size: 22, weight: FontWeight.w600)
                          .copyWith(color: Klaro.textMuted),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: Klaro.line),
              if (entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 28, 20, 36),
                  child: Center(
                    child: Text(
                      'All payments are in your budget now.',
                      style: TextStyle(color: Klaro.textMuted, fontSize: 13),
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                    shrinkWrap: true,
                    itemCount: entries.length,
                    itemBuilder: (_, i) => _OneOffTile(
                      expense: entries[i],
                      onAddToBudget: () => provider.setInBudget(entries[i], true),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _OneOffTile extends StatelessWidget {
  const _OneOffTile({required this.expense, required this.onAddToBudget});
  final Expense expense;
  final VoidCallback onAddToBudget;

  @override
  Widget build(BuildContext context) {
    final sub =
        '${expense.category ?? 'Other'} · ${DateFormat('d MMM').format(expense.date)}';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: Klaro.textMuted.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(Klaro.radiusMd),
            ),
            child: const Icon(Icons.bookmark_remove_outlined,
                size: 18, color: Klaro.textMuted),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.merchant.isEmpty ? 'Unknown' : expense.merchant,
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
          const SizedBox(width: 8),
          Text(
            '₹${expense.amount.toStringAsFixed(0)}',
            style: Klaro.figures(size: 13.5, weight: FontWeight.w600),
          ),
          const SizedBox(width: 6),
          // Pull this payment back into the budget.
          TextButton(
            onPressed: onAddToBudget,
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 8)),
            child: const Text('Add to budget',
                style: TextStyle(color: Klaro.violetLt, fontSize: 12)),
          ),
        ],
      ),
    );
  }
}
