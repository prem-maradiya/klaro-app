import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/build_config.dart';
import '../models/expense.dart';
import '../providers/expense_provider.dart';
import '../services/budget_service.dart';
import '../theme/klaro.dart';
import '../widgets/add_expense_sheet.dart';
import '../widgets/category_donut.dart';
import '../widgets/edit_expense_sheet.dart';
import '../widgets/import_text_sheet.dart';
import '../widgets/income_sheet.dart';
import '../widgets/klaro_button.dart';
import '../widgets/oneoff_sheet.dart';
import '../widgets/spending_chart.dart';
import 'budgets_screen.dart';
import 'label_screen.dart';
import 'recurring_screen.dart';
import 'settings_screen.dart';
import 'trends_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back to the app — reload to surface anything the background isolate
    // captured while we were away.
    if (state == AppLifecycleState.resumed && _initialized) {
      context.read<ExpenseProvider>().reloadFromDisk();
    }
  }

  Future<void> _init() async {
    final provider = context.read<ExpenseProvider>();
    await provider.initialize();
    // Post-login: if this device has no local history yet (fresh install / new
    // device), pull the account's transactions from the backend so they show
    // immediately instead of waiting on an SMS re-scan.
    await provider.hydrateFromBackend();
    if (mounted) setState(() => _initialized = true);
    _maybeRequestBackgroundPermission();
  }

  // Ask once to ignore battery optimization so SMS keep being caught in the
  // background (Vivo kills background apps aggressively). Skipped on the no-SMS
  // (Play) build, which has nothing running in the background to protect.
  Future<void> _maybeRequestBackgroundPermission() async {
    if (!kSmsEnabled) return;
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('battery_opt_asked') == true) return;
    await prefs.setBool('battery_opt_asked', true);
    if (!await Permission.ignoreBatteryOptimizations.isGranted) {
      await Permission.ignoreBatteryOptimizations.request();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Image.asset('assets/brand/klaro_mark.png', width: 26, height: 26),
            const SizedBox(width: 10),
            const Text('Klaro'),
          ],
        ),
        actions: [
          Consumer<ExpenseProvider>(
            builder: (_, provider, __) {
              final count = provider.unlabeled.length;
              return count == 0
                  ? const SizedBox.shrink()
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.label_outline),
                          tooltip: 'Label unknown merchants',
                          onPressed: () => _openLabelScreen(context),
                        ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: Klaro.danger,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '$count',
                              style: const TextStyle(
                                  color: Colors.white, fontSize: 10),
                            ),
                          ),
                        ),
                      ],
                    );
            },
          ),
          IconButton(
            icon: const Icon(Icons.autorenew),
            tooltip: 'Upcoming payments',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const RecurringScreen())),
          ),
          IconButton(
            icon: const Icon(Icons.account_balance_wallet_outlined),
            tooltip: 'Budgets',
            onPressed: () => Navigator.push(context,
                MaterialPageRoute(builder: (_) => const BudgetsScreen())),
          ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'import') {
                await _importInbox();
              } else if (v == 'import_text') {
                await ImportTextSheet.show(context);
              } else if (v == 'recurring') {
                if (!mounted) return;
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const RecurringScreen()));
              } else if (v == 'trends') {
                if (!mounted) return;
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const TrendsScreen()));
              } else if (v == 'budgets') {
                if (!mounted) return;
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const BudgetsScreen()));
              } else if (v == 'settings') {
                if (!mounted) return;
                Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const SettingsScreen()));
              }
            },
            itemBuilder: (_) => [
              // SMS inbox import only exists on builds with SMS access.
              if (kSmsEnabled)
                const PopupMenuItem(
                    value: 'import', child: Text('Import from SMS inbox')),
              const PopupMenuItem(
                  value: 'import_text', child: Text('Import from text')),
              const PopupMenuItem(
                  value: 'recurring', child: Text('Upcoming payments')),
              const PopupMenuItem(
                  value: 'trends', child: Text('Spending trends')),
              const PopupMenuItem(value: 'budgets', child: Text('Budgets')),
              const PopupMenuItem(value: 'settings', child: Text('Settings')),
            ],
          ),
        ],
      ),
      body: _initialized
          ? const _Body()
          : const Center(child: CircularProgressIndicator()),
      floatingActionButton: FloatingActionButton(
        tooltip: 'Add expense',
        backgroundColor: Klaro.violet,
        foregroundColor: Colors.white,
        onPressed: () => AddExpenseSheet.show(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Future<void> _importInbox() async {
    final provider = context.read<ExpenseProvider>();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Scanning SMS inbox…')),
    );
    await provider.importFromInbox();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Import complete')),
      );
    }
  }

  void _openLabelScreen(BuildContext context) {
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const LabelScreen()));
  }
}

