import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/sms_service.dart';
import '../theme/klaro.dart';
import '../widgets/klaro_button.dart';

class LabelScreen extends StatelessWidget {
  const LabelScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Label expenses')),
      body: Consumer<ExpenseProvider>(
        builder: (_, provider, __) {
          final items = provider.unlabeled;
          if (items.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle_outline,
                      size: 64, color: Klaro.positive),
                  SizedBox(height: 12),
                  Text('All expenses labeled!',
                      style: TextStyle(fontSize: 18, color: Klaro.textMuted)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (ctx, i) => _LabelCard(expense: items[i]),
          );
        },
      ),
    );
  }
}

class _LabelCard extends StatefulWidget {
  const _LabelCard({required this.expense});
  final Expense expense;

  @override
  State<_LabelCard> createState() => _LabelCardState();
}

class _LabelCardState extends State<_LabelCard> {
  late final TextEditingController _merchantCtrl;
  String _category = 'Other';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Pre-fill with UPI prefix as a hint
    final hint = widget.expense.upiId?.split('@').first ?? '';
    _merchantCtrl = TextEditingController(text: hint);
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
    if (mounted) setState(() => _saving = false);
  }

  @override
  Widget build(BuildContext context) {
    final e = widget.expense;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Klaro.surface,
        borderRadius: BorderRadius.circular(Klaro.radiusLg),
        border: Border.all(color: Klaro.alert.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
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
                  style: Klaro.figures(size: 15, weight: FontWeight.w600),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.upiId ?? 'Unknown UPI',
                  style:
                      const TextStyle(color: Klaro.textMuted, fontSize: 13),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            e.rawSms,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Klaro.textFaint),
          ),
          const Divider(height: 20),
          TextField(
            controller: _merchantCtrl,
            decoration: const InputDecoration(
              labelText: 'Merchant name',
              hintText: 'e.g. Local grocery shop',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            textCapitalization: TextCapitalization.words,
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(
              labelText: 'Category',
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
            ),
            items: SmsService.allCategories
                .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                .toList(),
            onChanged: (v) => setState(() => _category = v ?? 'Other'),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () =>
                    context.read<ExpenseProvider>().deleteExpense(widget.expense),
                child:
                    const Text('Delete', style: TextStyle(color: Klaro.danger)),
              ),
              const SizedBox(width: 8),
              KlaroButton(
                onPressed: _saving ? null : _save,
                label: 'Save',
                loading: _saving,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
