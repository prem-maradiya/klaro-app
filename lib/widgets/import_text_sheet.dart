import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/expense_provider.dart';
import '../services/sms_service.dart';
import '../theme/klaro.dart';
import 'klaro_button.dart';

/// Paste / forward a transaction's text (a UPI or receipt SMS, or a bank email)
/// and Klaro extracts + files it — entirely ON-DEVICE (same parser as inbox
/// SMS, no network). This is the import path on builds without SMS access (the
/// Play build), and a handy fallback on any build.
class ImportTextSheet extends StatefulWidget {
  const ImportTextSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const ImportTextSheet(),
    );
  }

  @override
  State<ImportTextSheet> createState() => _ImportTextSheetState();
}

class _ImportTextSheetState extends State<ImportTextSheet> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _import() async {
    final text = _ctrl.text.trim();
    if (text.length < 8) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paste the transaction message first')),
      );
      return;
    }
    setState(() => _busy = true);
    // Parse on-device — the pasted text never leaves the phone.
    final expense = SmsService.parsePastedText(text);
    if (!mounted) return;
    setState(() => _busy = false);

    if (expense == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              "Couldn't find a transaction in that text. Paste the full bank/UPI message."),
        ),
      );
      return;
    }

    // Add locally (and sync the cleaned record if the dashboard is enabled).
    await context.read<ExpenseProvider>().addExpense(expense);
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Imported ₹${expense.amount.toStringAsFixed(2)} · '
            '${expense.merchant}'),
      ),
    );
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
              'Import from text',
              style: TextStyle(
                fontFamily: Klaro.display,
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Klaro.text,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Paste a bank/UPI message or receipt — Klaro reads the amount, '
              'merchant and category for you.',
              style: TextStyle(fontSize: 11.5, color: Klaro.textFaint),
            ),
            const Divider(height: 24),
            TextField(
              controller: _ctrl,
              autofocus: true,
              minLines: 3,
              maxLines: 6,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Transaction message',
                hintText:
                    'e.g. "Rs 250 debited from a/c …0356 at STARBUCKS on …"',
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Spacer(),
                KlaroButton(
                  onPressed: _busy ? null : _import,
                  label: 'Import',
                  icon: Icons.auto_awesome,
                  loading: _busy,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
