import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../services/budget_service.dart';
import '../services/sms_service.dart';
import '../theme/klaro.dart';
import '../widgets/klaro_button.dart';

/// Set / edit monthly spending limits — one overall cap plus optional
/// per-category limits, each with this month's progress.
class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      body: ListenableBuilder(
        listenable: BudgetService.instance,
        builder: (context, _) {
          final provider = context.watch<ExpenseProvider>();
          final budgets = BudgetService.instance;
          final totals = provider.categoryTotals;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _BudgetTile(
                name: 'Monthly budget',
                categoryKey: BudgetService.overallKey,
                spent: provider.totalThisMonth,
                limit: budgets.overall,
                emphasized: true,
              ),
              const SizedBox(height: 20),
              const Padding(
                padding: EdgeInsets.only(left: 4, bottom: 8),
                child: Text('Per category',
                    style: TextStyle(color: Klaro.textFaint, fontSize: 12)),
              ),
              ...SmsService.allCategories.map(
                (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _BudgetTile(
                    name: c,
                    categoryKey: c,
                    spent: totals[c] ?? 0,
                    limit: budgets.limitFor(c),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'You\'ll get a notification when a budget passes 80% and again '
                'when it\'s exceeded.',
                style: TextStyle(color: Klaro.textFaint, fontSize: 12),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BudgetTile extends StatelessWidget {
  const _BudgetTile({
    required this.name,
    required this.categoryKey,
    required this.spent,
    required this.limit,
    this.emphasized = false,
  });

  final String name;
  final String categoryKey;
  final double spent;
  final double? limit;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final hasLimit = limit != null && limit! > 0;
    final pct = hasLimit ? (spent / limit!).clamp(0.0, 1.0) : 0.0;
    final over = hasLimit && spent >= limit!;
    final near = hasLimit && !over && spent >= limit! * 0.8;
    final barColor =
        over ? Klaro.danger : (near ? Klaro.alert : Klaro.violet);
    final dotColor = categoryKey == BudgetService.overallKey
        ? Klaro.violet
        : Klaro.categoryColor(name);

    return InkWell(
      onTap: () => _BudgetEditDialog.show(context, name, categoryKey, limit),
      borderRadius: BorderRadius.circular(Klaro.radiusLg),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: emphasized ? Klaro.raised : Klaro.surface,
          borderRadius: BorderRadius.circular(Klaro.radiusLg),
          border: Border.all(color: Klaro.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: dotColor, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: TextStyle(
                      color: Klaro.text,
                      fontWeight:
                          emphasized ? FontWeight.w600 : FontWeight.w500,
                      fontSize: emphasized ? 15 : 14,
                    ),
                  ),
                ),
                if (hasLimit)
                  Text(
                    '₹${spent.toStringAsFixed(0)} / ₹${limit!.toStringAsFixed(0)}',
                    style: Klaro.figures(size: 13, weight: FontWeight.w500),
                  )
                else
                  const Text('Set limit',
                      style:
                          TextStyle(color: Klaro.textFaint, fontSize: 12.5)),
              ],
            ),
            if (hasLimit) ...[
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: pct,
                  minHeight: 6,
                  backgroundColor: Klaro.line,
                  valueColor: AlwaysStoppedAnimation(barColor),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                over
                    ? 'Over by ₹${(spent - limit!).toStringAsFixed(0)}'
                    : '${(pct * 100).round()}% used · ₹${(limit! - spent).toStringAsFixed(0)} left',
                style: TextStyle(
                  fontSize: 11.5,
                  color: over ? Klaro.danger : Klaro.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _BudgetEditDialog extends StatefulWidget {
  const _BudgetEditDialog(
      {required this.name, required this.categoryKey, required this.current});

  final String name;
  final String categoryKey;
  final double? current;

  static Future<void> show(
      BuildContext context, String name, String categoryKey, double? current) {
    return showDialog(
      context: context,
      builder: (_) => _BudgetEditDialog(
          name: name, categoryKey: categoryKey, current: current),
    );
  }

  @override
  State<_BudgetEditDialog> createState() => _BudgetEditDialogState();
}

class _BudgetEditDialogState extends State<_BudgetEditDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
      text: widget.current != null && widget.current! > 0
          ? widget.current!.toStringAsFixed(0)
          : '',
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_ctrl.text.trim());
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount above zero')),
      );
      return;
    }
    await BudgetService.instance.setBudget(widget.categoryKey, amount);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _remove() async {
    await BudgetService.instance.removeBudget(widget.categoryKey);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Klaro.overlay,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Klaro.radiusLg)),
      title: Text(
        widget.categoryKey == BudgetService.overallKey
            ? 'Monthly budget'
            : '${widget.name} budget',
        style: const TextStyle(
            fontFamily: Klaro.display, fontSize: 17, color: Klaro.text),
      ),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
        ],
        decoration: const InputDecoration(
          labelText: 'Limit per month',
          prefixText: '₹ ',
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        if (widget.current != null)
          TextButton(
            onPressed: _remove,
            child:
                const Text('Remove', style: TextStyle(color: Klaro.danger)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        KlaroButton(onPressed: _save, label: 'Save'),
      ],
    );
  }
}
