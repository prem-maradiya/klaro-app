import 'package:flutter/material.dart';
import '../models/recurring.dart';
import '../services/api_service.dart';
import '../theme/klaro.dart';

/// "Upcoming payments" — subscriptions, EMIs and regular bills the backend
/// detected, each with a predicted next-due date. Mirrors the web dashboard's
/// RecurringCard; the detection is computed server-side so the phone and the
/// dashboard never drift.
class RecurringScreen extends StatefulWidget {
  const RecurringScreen({super.key});

  @override
  State<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends State<RecurringScreen> {
  late Future<RecurringSummary?> _future;

  @override
  void initState() {
    super.initState();
    _future = ApiService.instance.fetchRecurring();
  }

  Future<void> _reload() async {
    final f = ApiService.instance.fetchRecurring();
    setState(() => _future = f);
    await f;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Upcoming payments')),
      body: RefreshIndicator(
        onRefresh: _reload,
        color: Klaro.violet,
        backgroundColor: Klaro.surface,
        child: FutureBuilder<RecurringSummary?>(
          future: _future,
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: CircularProgressIndicator()),
                ],
              );
            }
            final data = snap.data;
            if (data == null) {
              return const _MessageState(
                icon: Icons.cloud_off,
                title: "Couldn't load recurring payments",
                body: 'Klaro needs to reach your backend to detect '
                    'subscriptions. Check the connection in Settings, then pull '
                    'down to retry.',
              );
            }
            if (data.items.isEmpty) {
              return const _MessageState(
                icon: Icons.event_repeat,
                title: 'No recurring payments yet',
                body: 'Subscriptions, EMIs and regular bills appear here '
                    'automatically as Klaro spots the pattern — usually from '
                    'the second charge onward.',
              );
            }
            return _RecurringList(data: data);
          },
        ),
      ),
    );
  }
}

class _RecurringList extends StatefulWidget {
  const _RecurringList({required this.data});

  final RecurringSummary data;

  @override
  State<_RecurringList> createState() => _RecurringListState();
}

class _RecurringListState extends State<_RecurringList> {
  late List<RecurringPayment> _items;
  // Sum of monthly-equivalents we've removed, so the header total stays in step
  // with the server figure (which it exactly matches on first paint).
  double _removedMonthly = 0;

  @override
  void initState() {
    super.initState();
    _items = _sorted(widget.data.items);
  }

  // Soonest due first; undated items sink to the bottom.
  List<RecurringPayment> _sorted(List<RecurringPayment> src) {
    return [...src]..sort((a, b) {
        final ad = a.nextDue, bd = b.nextDue;
        if (ad == null && bd == null) return 0;
        if (ad == null) return 1;
        if (bd == null) return -1;
        return ad.compareTo(bd);
      });
  }

  /// Rough monthly cost of one payment, mirroring the backend's normalization,
  /// so removing a row decrements the header by the right amount.
  double _monthlyEquivalent(RecurringPayment r) {
    switch (r.cadence.toLowerCase()) {
      case 'weekly':
        return r.amount * 4.345;
      case 'fortnightly':
      case 'biweekly':
        return r.amount * 2.173;
      case 'quarterly':
        return r.amount / 3;
      case 'yearly':
      case 'annually':
        return r.amount / 12;
      case 'daily':
        return r.amount * 30.4;
      default: // monthly and anything unrecognised
        return r.amount;
    }
  }

  Future<void> _dismiss(RecurringPayment item, int index) async {
    setState(() {
      _items.removeAt(index);
      _removedMonthly += _monthlyEquivalent(item);
    });
    // Fire the API call; UI is already optimistic. Failure is surfaced via the
    // SnackBar copy so the user knows it didn't stick.
    final ok = await ApiService.instance.dismissRecurring(item.merchant);
    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        backgroundColor: Klaro.raised,
        behavior: SnackBarBehavior.floating,
        content: Text(
          ok
              ? '${item.merchant} dismissed'
              : "Couldn't reach backend — will retry on refresh",
          style: const TextStyle(color: Klaro.text),
        ),
        action: SnackBarAction(
          label: 'Undo',
          textColor: Klaro.violetLt,
          onPressed: () => _restore(item, index),
        ),
      ),
    );
  }

  Future<void> _restore(RecurringPayment item, int index) async {
    setState(() {
      _items.insert(index.clamp(0, _items.length), item);
      _items = _sorted(_items);
      _removedMonthly =
          (_removedMonthly - _monthlyEquivalent(item)).clamp(0, double.infinity);
    });
    await ApiService.instance.restoreRecurring(item.merchant);
  }

  @override
  Widget build(BuildContext context) {
    final total =
        (widget.data.monthlyTotal - _removedMonthly).clamp(0, double.infinity);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _SummaryHeader(monthlyTotal: total.toDouble(), count: _items.length),
        const SizedBox(height: 16),
        if (_items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 28, horizontal: 8),
            child: Text(
              'All recurring payments dismissed. Pull down to refresh, or undo '
              'above.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Klaro.textMuted, fontSize: 13),
            ),
          ),
        for (var i = 0; i < _items.length; i++)
          Dismissible(
            key: ValueKey(_items[i].merchant),
            direction: DismissDirection.endToStart,
            background: _DismissBackground(),
            onDismissed: (_) => _dismiss(_items[i], i),
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _RecurringTile(item: _items[i]),
            ),
          ),
        const SizedBox(height: 8),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            'Detected from your transaction history — amounts and dates are '
            'estimates from past charges. Swipe left to dismiss one you no '
            'longer pay.',
            style:
                TextStyle(color: Klaro.textFaint, fontSize: 11.5, height: 1.4),
          ),
        ),
      ],
    );
  }
}

