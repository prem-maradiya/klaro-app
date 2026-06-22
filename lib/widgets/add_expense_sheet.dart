import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/sms_service.dart';
import '../theme/klaro.dart';
import 'klaro_button.dart';

/// Manual entry for payments that produce no bank SMS (UPI Lite, wallet
/// balances, cash) — the one case automatic capture can't cover.
class AddExpenseSheet extends StatefulWidget {
  const AddExpenseSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddExpenseSheet(),
    );
  }

  @override
  State<AddExpenseSheet> createState() => _AddExpenseSheetState();
}

class _AddExpenseSheetState extends State<AddExpenseSheet> {
  final _amountCtrl = TextEditingController();
  final _merchantCtrl = TextEditingController();
  String _category = 'Other';
  DateTime _date = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _amountCtrl.dispose();
    _merchantCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    final now = DateTime.now();
    setState(() {
      // Keep the current time for today; noon for past days so the entry
      // lands mid-day rather than at midnight.
      _date = picked.year == now.year &&
              picked.month == now.month &&
              picked.day == now.day
          ? now
          : DateTime(picked.year, picked.month, picked.day, 12);
    });
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amountCtrl.text.trim());
    final merchant = _merchantCtrl.text.trim();
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter an amount above zero')),
      );
      return;
    }
    if (merchant.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a name for this payment')),
      );
      return;
    }
    setState(() => _saving = true);
    await context.read<ExpenseProvider>().addExpense(Expense(
          merchant: merchant,
          amount: amount,
          date: _date,
          rawSms: '', // manual entry — backend skips SMS dedupe by design
          isLabeled: true,
          category: _category,
        ));
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        decoration: const BoxDecoration(
          color: Klaro.overlay,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(Klaro.radiusXl)),
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
            const Text(
              'Add expense',
              style: TextStyle(
                fontFamily: Klaro.display,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Klaro.text,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'For payments without a bank SMS (UPI Lite, wallets, cash)',
              style: TextStyle(fontSize: 11.5, color: Klaro.textFaint),
            ),
            const Divider(height: 24),
            TextField(
              controller: _amountCtrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
              ],
              decoration: const InputDecoration(
                labelText: 'Amount',
                prefixText: '₹ ',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 12),
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
                  onPressed: _saving ? null : _pickDate,
                  icon: const Icon(Icons.event_outlined,
                      size: 18, color: Klaro.textMuted),
                  label: Text(
                    DateFormat('d MMM yyyy').format(_date),
                    style: const TextStyle(color: Klaro.textMuted),
                  ),
                ),
                const Spacer(),
                KlaroButton(
                  onPressed: _saving ? null : _save,
                  label: 'Add',
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
