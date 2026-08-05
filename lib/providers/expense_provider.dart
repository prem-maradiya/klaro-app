import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/build_config.dart';
import '../models/expense.dart';
import '../services/api_service.dart';
import '../services/budget_pacing.dart';
import '../services/budget_service.dart';
import '../services/contacts_service.dart';
import '../services/sms_service.dart';

/// One month's total spend — `month` is the first day of that calendar month.
typedef MonthSpend = ({DateTime month, double total});

/// Escalating retry delays for backend sync. After the last delay the engine
/// stops scheduling (syncFailed) until connectivity returns, the app resumes,
/// or the user taps retry — all of which reset it.
class SyncBackoff {
  static const delays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(minutes: 1),
    Duration(minutes: 5),
    Duration(minutes: 15),
  ];

  int _attempt = 0;

  /// Next delay to wait, or null when out of retries.
  Duration? nextDelay() =>
      _attempt < delays.length ? delays[_attempt++] : null;

  void reset() => _attempt = 0;
}

class ExpenseProvider extends ChangeNotifier {
  static const _localKey = 'local_expenses';
  static const _deletesKey = 'pending_deletes';
  static const _catchupKey = 'last_catchup_ms';
  // Set once the user has imported (or declined) their SMS history, so the
  // first-run offer is never shown again.
  static const _historyDoneKey = 'history_import_done';

  /// How far back the first-run history import reaches.
  static const historyImportMonths = 6;

  final List<Expense> _expenses = [];

  // Backend ids deleted locally while the backend was unreachable — drained by
  // the sync engine so deletes are never lost.
  final List<int> _pendingDeletes = [];

  final SyncBackoff _backoff = SyncBackoff();
  Timer? _syncTimer;
  StreamSubscription<List<ConnectivityResult>>? _connSub;
  bool _syncing = false;
  bool _syncGaveUp = false;

  // First-run history import: the phone's inbox already holds months of bank
  // messages, so a brand-new install can be populated instantly instead of
  // starting empty (which reads as "the app doesn't work").
  bool _needsHistoryImport = false;
  bool _importingHistory = false;

  /// True when this is a fresh install with SMS access and the user hasn't yet
  /// imported (or declined) their existing inbox history — the home screen
  /// offers a one-tap import while this is set.
  bool get needsHistoryImport => _needsHistoryImport;

  /// True while the history import is running (drives the progress state).
  bool get importingHistory => _importingHistory;

  // Always newest-first for display, regardless of insertion/import order.
  List<Expense> get expenses {
    final sorted = [..._expenses]..sort((a, b) => b.date.compareTo(a.date));
    return List.unmodifiable(sorted);
  }