class _Body extends StatelessWidget {
  const _Body();

  @override
  Widget build(BuildContext context) {
    return Consumer<ExpenseProvider>(
      builder: (_, provider, __) {
        if (provider.expenses.isEmpty) {
          return const _EmptyState();
        }
        return CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _SummaryCard(provider: provider)),
            // Fresh install that has captured a payment or two but never pulled
            // in the inbox history — offer it once, compactly.
            if (provider.needsHistoryImport)
              SliverToBoxAdapter(
                child: _HistoryImportCard(provider: provider, compact: true),
              ),
            if (provider.budgetReviewQueue.isNotEmpty)
              SliverToBoxAdapter(
                child: _BudgetReviewCard(
                  items: provider.budgetReviewQueue,
                  onDecide: provider.setInBudget,
                ),
              ),
            if (provider.budgetedThisMonth > 0)
              SliverToBoxAdapter(
                child: SpendingChartCard(
                  daily: provider.dailySpendThisMonth,
                  monthLabel: DateFormat('MMMM').format(DateTime.now()),
                ),
              ),
            if (provider.categoryTotals.isNotEmpty)
              SliverToBoxAdapter(
                child: CategoryDonutCard(totals: provider.categoryTotals),
              ),
            if (provider.pendingSyncCount > 0)
              SliverToBoxAdapter(
                child: _SyncBanner(
                  count: provider.pendingSyncCount,
                  failed: provider.syncFailed,
                  onRetry: provider.syncNow,
                ),
              ),
            if (provider.unlabeled.isNotEmpty)
              SliverToBoxAdapter(
                  child: _UnlabeledBanner(count: provider.unlabeled.length)),
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverList.separated(
                itemCount: provider.expenses.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) => _ExpenseTile(
                  expense: provider.expenses[i],
                  syncFailed: provider.syncFailed,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.provider});
  final ExpenseProvider provider;

  @override
  Widget build(BuildContext context) {
    final month = DateFormat('MMMM yyyy').format(DateTime.now());

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Klaro.surface,
        borderRadius: BorderRadius.circular(Klaro.radiusXl),
        border: Border.all(color: Klaro.line),
        boxShadow: [
          // Soft brand glow instead of a hard shadow (dark-first elevation).
          BoxShadow(
            color: Klaro.violet.withValues(alpha: 0.12),
            blurRadius: 28,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Spent in $month',
            style: const TextStyle(color: Klaro.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Text(
            // Day-to-day spend — one-off / fee payments are shown separately
            // below so a single large payment can't dominate the headline.
            '₹${provider.budgetedThisMonth.toStringAsFixed(2)}',
            style: Klaro.figures(size: 34, weight: FontWeight.w600),
          ),
          ListenableBuilder(
            listenable: BudgetService.instance,
            builder: (context, _) => _BudgetBar(
              // Budget tracks day-to-day spend; large one-off / fee payments are
              // held out (shown separately below) so they can't falsely blow it.
              spent: provider.budgetedThisMonth,
              limit: BudgetService.instance.overall,
            ),
          ),
          // Make the held-out one-off spend visible so the headline total still
          // reconciles (budgeted + one-off = total). Tap to see/manage the list.
          if (provider.oneoffThisMonth > 0) ...[
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(Klaro.radiusMd),
              onTap: () => OneOffSheet.show(
                context,
                provider: provider,
                monthLabel: DateFormat('MMMM').format(DateTime.now()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.bookmark_remove_outlined,
                        size: 13, color: Klaro.textMuted),
                    const SizedBox(width: 4),
                    Text(
                      '+ ₹${provider.oneoffThisMonth.toStringAsFixed(0)} one-off (not in budget)',
                      style:
                          const TextStyle(color: Klaro.textMuted, fontSize: 12.5),
                    ),
                    const Icon(Icons.chevron_right,
                        size: 16, color: Klaro.textFaint),
                  ],
                ),
              ),
            ),
          ],
          // Net cash flow — only once some income (credits) has been captured.
          // Tap to break the income down by source.
          if (provider.incomeThisMonth > 0) ...[
            const SizedBox(height: 6),
            InkWell(
              borderRadius: BorderRadius.circular(Klaro.radiusMd),
              onTap: () => IncomeSheet.show(
                context,
                entries: provider.incomeThisMonthEntries,
                monthLabel: DateFormat('MMMM').format(DateTime.now()),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.south_west, size: 13, color: Klaro.positive),
                    const SizedBox(width: 4),
                    Text(
                      '₹${provider.incomeThisMonth.toStringAsFixed(0)} in',
                      style: const TextStyle(
                          color: Klaro.positive,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Net ${provider.netThisMonth >= 0 ? '+' : '−'}₹${provider.netThisMonth.abs().toStringAsFixed(0)}',
                      style: TextStyle(
                        color: provider.netThisMonth >= 0
                            ? Klaro.positive
                            : Klaro.textMuted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(Icons.chevron_right,
                        size: 15, color: Klaro.textFaint),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Overall monthly-budget progress under the month total. Hidden until a
/// budget is set (in ⋮ → Budgets). Violet while comfortable, alert at 80%,
/// danger once exceeded — tap goes to the Budgets screen.
class _BudgetBar extends StatelessWidget {
  const _BudgetBar({required this.spent, this.limit});
  final double spent;
  final double? limit;

  @override
  Widget build(BuildContext context) {
    final l = limit;
    if (l == null || l <= 0) return const SizedBox.shrink();

    final pct = (spent / l).clamp(0.0, 1.0);
    final over = spent >= l;
    final near = !over && spent >= l * 0.8;
    final color = over ? Klaro.danger : (near ? Klaro.alert : Klaro.violet);

    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const BudgetsScreen())),
      child: Padding(
        padding: const EdgeInsets.only(top: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct,
                minHeight: 6,
                backgroundColor: Klaro.line,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
            const SizedBox(height: 5),
            Text(
              over
                  ? 'Budget exceeded — ₹${(spent - l).toStringAsFixed(0)} over ₹${l.toStringAsFixed(0)}'
                  : '${(pct * 100).round()}% of ₹${l.toStringAsFixed(0)} budget · ₹${(l - spent).toStringAsFixed(0)} left',
              style: TextStyle(
                fontSize: 11.5,
                color: over ? Klaro.danger : Klaro.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Prompts the user to decide whether large/fee-like captures count toward the
/// monthly budget. They're held out until decided, so a one-time college fee or
/// rent payment never triggers a false "budget exceeded".
class _BudgetReviewCard extends StatelessWidget {
  const _BudgetReviewCard({required this.items, required this.onDecide});
  final List<Expense> items;
  final Future<void> Function(Expense, bool) onDecide;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Klaro.alert.withValues(alpha: 0.08),
        border: Border.all(color: Klaro.alert.withValues(alpha: 0.30)),
        borderRadius: BorderRadius.circular(Klaro.radiusMd),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.help_outline, size: 18, color: Klaro.alert),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  items.length == 1
                      ? 'A large payment — count it in your budget?'
                      : '${items.length} large payments — count them in your budget?',
                  style: const TextStyle(
                      color: Klaro.text,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 26, top: 2),
            child: Text(
              "Held out until you decide, so a one-off can't falsely blow your budget.",
              style: TextStyle(color: Klaro.textMuted, fontSize: 11.5),
            ),
          ),
          const SizedBox(height: 12),
          for (final e in items) _ReviewRow(expense: e, onDecide: onDecide),
        ],
      ),
    );
  }
}

class _ReviewRow extends StatelessWidget {
  const _ReviewRow({required this.expense, required this.onDecide});
  final Expense expense;
  final Future<void> Function(Expense, bool) onDecide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  expense.merchant.isEmpty ? 'Unknown' : expense.merchant,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Klaro.text, fontSize: 13),
                ),
                Text(
                  '₹${expense.amount.toStringAsFixed(0)}'
                  '${expense.category != null ? ' · ${expense.category}' : ''}',
                  style: const TextStyle(color: Klaro.textMuted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => onDecide(expense, false),
            style: TextButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10)),
            child: const Text('One-off',
                style: TextStyle(color: Klaro.textMuted, fontSize: 12.5)),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: () => onDecide(expense, true),
            style: FilledButton.styleFrom(
                backgroundColor: Klaro.violet,
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 12)),
            child: const Text('In budget', style: TextStyle(fontSize: 12.5)),
          ),
        ],
      ),
    );
  }
}

