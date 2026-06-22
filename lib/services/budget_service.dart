import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/expense.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'sms_service.dart' show kLocalExpensesKey;

/// Monthly spending limits, keyed by category name or [overallKey] for the
/// whole month. The backend is the source of truth; a SharedPreferences cache
/// keeps budgets usable offline AND readable from the background SMS isolate
/// so threshold alerts fire even when the app is closed.
class BudgetService extends ChangeNotifier {
  static final BudgetService instance = BudgetService._();
  BudgetService._();

  static const overallKey = 'overall';
  static const _cacheKey = 'budgets_cache';
  static const _dirtyKey = 'budgets_dirty';
  static const _alertsKeyPrefix = 'budget_alerts_'; // + YYYY-MM

  /// Notify at these % of a budget — once per level per month.
  static const warnPct = 80;

  Map<String, double> _budgets = {};
  Map<String, double> get budgets => Map.unmodifiable(_budgets);
  double? get overall => _budgets[overallKey];
  double? limitFor(String category) => _budgets[category];

  /// Load the cached budgets immediately (instant UI), then refresh from the
  /// backend in the background.
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _budgets = _decode(prefs.getString(_cacheKey));
    notifyListeners();
    refresh(); // unawaited — backend wins when reachable
  }

  /// Re-push edits made while offline, then pull the backend's copy.
  Future<void> refresh() async {
    final prefs = await SharedPreferences.getInstance();
    final dirty = prefs.getStringList(_dirtyKey) ?? <String>[];
    for (final category in List<String>.from(dirty)) {
      final amount = _budgets[category];
      final ok = amount == null
          ? await ApiService.instance.deleteBudget(category)
          : await ApiService.instance.putBudget(category, amount);
      if (ok) dirty.remove(category);
    }
    await prefs.setStringList(_dirtyKey, dirty);

    final remote = await ApiService.instance.fetchBudgets();
    if (remote == null) return; // unreachable — keep the cache

    // Local edits still waiting to sync beat the (stale) server copy.
    for (final category in dirty) {
      final local = _budgets[category];
      if (local != null) {
        remote[category] = local;
      } else {
        remote.remove(category); // pending offline delete
      }
    }
    _budgets = remote;
    await _saveCache(prefs);
    notifyListeners();
    // Budgets may have been added/lowered from another device — re-evaluate.
    if (_budgets.isNotEmpty) await checkAlerts();
  }

  Future<void> setBudget(String category, double amount) async {
    _budgets[category] = amount;
    final prefs = await SharedPreferences.getInstance();
    await _saveCache(prefs);
    notifyListeners();
    if (!await ApiService.instance.putBudget(category, amount)) {
      await _markDirty(prefs, category);
    }
    // A freshly set budget may already be past a threshold — say so now.
    await checkAlerts();
  }

  Future<void> removeBudget(String category) async {
    _budgets.remove(category);
    final prefs = await SharedPreferences.getInstance();
    await _saveCache(prefs);
    notifyListeners();
    if (!await ApiService.instance.deleteBudget(category)) {
      await _markDirty(prefs, category);
    }
  }

  // ---------------------------------------------------------------------------
  // Threshold alerts
  // ---------------------------------------------------------------------------

  /// Check every budget against this month's spend and notify when one crosses
  /// 80% (nearing) or 100% (exceeded) — once per level per month. Static and
  /// prefs-only so the background SMS isolate can run it right after storing a
  /// new expense, with the app closed.
  static Future<void> checkAlerts() async {
    final prefs = await SharedPreferences.getInstance();
    final budgets = _decode(prefs.getString(_cacheKey));
    if (budgets.isEmpty) return;

    final raw = prefs.getString(kLocalExpensesKey);
    if (raw == null) return;

    // This month's spend per category (same rule as the home screen total:
    // unlabeled rows don't count until they're resolved).
    final now = DateTime.now();
    var overallSpent = 0.0;
    final totals = <String, double>{};
    try {
      for (final j in jsonDecode(raw) as List<dynamic>) {
        final e = Expense.fromJson(j as Map<String, dynamic>);
        if (e.date.year != now.year || e.date.month != now.month) continue;
        if (e.needsLabel) continue;
        if (e.isIncome) continue; // budgets cap spending, not income
        overallSpent += e.amount;
        final cat = e.category ?? 'Other';
        totals[cat] = (totals[cat] ?? 0) + e.amount;
      }
    } catch (_) {
      return;
    }

    final monthKey =
        '$_alertsKeyPrefix${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
    // Old months' alert state is garbage now — drop it.
    for (final k in prefs.getKeys().toList()) {
      if (k.startsWith(_alertsKeyPrefix) && k != monthKey) {
        await prefs.remove(k);
      }
    }

    Map<String, dynamic> fired = {};
    try {
      fired = jsonDecode(prefs.getString(monthKey) ?? '{}') as Map<String, dynamic>;
    } catch (_) {}

    var changed = false;
    for (final entry in budgets.entries) {
      final limit = entry.value;
      if (limit <= 0) continue;
      final spent =
          entry.key == overallKey ? overallSpent : (totals[entry.key] ?? 0.0);
      final pct = spent / limit * 100;
      final level = pct >= 100 ? 100 : (pct >= warnPct ? warnPct : 0);
      final last = (fired[entry.key] as num?)?.toInt() ?? 0;
      if (level > last) {
        fired[entry.key] = level;
        changed = true;
        await NotificationService.instance.showBudgetAlert(
          label: entry.key == overallKey ? 'Monthly' : entry.key,
          spent: spent,
          limit: limit,
          exceeded: level == 100,
        );
      }
    }
    if (changed) await prefs.setString(monthKey, jsonEncode(fired));
  }

  // ---------------------------------------------------------------------------

  static Map<String, double> _decode(String? raw) {
    if (raw == null) return {};
    try {
      return (jsonDecode(raw) as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  Future<void> _saveCache(SharedPreferences prefs) =>
      prefs.setString(_cacheKey, jsonEncode(_budgets));

  Future<void> _markDirty(SharedPreferences prefs, String category) async {
    final dirty = prefs.getStringList(_dirtyKey) ?? <String>[];
    if (!dirty.contains(category)) {
      dirty.add(category);
      await prefs.setStringList(_dirtyKey, dirty);
    }
  }
}