  List<Expense> get unlabeled {
    return _expenses.where((e) => e.needsLabel).toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Local changes the backend doesn't have yet (new + edited + deleted).
  int get pendingSyncCount =>
      _expenses.where((e) => !e.isSynced).length + _pendingDeletes.length;

  /// True when retries are exhausted and changes are still waiting — the UI
  /// offers a manual retry (which also fires automatically on reconnect).
  bool get syncFailed => _syncGaveUp && pendingSyncCount > 0;

  /// Grand total of this month's spending — ALL labeled debits, including large
  /// one-off / fee payments held out of the budget. Used for net cash flow (the
  /// money genuinely left the account); the headline + charts use the day-to-day
  /// figure [budgetedThisMonth] instead so a one-off can't dominate the view.
  double get totalThisMonth {
    final now = DateTime.now();
    return _expenses
        .where((e) =>
            e.date.year == now.year &&
            e.date.month == now.month &&
            !e.needsLabel &&
            !e.isIncome) // income is not a spend
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  /// Money in this month (credits — salary, refunds, transfers received).
  double get incomeThisMonth {
    final now = DateTime.now();
    return _expenses
        .where((e) =>
            e.date.year == now.year && e.date.month == now.month && e.isIncome)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  /// Net cash flow this month: income minus spending.
  double get netThisMonth => incomeThisMonth - totalThisMonth;

  /// Spend per day of the current month so far (index 0 = the 1st), excluding
  /// income, still-unlabeled rows, and one-off / fee payments held out of the
  /// budget — same set as [budgetedThisMonth], so the bars sum to the headline.
  /// Length = today's day-of-month. Feeds the home spending-trend chart.
  List<double> get dailySpendThisMonth {
    final now = DateTime.now();
    final days = now.day;
    final out = List<double>.filled(days, 0);
    for (final e in _expenses) {
      if (e.date.year != now.year ||
          e.date.month != now.month ||
          e.needsLabel ||
          e.isIncome ||
          !e.inBudget) {
        continue;
      }
      // Clamp guards any odd future-dated row so the sum still matches the total.
      out[(e.date.day - 1).clamp(0, days - 1)] += e.amount;
    }
    return out;
  }

  /// This month's income rows (credits), newest first — feeds the income
  /// detail sheet (grouped by source there).
  List<Expense> get incomeThisMonthEntries {
    final now = DateTime.now();
    return _expenses
        .where((e) =>
            e.date.year == now.year && e.date.month == now.month && e.isIncome)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Total spend per calendar month for the last [count] months, oldest first
  /// and the current month last. Excludes income and still-unlabeled rows (same
  /// set as [totalThisMonth]); months with no spend are included as 0 so the
  /// trend has no gaps. Feeds the Spending Trends screen.
  List<MonthSpend> monthlySpend({int count = 6}) {
    final now = DateTime.now();
    // DateTime normalizes month underflow, so `now.month - i` rolls into prior
    // years cleanly. Key each month by an absolute ordinal to bucket on.
    int key(DateTime d) => d.year * 12 + (d.month - 1);
    final months = [
      for (var i = count - 1; i >= 0; i--) DateTime(now.year, now.month - i, 1),
    ];
    final totals = {for (final m in months) key(m): 0.0};
    for (final e in _expenses) {
      // Day-to-day spend only — one-off / fee payments are tracked but kept out
      // of the trend so a single big month doesn't distort the pattern.
      if (e.needsLabel || e.isIncome || !e.inBudget) continue;
      final k = key(e.date);
      if (totals.containsKey(k)) totals[k] = totals[k]! + e.amount;
    }
    return [for (final m in months) (month: m, total: totals[key(m)]!)];
  }

  /// Day-to-day spend per category this month (one-off / fee payments excluded),
  /// for the home donut and the per-category budget bars.
  Map<String, double> get categoryTotals {
    final now = DateTime.now();
    final totals = <String, double>{};
    for (final e in _expenses.where((e) =>
        e.date.year == now.year &&
        e.date.month == now.month &&
        !e.needsLabel &&
        !e.isIncome &&
        e.inBudget)) {
      final cat = e.category ?? 'Other';
      totals[cat] = (totals[cat] ?? 0) + e.amount;
    }
    return totals;
  }

  /// Spend that counts toward the monthly budget: this month's labeled debits
  /// MINUS large one-off / fee payments held out of the budget. This — not
  /// [totalThisMonth] — is what the budget bar compares against the limit.
  double get budgetedThisMonth {
    final now = DateTime.now();
    return _expenses
        .where((e) =>
            e.date.year == now.year &&
            e.date.month == now.month &&
            !e.needsLabel &&
            !e.isIncome &&
            e.inBudget)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  // --- Budget pacing -------------------------------------------------------
  // Klaro records what you spent; these turn that into what you can spend. All
  // of them work off [budgetedThisMonth], so a college fee or other one-off
  // held out of the budget can't distort the daily allowance.

  /// Days remaining in this month, counting today. See [BudgetPacing.daysLeft].
  int get daysLeftThisMonth => BudgetPacing.daysLeft(DateTime.now());

  /// What can still be spent TODAY without breaking the monthly budget. Null
  /// when no overall budget is set; 0 once the budget is used up.
  double? get safeToSpendToday => BudgetPacing.safeToSpend(
        limit: BudgetService.instance.overall,
        spent: budgetedThisMonth,
        daysLeft: daysLeftThisMonth,
      );

  /// Where this month's day-to-day spending lands if the current pace holds.
  /// Null early in the month, when there's too little to extrapolate from.
  double? get projectedMonthEnd => BudgetPacing.projectedMonthEnd(
        limit: BudgetService.instance.overall,
        spent: budgetedThisMonth,
        today: DateTime.now(),
      );

  /// True when the current pace lands over the monthly budget — the cue to warn
  /// the user while they can still change course.
  bool get isPacingOverBudget {
    final projected = projectedMonthEnd;
    final limit = BudgetService.instance.overall;
    if (projected == null || limit == null || limit <= 0) return false;
    return projected > limit;
  }

  /// Large one-off / fee spend this month that the user excluded from the budget
  /// (already reviewed) — shown next to the budget bar so nothing is hidden.
  double get oneoffThisMonth {
    final now = DateTime.now();
    return _expenses
        .where((e) =>
            e.date.year == now.year &&
            e.date.month == now.month &&
            e.excludedFromBudget)
        .fold(0.0, (sum, e) => sum + e.amount);
  }

  /// Large/fee captures awaiting an include/exclude decision (newest first) —
  /// feeds the home "review" card. Held out of the budget until decided.
  List<Expense> get budgetReviewQueue =>
      _expenses.where((e) => e.budgetReview).toList()
        ..sort((a, b) => b.date.compareTo(a.date));

  /// This month's one-off / fee payments excluded from the budget (newest first)
  /// — feeds the "not in budget" list opened from the home one-off line.
  List<Expense> get oneoffEntriesThisMonth {
    final now = DateTime.now();
    return _expenses
        .where((e) =>
            e.date.year == now.year &&
            e.date.month == now.month &&
            e.excludedFromBudget)
        .toList()
      ..sort((a, b) => b.date.compareTo(a.date));
  }

  /// Decide a payment's budget inclusion — used by the review card and the edit
  /// sheet's "Count toward budget" switch. Updates locally at once (optimistic),
  /// clears the review flag, and PATCHes the backend (retried on failure).
  Future<void> setInBudget(Expense expense, bool include) async {
    final idx = _expenses.indexOf(expense);
    if (idx == -1) return;
    final updated = expense.copyWith(
      inBudget: include,
      budgetReview: false,
      dirty: expense.id != null,
    );
    _expenses[idx] = updated;
    await _saveLocal();
    notifyListeners();
    // Including/excluding a spend changes what counts against the budget.
    BudgetService.checkAlerts();

    if (updated.id != null) {
      final ok = await ApiService.instance.updateExpenseLabel(
        id: updated.id!,
        merchant: updated.merchant,
        category: updated.category ?? 'Other',
        inBudget: include,
        budgetReview: false,
      );
      if (ok) {
        final i = _expenses.indexWhere((x) => x.id == updated.id);
        if (i != -1) _expenses[i] = _expenses[i].copyWith(dirty: false);
        await _saveLocal();
        notifyListeners();
      } else {
        _scheduleRetry();
      }
    }
  }

  Future<void> initialize() async {
    await _loadLocal();
    await _loadPendingDeletes();

    // Load contacts first so SMS parsing can auto-label payments to known people.
    await ContactsService.instance.initialize();

    // Background-captured payments were parsed WITHOUT contacts loaded — apply
    // them now so friend payments get the contact name + Personal category.
    await _applyContacts();

    // Wire up live SMS handler — only on builds with SMS capture (the Play
    // build ships without it; see [kSmsEnabled]).
    var smsReady = false;
    if (kSmsEnabled) {
      SmsService.instance.onNewExpense = (expense) {
        _addExpense(expense);
      };

      smsReady = await SmsService.instance.initialize();

      // Pick up any SMS that arrived while neither the app nor the background
      // receiver was alive (Vivo kills it sometimes).
      if (smsReady) await _catchUpFromInbox();
    }

    // The moment the phone is back online, push anything that's waiting.
    _connSub ??= Connectivity().onConnectivityChanged.listen((results) {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (online && pendingSyncCount > 0) syncNow();
    });

    // Push any expenses captured offline / in the background (no backend id yet).
    syncNow();
  }

  @override
  void dispose() {
    _syncTimer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  /// Re-read local store from disk (e.g. on app resume, to pick up expenses the
  /// background isolate captured while the app was closed/backgrounded).
  Future<void> reloadFromDisk() async {
    _expenses.clear();
    await _loadLocal();
    await _applyContacts();
    if (kSmsEnabled) await _catchUpFromInbox();
    syncNow();
  }

  /// Wipe all locally-stored expense data — used after the user deletes their
  /// account (the backend wipe already ran). Clears the in-memory lists and the
  /// on-disk cache / sync queue / catch-up baseline so nothing of the old
  /// account survives on the device.
  Future<void> clearLocalData() async {
    _expenses.clear();
    _pendingDeletes.clear();
    _backoff.reset();
    _syncGaveUp = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_localKey);
    await prefs.remove(_deletesKey);
    await prefs.remove(_catchupKey);
    // Starting over: offer the history import again on the next sign-in.
    await prefs.remove(_historyDoneKey);
    notifyListeners();
  }

  /// Scan the inbox for SMS that arrived after the last scan and add any
  /// transactions we don't already have. Self-heals captures the OS dropped:
  /// a missed background broadcast otherwise stays invisible until the user
  /// runs a full manual import.
  Future<void> _catchUpFromInbox() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getInt(_catchupKey);
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      if (last == null) {
        // First run: start live capture from now, and flag that the inbox's
        // existing history hasn't been imported yet so the home screen can
        // offer it in one tap (rather than leaving a new user on an empty app).
        await prefs.setInt(_catchupKey, nowMs);
        if (prefs.getBool(_historyDoneKey) != true) {
          _needsHistoryImport = true;
          notifyListeners();
        }
        return;
      }

      // Small overlap so an SMS landing mid-scan isn't skipped; _isDuplicate
      // makes the overlap harmless.
      final found = await SmsService.instance.catchUpExpenses(
          sinceMs: last - const Duration(minutes: 2).inMilliseconds);
      await prefs.setInt(_catchupKey, nowMs);

      final toAdd = <Expense>[];
      for (final e in found) {
        if (!_isDuplicate(e)) {
          _expenses.insert(0, e);
          toAdd.add(e);
        }
      }
      if (toAdd.isEmpty) return;

      await _saveLocal();
      notifyListeners();
      var allOk = true;
      for (final e in toAdd) {
        if (!await _syncAndReconcile(e)) allOk = false;
      }
      if (!allOk) _scheduleRetry();
      await BudgetService.checkAlerts();
    } catch (_) {
      // Inbox unavailable (permission revoked, platform error) — not fatal.
    }
  }

  // Re-evaluate person-like payments against the user's contacts. Fixes
  // background-captured payments that show the bank/GPay name instead of the
  // contact name (e.g. "Adil Rahul Deok" -> "Adil Deokar", Personal).
  Future<void> _applyContacts() async {
    if (!ContactsService.instance.isLoaded) return;
    var changed = false;
    for (var i = 0; i < _expenses.length; i++) {
      final e = _expenses[i];
      if (e.category == 'Personal') continue;
      final m = e.merchant;
      if (m.startsWith('Card') ||
          m.startsWith('Bank ') ||
          m == 'ATM Withdrawal' ||
          m == 'Unknown') {
        continue;
      }
      final contact = ContactsService.instance.matchContactName(m);
      if (contact != null) {
        _expenses[i] =
            e.copyWith(merchant: contact, category: 'Personal', isLabeled: true);
        changed = true;
        if (e.id != null) {
          ApiService.instance.updateExpenseLabel(
              id: e.id!, merchant: contact, category: 'Personal');
        }
      }
    }
    if (changed) {
      await _saveLocal();
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Sync engine
  // ---------------------------------------------------------------------------

  /// Kick a sync right now with a fresh backoff (user tap, reconnect, resume).
  Future<void> syncNow() {
    _backoff.reset();
    _syncGaveUp = false;
    _syncTimer?.cancel();
    // Budgets ride along: re-push offline edits + pull the backend's copy.
    BudgetService.instance.refresh();
    return _runSync();
  }

  /// Schedule the next retry per backoff; flags syncFailed when exhausted.
  void _scheduleRetry() {
    if (_syncTimer?.isActive ?? false) return;
    final delay = _backoff.nextDelay();
    if (delay == null) {
      _syncGaveUp = true;
      notifyListeners();
      return;
    }
    _syncTimer = Timer(delay, _runSync);
  }

  Future<void> _runSync() async {
    if (_syncing) return;
    _syncing = true;
    var allOk = true;
    try {
      // 1) Deletes queued while offline.
      for (final id in List<int>.from(_pendingDeletes)) {
        if (await ApiService.instance.deleteExpense(id)) {
          _pendingDeletes.remove(id);
          await _savePendingDeletes();
          notifyListeners(); // clears the sync banner once the queue drains
        } else {
          allOk = false;
        }
      }

      // 2) Expenses the backend has never seen (background-captured / offline).
      for (final e in _expenses.where((e) => e.id == null).toList()) {
        if (!await _syncAndReconcile(e)) allOk = false;
      }

      // 3) Local edits to already-synced expenses that failed to PATCH.
      for (final e in _expenses.where((e) => e.dirty && e.id != null).toList()) {
        final ok = await ApiService.instance.updateExpenseLabel(
          id: e.id!,
          merchant: e.merchant,
          category: e.category ?? 'Other',
          inBudget: e.inBudget,
          budgetReview: e.budgetReview,
        );
        if (ok) {
          final idx = _expenses.indexWhere((x) => x.id == e.id);
          if (idx != -1) _expenses[idx] = _expenses[idx].copyWith(dirty: false);
          await _saveLocal();
          notifyListeners();
        } else {
          allOk = false;
        }
      }
      // 4) Pull: adopt edits/deletes made elsewhere (web dashboard) so the
      // phone reflects them too.
      await _pullReconcile();
    } finally {
      _syncing = false;
    }

    if (allOk && pendingSyncCount == 0) {
      _backoff.reset();
      if (_syncGaveUp) {
        _syncGaveUp = false;
        notifyListeners();
      }
    } else if (!allOk) {
      _scheduleRetry();
    }
  }

  /// Pull edits made OUTSIDE this app (web dashboard renames/recategorizes/
  /// deletes) into the local store. Covers the current + previous month —
  /// where edits realistically happen. Local rows that are still un-synced or
  /// carry an unsent edit (dirty) always win; a month is only reconciled when
  /// its fetch succeeded, so an unreachable backend can never wipe local data.
  Future<void> _pullReconcile() async {
    final now = DateTime.now();
    final months = [
      DateTime(now.year, now.month),
      DateTime(now.year, now.month - 1), // Dart normalizes Jan-1 → Dec prev yr
    ];

    var changed = false;
    for (final m in months) {
      final key =
          '${m.year.toString().padLeft(4, '0')}-${m.month.toString().padLeft(2, '0')}';
      final remote = await ApiService.instance.fetchExpenses(month: key);
      if (remote == null) return; // unreachable — keep local state untouched

      final byId = <int, Expense>{for (final r in remote) r.id!: r};
      for (var i = _expenses.length - 1; i >= 0; i--) {
        final e = _expenses[i];
        if (e.id == null || e.dirty) continue;
        final d = e.date.toLocal();
        if (d.year != m.year || d.month != m.month) continue;

        final r = byId[e.id];
        if (r == null) {
          // Gone from its month on the backend — deleted from the dashboard.
          _expenses.removeAt(i);
          changed = true;
        } else if (r.merchant != e.merchant ||
            (r.category != null && r.category != e.category) ||
            r.isLabeled != e.isLabeled ||
            r.inBudget != e.inBudget ||
            r.budgetReview != e.budgetReview) {
          _expenses[i] = e.copyWith(
            merchant: r.merchant,
            category: r.category,
            isLabeled: r.isLabeled,
            inBudget: r.inBudget,
            budgetReview: r.budgetReview,
          );
          changed = true;
        }
      }
    }

    if (changed) {
      await _saveLocal();
      notifyListeners();
      await BudgetService.checkAlerts();
    }
  }

  /// On a fresh sign-in with no local data yet, pull the user's full history
  /// from the backend so a new device shows everything immediately — rather than
  /// waiting on an SMS re-scan. No-op once there's local data; from then on the
  /// normal local-first sync + reconcile takes over. Adopts the backend's ids,
  /// so post-migration the phone and server agree on ids.
  Future<void> hydrateFromBackend() async {
    if (_expenses.isNotEmpty) return;
    final remote = await ApiService.instance.fetchExpenses(limit: 5000);
    if (remote == null || remote.isEmpty) return;
    _expenses
      ..clear()
      ..addAll(remote);
    await _saveLocal();
    notifyListeners();
    await BudgetService.checkAlerts();
  }

  // ---------------------------------------------------------------------------

  Future<void> importFromInbox() async {
    final expenses = await SmsService.instance.importInboxExpenses();
    await _ingestImported(expenses);
    // A manual import covers the history too — stop offering the first-run one.
    await _markHistoryDone();
  }

  /// First-run history import: pull the last [historyImportMonths] months of
  /// bank SMS from the inbox so a new install opens with real spending instead
  /// of a blank screen. The offer is cleared either way, so a user is never
  /// nagged twice.
  ///
  /// Returns `(added, found)` — `found` is how many transactions the inbox scan
  /// recognized, `added` how many were actually new. They differ when the data
  /// is already present (e.g. a returning user on a new phone who just restored
  /// from the backend), which lets the UI say "already up to date" instead of
  /// the misleading "nothing found".
  Future<({int added, int found})> importHistory() async {
    if (_importingHistory) return (added: 0, found: 0);
    _importingHistory = true;
    notifyListeners();

    var added = 0;
    var found = 0;
    try {
      final since = DateTime.now()
          .subtract(const Duration(days: historyImportMonths * 31))
          .millisecondsSinceEpoch;
      final expenses = await SmsService.instance
          .importInboxExpenses(maxMessages: 2000, sinceMs: since);
      found = expenses.length;
      added = await _ingestImported(expenses);
    } catch (_) {
      // Inbox unreadable (permission revoked / platform error) — not fatal.
    }

    _importingHistory = false;
    await _markHistoryDone();
    return (added: added, found: found);
  }

  /// The user declined the history offer — don't ask again.
  Future<void> dismissHistoryImport() => _markHistoryDone();

  Future<void> _markHistoryDone() async {
    _needsHistoryImport = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_historyDoneKey, true);
    notifyListeners();
  }

  /// Shared tail of any inbox import: dedupe, store locally first for an instant
  /// UI, then sync to the backend SEQUENTIALLY so a bulk import doesn't fire
  /// dozens of concurrent requests (which would exhaust the DB pool). The
  /// backend also dedupes (hash + amount + time window), so a re-import can
  /// never double-count server-side. Returns the number of new transactions.
  Future<int> _ingestImported(List<Expense> expenses) async {
    // A full import covers everything up to now — move the catch-up baseline.
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_catchupKey, DateTime.now().millisecondsSinceEpoch);

    final toAdd = <Expense>[];
    for (final e in expenses) {
      if (!_isDuplicate(e)) {
        _expenses.insert(0, e);
        toAdd.add(e);
      }
    }
    if (toAdd.isEmpty) return 0;

    await _saveLocal();
    notifyListeners();

    var allOk = true;
    for (final e in toAdd) {
      if (!await _syncAndReconcile(e)) allOk = false;
    }
    if (!allOk) _scheduleRetry();
    await BudgetService.checkAlerts();
    return toAdd.length;
  }

  Future<void> addExpense(Expense expense) async {
    _addExpense(expense);
  }

  /// Store an expense the backend already created (e.g. via text-import through
  /// a server-side import). It carries its server id and final category, so we just
  /// add it locally — no re-POST. Skips duplicates by id and content.
  Future<void> addBackendExpense(Expense expense) async {
    if (expense.id != null && _expenses.any((e) => e.id == expense.id)) return;
    if (_isDuplicate(expense)) return;
    _expenses.insert(0, expense);
    await _saveLocal();
    notifyListeners();
    await BudgetService.checkAlerts();
  }

  Future<void> labelExpense({
    required Expense expense,
    required String merchant,
    required String category,
    bool? inBudget,
  }) async {
    final idx = _expenses.indexOf(expense);
    if (idx == -1) return;

    // Mark dirty until the backend confirms — un-synced expenses (id == null)
    // carry the edit in their eventual POST instead.
    final updated = expense.copyWith(
      merchant: merchant,
      category: category,
      isLabeled: true,
      // When the edit sheet's budget switch was set, apply it and clear any
      // pending review in the same save; otherwise leave inclusion untouched.
      inBudget: inBudget,
      budgetReview: inBudget != null ? false : null,
      dirty: expense.id != null,
    );
    _expenses[idx] = updated;
    await _saveLocal();
    notifyListeners();

    // Labeling can move spend into a budgeted category (or make an unlabeled
    // row start counting) — re-check thresholds.
    BudgetService.checkAlerts();

    if (updated.id != null) {
      final ok = await ApiService.instance.updateExpenseLabel(
        id: updated.id!,
        merchant: merchant,
        category: category,
        inBudget: inBudget,
        budgetReview: inBudget != null ? false : null,
      );
      if (ok) {
        final i = _expenses.indexWhere((x) => x.id == updated.id);
        if (i != -1) _expenses[i] = _expenses[i].copyWith(dirty: false);
        await _saveLocal();
        notifyListeners();
      } else {
        _scheduleRetry();
      }
    }
  }

  Future<void> deleteExpense(Expense expense) async {
    _expenses.remove(expense);
    await _saveLocal();
    notifyListeners();

    // Propagate to the backend; queue the id if unreachable so the delete
    // survives restarts and re-imports can't resurrect it as a dupe.
    if (expense.id != null) {
      final ok = await ApiService.instance.deleteExpense(expense.id!);
      if (!ok) {
        _pendingDeletes.add(expense.id!);
        await _savePendingDeletes();
        _scheduleRetry();
        notifyListeners();
      }
    }
  }

  void _addExpense(Expense expense) {
    // Newest first
    _expenses.insert(0, expense);
    _saveLocal().then((_) => BudgetService.checkAlerts());
    notifyListeners();

    // Sync to backend, then reconcile: the backend assigns an id and may
    // auto-categorize unknown merchants (brand/keyword/learned/AI). Adopt that.
    _syncAndReconcile(expense).then((ok) {
      if (!ok) _scheduleRetry();
    });
  }

  /// POST one expense and adopt the backend's version. Returns success.
  Future<bool> _syncAndReconcile(Expense local) async {
    final created = await ApiService.instance.createExpense(local);
    if (created == null) return false;

    final idx = _expenses.indexOf(local);
    if (idx == -1) return true;

    // Adopt whatever the backend changed: it assigns an id, may auto-categorize
    // unknown merchants, applies any learned RENAME (your preferred name for
    // that payee), AND decides budget inclusion (large/fee captures are held out
    // and flagged for review). copyWith(field: null) keeps the local value, so we
    // only take fields the backend actually changed.
    _expenses[idx] = local.copyWith(
      id: created.id,
      merchant: created.merchant != local.merchant ? created.merchant : null,
      category: (created.category != null && created.category != local.category)
          ? created.category
          : null,
      isLabeled: created.isLabeled != local.isLabeled ? created.isLabeled : null,
      inBudget: created.inBudget != local.inBudget ? created.inBudget : null,
      budgetReview:
          created.budgetReview != local.budgetReview ? created.budgetReview : null,
    );
    await _saveLocal();
    notifyListeners();
    return true;
  }

  /// True when we already hold this transaction.
  ///
  /// Matches on the de-duplication HASH rather than the raw message, because a
  /// row restored from the backend carries no raw SMS (it never leaves the
  /// device) — comparing text would make a restored transaction look brand new
  /// and a history import would then double-count everything. The hash is
  /// computed identically on both sides, so the two forms still match exactly.
  bool _isDuplicate(Expense candidate) {
    final key = candidate.dedupeHash;
    return _expenses.any((e) =>
        e.amount == candidate.amount &&
        e.date.difference(candidate.date).abs().inMinutes < 5 &&
        // Equal hashes = same message. Both null (two manual entries with no
        // SMS) falls back to amount + time, as before. One null = different.
        e.dedupeHash == key);
  }

  Future<void> _loadLocal() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_localKey);
    if (raw == null) return;

    try {
      final list = jsonDecode(raw) as List<dynamic>;
      _expenses
          .addAll(list.map((e) => Expense.fromJson(e as Map<String, dynamic>)));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveLocal() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _localKey,
      jsonEncode(_expenses.map((e) => e.toJson()).toList()),
    );
  }

  Future<void> _loadPendingDeletes() async {
    final prefs = await SharedPreferences.getInstance();
    _pendingDeletes
      ..clear()
      ..addAll(
          (prefs.getStringList(_deletesKey) ?? []).map(int.parse));
  }

  Future<void> _savePendingDeletes() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        _deletesKey, _pendingDeletes.map((e) => e.toString()).toList());
  }
}