/// Sync state strip: quiet while retrying in the background, alert-tinted with
/// tap-to-retry once the backoff is exhausted (e.g. backend off / no network).
class _SyncBanner extends StatelessWidget {
  const _SyncBanner(
      {required this.count, required this.failed, required this.onRetry});
  final int count;
  final bool failed;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final color = failed ? Klaro.alert : Klaro.textMuted;
    return GestureDetector(
      onTap: onRetry,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: failed
              ? Klaro.alert.withValues(alpha: 0.10)
              : Klaro.raised.withValues(alpha: 0.6),
          border: Border.all(
              color: failed
                  ? Klaro.alert.withValues(alpha: 0.35)
                  : Klaro.line),
          borderRadius: BorderRadius.circular(Klaro.radiusMd),
        ),
        child: Row(
          children: [
            Icon(failed ? Icons.cloud_off : Icons.cloud_upload_outlined,
                color: color, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                failed
                    ? '$count change${count > 1 ? 's' : ''} not synced — tap to retry'
                    : 'Syncing $count change${count > 1 ? 's' : ''}…',
                style: TextStyle(
                    color: color, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
            if (failed) Icon(Icons.refresh, color: color, size: 18),
          ],
        ),
      ),
    );
  }
}

class _UnlabeledBanner extends StatelessWidget {
  const _UnlabeledBanner({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
          context, MaterialPageRoute(builder: (_) => const LabelScreen())),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Klaro.alert.withValues(alpha: 0.10),
          border: Border.all(color: Klaro.alert.withValues(alpha: 0.35)),
          borderRadius: BorderRadius.circular(Klaro.radiusMd),
        ),
        child: Row(
          children: [
            const Icon(Icons.label_outline, color: Klaro.alert, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$count expense${count > 1 ? 's' : ''} need labeling',
                style: const TextStyle(
                    color: Klaro.alert, fontWeight: FontWeight.w500),
              ),
            ),
            const Icon(Icons.chevron_right, color: Klaro.alert),
          ],
        ),
      ),
    );
  }
}

