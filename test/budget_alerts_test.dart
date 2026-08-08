// Budget threshold alerts: when they fire, how often, and what they count.
//
// This logic runs from the background SMS isolate with the app closed, so a bug
// here is invisible — an alert that never fires looks exactly like "I haven't
// overspent". Until now it called the notification plugin directly and no test
// could reach it.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/services/budget_service.dart';
import 'package:expense_tracker/services/sms_service.dart' show kLocalExpensesKey;

/// Records alerts instead of showing them.
class RecordedAlert {
  RecordedAlert(this.label, this.spent, this.limit, this.exceeded);
  final String label;
  final double spent;
  final double limit;
  final bool exceeded;
  @override
  String toString() => '$label ${exceeded ? "exceeded" : "warn"} $spent/$limit';
}

void main() {
  late List<RecordedAlert> fired;

  /// Seed storage the way the app writes it: cached budgets + local expenses.
  void seed({
    required Map<String, double> budgets,
    required List<Expense> expenses,
    Map<String, Object> extra = const {},
  }) {
    SharedPreferences.setMockInitialValues({
      'budgets_cache': jsonEncode(budgets),
      kLocalExpensesKey: jsonEncode([for (final e in expenses) e.toJson()]),
      ...extra,
    });
  }

  Expense spend(double amount, {String category = 'Food', bool labeled = true,
      bool inBudget = true, bool income = false}) {
    final now = DateTime.now();
    return Expense(
      merchant: 'Shop',
      amount: amount,
      // Mid-month, midday: safe from month-boundary and timezone edges.
      date: DateTime(now.year, now.month, now.day, 12),
      rawSms: 'debited $amount',
      isLabeled: labeled,
      category: labeled ? category : null,
      inBudget: inBudget,
      direction: income ? 'credit' : 'debit',
    );
  }

  setUp(() {
    fired = [];
    BudgetService.notifier = ({
      required String label,
      required double spent,
      required double limit,
      required bool exceeded,
    }) async =>
        fired.add(RecordedAlert(label, spent, limit, exceeded));
  });

  group('when an alert fires', () {
    test('stays quiet below the warning threshold', () async {
      seed(budgets: {'overall': 1000}, expenses: [spend(500)]); // 50%
      await BudgetService.checkAlerts();
      expect(fired, isEmpty);
    });

    test('warns once the budget is nearly used', () async {
      seed(budgets: {'overall': 1000}, expenses: [spend(850)]); // 85%
      await BudgetService.checkAlerts();
      expect(fired.length, 1);
      expect(fired.single.exceeded, isFalse);
    });

    test('escalates to exceeded past the limit', () async {
      seed(budgets: {'overall': 1000}, expenses: [spend(1200)]);
      await BudgetService.checkAlerts();
      expect(fired.single.exceeded, isTrue);
    });
  });

  group('how often it fires', () {
    test('does not repeat the same level', () async {
      // Otherwise every captured SMS would re-alert — the fastest way to make a
      // user silence Klaro's notifications for good.
      seed(budgets: {'overall': 1000}, expenses: [spend(850)]);
      await BudgetService.checkAlerts();
      await BudgetService.checkAlerts();
      await BudgetService.checkAlerts();
      expect(fired.length, 1);
    });

    test('still escalates from warning to exceeded', () async {
      // Warning already sent this month; spending has since passed the limit.
      // Suppressing repeats must not suppress an ESCALATION — going over budget
      // is new information and has to be said.
      final now = DateTime.now();
      final monthKey =
          'budget_alerts_${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}';
      seed(
        budgets: {'overall': 1000},
        expenses: [spend(850), spend(300)], // 115%
        extra: {monthKey: jsonEncode({'overall': BudgetService.warnPct})},
      );

      await BudgetService.checkAlerts();
      expect(fired.length, 1);
      expect(fired.single.exceeded, isTrue);
    });

    test('a new month starts the alerts fresh', () async {
      // Last month's "already warned" state must not silence this month.
      seed(
        budgets: {'overall': 1000},
        expenses: [spend(1200)],
        extra: {'budget_alerts_2020-01': jsonEncode({'overall': 100})},
      );

      await BudgetService.checkAlerts();
      expect(fired.length, 1, reason: 'stale month state must not carry over');
    });
  });

  group('what counts toward the alert', () {
    test('unlabeled spend counts — the alert must match the home screen',
        () async {
      // The screen totals include uncategorized spend. If alerts used a smaller
      // figure, a budget could read "over" on screen while no warning ever came.
      seed(budgets: {'overall': 1000}, expenses: [spend(1200, labeled: false)]);
      await BudgetService.checkAlerts();
      expect(fired.single.exceeded, isTrue,
          reason: 'uncategorized money is still money spent');
      expect(fired.single.spent, 1200);
    });

    test('income never triggers a spending alert', () async {
      seed(budgets: {'overall': 1000}, expenses: [spend(50000, income: true)]);
      await BudgetService.checkAlerts();
      expect(fired, isEmpty);
    });

    test('a one-off held out of the budget does not trigger it', () async {
      // The college-fee case: tracked, but it must not set off the alarm.
      seed(budgets: {'overall': 1000}, expenses: [spend(78500, inBudget: false)]);
      await BudgetService.checkAlerts();
      expect(fired, isEmpty);
    });

    test('per-category budgets alert independently of the overall one', () async {
      seed(
        budgets: {'overall': 100000, 'Food': 1000},
        expenses: [spend(1500, category: 'Food')],
      );
      await BudgetService.checkAlerts();
      expect(fired.length, 1);
      expect(fired.single.label, 'Food');
    });
  });

  group('edge cases', () {
    test('no budgets set means nothing to alert about', () async {
      seed(budgets: {}, expenses: [spend(9999)]);
      await BudgetService.checkAlerts();
      expect(fired, isEmpty);
    });

    test('a zero limit is ignored rather than dividing by zero', () async {
      seed(budgets: {'overall': 0}, expenses: [spend(500)]);
      await BudgetService.checkAlerts();
      expect(fired, isEmpty);
    });
  });
}
