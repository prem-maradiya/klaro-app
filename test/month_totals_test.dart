// What the home screen calls "spent" — and what it therefore says is safe to
// spend. Regression guard for a real bug seen on a phone (2026-08-05): the app
// showed "Spent in August ₹0.00" and "Safe to spend ₹741" while a genuine
// ₹218.82 payment sat unlabeled in the list, because every total filtered out
// rows Klaro hadn't categorized yet. An uncategorized spend is still a spend;
// hiding it told the user they had more money left than they did.
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/providers/expense_provider.dart';

void main() {
  final now = DateTime.now();

  // Dated inside the current month (the getters are all "this month"), and away
  // from midnight so a timezone wobble can't push it into a neighbouring month.
  DateTime thisMonth(int day) =>
      DateTime(now.year, now.month, day.clamp(1, now.day), 12);

  Expense spend({
    required double amount,
    String merchant = 'Shop',
    String? category = 'Food',
    bool labeled = true,
    bool inBudget = true,
    bool review = false,
    int? day,
  }) =>
      Expense(
        merchant: merchant,
        amount: amount,
        date: thisMonth(day ?? now.day),
        rawSms: '$merchant $amount',
        isLabeled: labeled,
        category: labeled ? category : null,
        inBudget: inBudget,
        budgetReview: review,
      );

  group('unlabeled spend counts as spending', () {
    test('a single unlabeled payment is NOT invisible', () {
      // The exact shape of the bug: one real payment, never categorized.
      final p = ExpenseProvider.withExpenses([
        spend(amount: 218.82, merchant: 'HARDCASTLE', labeled: false),
      ]);
      expect(p.budgetedThisMonth, 218.82,
          reason: 'headline + budget bar must include it');
      expect(p.totalThisMonth, 218.82);
    });

    test('labeled and unlabeled are added together', () {
      final p = ExpenseProvider.withExpenses([
        spend(amount: 300),
        spend(amount: 218.82, labeled: false),
      ]);
      expect(p.budgetedThisMonth, closeTo(518.82, 0.001));
    });

    test('unlabeled spend appears as its own donut slice, not as "Other"', () {
      // "Other" is a category the user can genuinely pick, so lumping unknown
      // spend in there would hide the fact that something needs labeling.
      final p = ExpenseProvider.withExpenses([
        spend(amount: 100, category: 'Other'),
        spend(amount: 218.82, labeled: false),
      ]);
      expect(p.categoryTotals[ExpenseProvider.uncategorized], 218.82);
      expect(p.categoryTotals['Other'], 100);
    });
  });

  group('the numbers on screen reconcile with each other', () {
    // If these drift apart the user sees a headline that disagrees with the
    // chart under it — which reads as the app being broken.
    final p = ExpenseProvider.withExpenses([
      spend(amount: 300, day: 1),
      spend(amount: 218.82, labeled: false, day: 1),
      spend(amount: 150, category: 'Grocery'),
    ]);

    test('category slices sum to the budget headline', () {
      final slices = p.categoryTotals.values.fold(0.0, (a, b) => a + b);
      expect(slices, closeTo(p.budgetedThisMonth, 0.001));
    });

    test('daily bars sum to the budget headline', () {
      final bars = p.dailySpendThisMonth.fold(0.0, (a, b) => a + b);
      expect(bars, closeTo(p.budgetedThisMonth, 0.001));
    });
  });

  group('what still must NOT count', () {
    test('income is never spending, labeled or not', () {
      final p = ExpenseProvider.withExpenses([
        spend(amount: 100),
        Expense(
          merchant: 'Salary',
          amount: 50000,
          date: thisMonth(1),
          rawSms: 'credited',
          direction: 'credit',
          category: 'Income',
        ),
      ]);
      expect(p.budgetedThisMonth, 100);
      expect(p.totalThisMonth, 100);
      expect(p.incomeThisMonth, 50000);
    });

    test('a one-off held out of the budget stays out of the budget total', () {
      // The college-fee case: tracked and in the grand total, but it must not
      // eat the day-to-day allowance.
      final p = ExpenseProvider.withExpenses([
        spend(amount: 500),
        spend(amount: 78500, merchant: 'MIT University', inBudget: false),
      ]);
      expect(p.budgetedThisMonth, 500, reason: 'day-to-day only');
      expect(p.totalThisMonth, 79000, reason: 'grand total keeps it');
      expect(p.oneoffThisMonth, 78500);
    });

    test('an unlabeled one-off is still held out of the budget', () {
      // Unlabeled must not become a backdoor into the budget for big payments.
      final p = ExpenseProvider.withExpenses([
        spend(amount: 30000, labeled: false, inBudget: false, review: true),
      ]);
      expect(p.budgetedThisMonth, 0);
      expect(p.totalThisMonth, 30000);
    });
  });
}