class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.expense, this.syncFailed = false});
  final Expense expense;

  /// Whether the global sync engine has given up — switches the pending
  /// indicator from "uploading" to "offline".
  final bool syncFailed;

  @override
  Widget build(BuildContext context) {
    final dateStr = DateFormat('d MMM, h:mm a').format(expense.date);
    final isCard = expense.isCard;
    final catColor = Klaro.categoryColor(expense.category);

    // Card payments carry the brand violet; UPI rows take their category color
    // (alert orange while unlabeled).
    final Color accent = isCard
        ? Klaro.violetLt
        : (expense.needsLabel ? Klaro.alert : catColor);

    return Container(
      decoration: BoxDecoration(
        color: isCard ? Klaro.raised : Klaro.surface,
        borderRadius: BorderRadius.circular(Klaro.radiusLg),
        border: isCard
            ? const Border(
                left: BorderSide(color: Klaro.violet, width: 3),
                top: BorderSide(color: Klaro.line),
                right: BorderSide(color: Klaro.line),
                bottom: BorderSide(color: Klaro.line),
              )
            : Border.all(color: Klaro.line),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: accent.withValues(alpha: 0.16),
          child: isCard
              ? Icon(Icons.credit_card, size: 16, color: accent)
              : Text(
                  expense.needsLabel
                      ? '?'
                      : expense.merchant[0].toUpperCase(),
                  style: TextStyle(fontWeight: FontWeight.bold, color: accent),
                ),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                expense.merchant,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.w600, color: Klaro.text),
              ),
            ),
            if (isCard) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Klaro.violet.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(5),
                  border:
                      Border.all(color: Klaro.violet.withValues(alpha: 0.45)),
                ),
                child: const Text(
                  'CARD',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Klaro.violetLt,
                  ),
                ),
              ),
            ],
            // Marks a spend the user kept out of the budget (a one-off / fee).
            // It still shows here and in the month total — just not the budget.
            if (expense.excludedFromBudget) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Klaro.textMuted.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: Klaro.line),
                ),
                child: const Text(
                  'ONE-OFF',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Klaro.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${expense.category ?? (expense.needsLabel ? 'Needs label' : 'Other')} • $dateStr',
          style: const TextStyle(fontSize: 12, color: Klaro.textMuted),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${expense.isIncome ? '+' : ''}₹${expense.amount.toStringAsFixed(2)}',
              style: Klaro.figures(size: 15, weight: FontWeight.w600)
                  .copyWith(color: expense.isIncome ? Klaro.positive : null),
            ),
            if (!expense.isSynced) ...[
              const SizedBox(height: 3),
              Icon(
                syncFailed ? Icons.cloud_off : Icons.cloud_upload_outlined,
                size: 13,
                color: syncFailed ? Klaro.alert : Klaro.textFaint,
              ),
            ],
          ],
        ),
        onTap: () => EditExpenseSheet.show(context, expense),
      ),
    );
  }
}

