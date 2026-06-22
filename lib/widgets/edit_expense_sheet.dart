import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/sms_service.dart';
import '../theme/klaro.dart';
import 'klaro_button.dart';

/// A bottom sheet for editing ANY expense's merchant + category — works for
/// both unlabeled items and already auto-categorized ones (so the user can
/// always correct the engine). Saving also trains the backend learning system.
class EditExpenseSheet extends StatefulWidget {
  const EditExpenseSheet({super.key, required this.expense});
  final Expense expense;

  static Future<void> show(BuildContext context, Expense expense) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => EditExpenseSheet(expense: expense),
    );
  }

  @override
  State<EditExpenseSheet> createState() => _EditExpenseSheetState();
}

class _EditExpenseSheetState extends State<EditExpenseSheet> {
  late final TextEditingController _merchantCtrl;
  late String _category;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _merchantCtrl = TextEditingController(text: widget.expense.merchant);
    final cat = widget.expense.category;
    _category = (cat != null && SmsService.allCategories.contains(cat))
        ? cat
        : 'Other';
  }

  @override
  void dispose() {
    _merchantCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final merchant = _merchantCtrl.text.trim();
    if (merchant.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a merchant name')),
      );
      return;
    }
    setState(() => _saving = true);
    await context.read<ExpenseProvider>().labelExpense(
          expense: widget.expense,
          merchant: merchant,
          category: _category,
        );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    await context.read<ExpenseProvider>().deleteExpense(widget.expense);
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Klaro.overlay,
          borderRadius: BorderRadius.vertical(top: Radius.circular(Klaro.radiusXl)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Klaro.textFaint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                const Text(
                  'Edit expense',
                  style: TextStyle(
                    fontFamily: Klaro.display,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Klaro.text,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: Klaro.raised,
                    borderRadius: BorderRadius.circular(Klaro.radiusSm),
                    border: Border.all(color: Klaro.line),
                  ),
                  child: Text(
                    '₹${e.amount.toStringAsFixed(2)}',
                    style: Klaro.figures(size: 14, weight: FontWeight.w600),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              e.rawSms,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Klaro.textFaint),
            ),
            const Divider(height: 24),
            TextField(
              controller: _merchantCtrl,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Merchant / name',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _category,
              decoration: const InputDecoration(
                labelText: 'Category',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              items: SmsService.allCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) => setState(() => _category = v ?? 'Other'),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                TextButton.icon(
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline,
                      color: Klaro.danger, size: 20),
                  label: const Text('Delete',
                      style: TextStyle(color: Klaro.danger)),
                ),
                const Spacer(),
                KlaroButton(
                  onPressed: _saving ? null : _save,
                  label: 'Save',
                  loading: _saving,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