/// Red "remove" affordance revealed as a recurring row is swiped left.
class _DismissBackground extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.only(right: 20),
      alignment: Alignment.centerRight,
      decoration: BoxDecoration(
        color: Klaro.danger.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(Klaro.radiusLg),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Dismiss',
            style: TextStyle(
                color: Klaro.danger, fontSize: 13, fontWeight: FontWeight.w600),
          ),
          SizedBox(width: 8),
          Icon(Icons.delete_outline, color: Klaro.danger, size: 20),
        ],
      ),
    );
  }
}

class _SummaryHeader extends StatelessWidget {
  const _SummaryHeader({required this.monthlyTotal, required this.count});

  final double monthlyTotal;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Klaro.raised,
        borderRadius: BorderRadius.circular(Klaro.radiusLg),
        border: Border.all(color: Klaro.line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Klaro.violet.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(Klaro.radiusMd),
            ),
            child: const Icon(Icons.autorenew, color: Klaro.violetLt, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recurring per month',
                  style: TextStyle(color: Klaro.textMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 3),
                Text(
                  '₹${monthlyTotal.toStringAsFixed(0)}',
                  style: Klaro.figures(size: 24, weight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(
            '$count active',
            style: const TextStyle(color: Klaro.textMuted, fontSize: 12.5),
          ),
        ],
      ),
    );
  }
}

class _RecurringTile extends StatelessWidget {
  const _RecurringTile({required this.item});

  final RecurringPayment item;

  @override
  Widget build(BuildContext context) {
    final color = Klaro.categoryColor(item.category);
    final due = _dueLabel(item.nextDue);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Klaro.surface,
        borderRadius: BorderRadius.circular(Klaro.radiusLg),
        border: Border.all(color: Klaro.line),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Klaro.text,
                    fontWeight: FontWeight.w600,
                    fontSize: 14.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${item.cadence} · ${item.category ?? 'Other'}',
                  style: const TextStyle(color: Klaro.textMuted, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '₹${item.amount.toStringAsFixed(0)}',
                style: Klaro.figures(size: 15, weight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.event_outlined,
                    size: 12,
                    color: due.soon ? Klaro.violetLt : Klaro.textFaint,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    due.text,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: due.soon ? Klaro.violetLt : Klaro.textFaint,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MessageState extends StatelessWidget {
  const _MessageState({
    required this.icon,
    required this.title,
    required this.body,
  });

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    // ListView (not Center) so RefreshIndicator's pull-to-retry still works.
    return ListView(
      padding: const EdgeInsets.fromLTRB(28, 96, 28, 28),
      children: [
        Icon(icon, size: 44, color: Klaro.textFaint),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: Klaro.display,
            fontSize: 17,
            color: Klaro.text,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          body,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            height: 1.5,
            color: Klaro.textMuted,
          ),
        ),
      ],
    );
  }
}

class _Due {
  const _Due(this.text, this.soon);
  final String text;
  final bool soon; // within a week / overdue → highlight
}

_Due _dueLabel(DateTime? due) {
  if (due == null) return const _Due('—', false);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final d = DateTime(due.year, due.month, due.day);
  final days = d.difference(today).inDays;
  if (days < 0) return const _Due('overdue', true);
  if (days == 0) return const _Due('due today', true);
  if (days == 1) return const _Due('tomorrow', true);
  if (days <= 7) return _Due('in $days days', true);
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  return _Due('${months[d.month - 1]} ${d.day}', false);
}