/// First-run offer to pull in the bank SMS already sitting in the phone's inbox,
/// so a new install opens with real spending instead of a blank screen (the
/// single biggest "this app doesn't work" moment). Shown until the user imports
/// or dismisses — then never again.
class _HistoryImportCard extends StatelessWidget {
  const _HistoryImportCard({required this.provider, this.compact = false});

  final ExpenseProvider provider;

  /// Compact banner (some data already present) vs. the full empty-state pitch.
  final bool compact;

  Future<void> _import(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final r = await provider.importHistory();
    // Distinguish "nothing in the inbox" from "the inbox is already tracked" —
    // the latter is the normal result for a returning user on a new phone.
    final message = r.added > 0
        ? 'Imported ${r.added} transaction${r.added == 1 ? '' : 's'} from your inbox'
        : r.found > 0
            ? 'Already up to date — those payments are all tracked'
            : 'No bank messages found in your inbox yet';
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final busy = provider.importingHistory;
    const months = ExpenseProvider.historyImportMonths;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 8 : 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Klaro.raised,
        borderRadius: BorderRadius.circular(Klaro.radiusLg),
        border: Border.all(color: Klaro.violet.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: Klaro.gradient,
                  borderRadius: BorderRadius.circular(Klaro.radiusMd),
                ),
                child: const Icon(Icons.history, color: Colors.white, size: 18),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Bring in your past spending',
                  style: TextStyle(
                    fontFamily: Klaro.display,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: Klaro.text,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Your phone already has months of bank messages. Klaro can read the '
            'last $months months right here on your device — so you start with a '
            'full picture instead of an empty screen.',
            style: TextStyle(color: Klaro.textMuted, fontSize: 12.5, height: 1.45),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: KlaroButton(
                  onPressed: busy ? null : () => _import(context),
                  label: busy ? 'Importing…' : 'Import last $months months',
                  icon: busy ? null : Icons.download_outlined,
                  loading: busy,
                ),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: busy ? null : provider.dismissHistoryImport,
                child: const Text('Not now',
                    style: TextStyle(color: Klaro.textMuted, fontSize: 12.5)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ExpenseProvider>();
    // A fresh install with an unread inbox: lead with the import offer instead
    // of a dead-end "no expenses yet".
    if (provider.needsHistoryImport) {
      return Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [_HistoryImportCard(provider: provider)],
          ),
        ),
      );
    }
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.receipt_long_outlined,
              size: 72, color: Klaro.textFaint),
          const SizedBox(height: 16),
          const Text('No expenses yet',
              style: TextStyle(color: Klaro.textMuted, fontSize: 18)),
          const SizedBox(height: 8),
          Text(
            kSmsEnabled
                ? 'Expenses will appear automatically\nwhen UPI payments are received'
                : 'Add a payment with the + button,\nor paste a bank message to import it',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Klaro.textFaint, fontSize: 13),
          ),
          const SizedBox(height: 24),
          if (kSmsEnabled)
            TextButton.icon(
              onPressed: () => context.read<ExpenseProvider>().importFromInbox(),
              icon: const Icon(Icons.inbox),
              label: const Text('Import from SMS inbox'),
            )
          else
            TextButton.icon(
              onPressed: () => ImportTextSheet.show(context),
              icon: const Icon(Icons.content_paste),
              label: const Text('Import from text'),
            ),
        ],
      ),
    );
  }
}
