// Budget pacing maths: "what can I spend today" and "where is this month
// heading". These drive a number the user acts on, so the edge cases —
// month boundaries, an exhausted budget, a month too young to extrapolate —
// are pinned down here rather than discovered on someone's phone.
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/services/budget_pacing.dart';

void main() {
  group('daysLeft', () {
    test('counts today, so the last day of the month is 1 (never 0)', () {
      // Dividing by 0 on the 31st would produce Infinity on screen.
      expect(BudgetPacing.daysLeft(DateTime(2026, 7, 31)), 1);
      expect(BudgetPacing.daysLeft(DateTime(2026, 6, 30)), 1);
    });

    test('first of the month = the whole month', () {
      expect(BudgetPacing.daysLeft(DateTime(2026, 7, 1)), 31); // July
      expect(BudgetPacing.daysLeft(DateTime(2026, 6, 1)), 30); // June
      expect(BudgetPacing.daysLeft(DateTime(2026, 2, 1)), 28); // Feb, non-leap
    });

    test('handles a leap February', () {
      expect(BudgetPacing.daysLeft(DateTime(2028, 2, 1)), 29);
      expect(BudgetPacing.daysLeft(DateTime(2028, 2, 29)), 1);
    });

    test('mid-month', () {
      expect(BudgetPacing.daysLeft(DateTime(2026, 7, 18)), 14); // 31-18+1
    });

    test('December rolls into the next year without breaking', () {
      expect(BudgetPacing.daysLeft(DateTime(2026, 12, 25)), 7);
    });
  });

  group('safeToSpend', () {
    test('spreads what is left over the days that remain', () {
      // ₹10,000 left, 10 days to go -> ₹1,000 a day.
      final r = BudgetPacing.safeToSpend(
          limit: 20000, spent: 10000, daysLeft: 10);
      expect(r, 1000);
    });

    test('falls as today is spent (it is a live "right now" figure)', () {
      final before =
          BudgetPacing.safeToSpend(limit: 20000, spent: 10000, daysLeft: 10)!;
      final after =
          BudgetPacing.safeToSpend(limit: 20000, spent: 10500, daysLeft: 10)!;
      expect(after, lessThan(before));
    });

    test('is 0 — not negative — once the budget is used up', () {
      // A negative "safe to spend" would be nonsense on screen.
      expect(BudgetPacing.safeToSpend(limit: 20000, spent: 25000, daysLeft: 5), 0);
      expect(BudgetPacing.safeToSpend(limit: 20000, spent: 20000, daysLeft: 5), 0);
    });

    test('is null with no budget set — show nothing rather than invent one', () {
      expect(BudgetPacing.safeToSpend(limit: null, spent: 500, daysLeft: 10),
          isNull);
      expect(
          BudgetPacing.safeToSpend(limit: 0, spent: 500, daysLeft: 10), isNull);
    });

    test('the whole budget is available on day one', () {
      // 30-day month, nothing spent: exactly one day's share.
      expect(BudgetPacing.safeToSpend(limit: 30000, spent: 0, daysLeft: 30),
          1000);
    });
  });

  group('projectedMonthEnd', () {
    test('extrapolates the current pace across the full month', () {
      // ₹5,000 over 10 days of a 30-day month -> ₹15,000.
      final r = BudgetPacing.projectedMonthEnd(
          limit: 20000, spent: 5000, today: DateTime(2026, 6, 10));
      expect(r, 15000);
    });

    test('stays silent for the first two days rather than crying wolf', () {
      // One ₹800 coffee on the 1st would otherwise "project" to ₹24,000.
      for (final day in [1, 2]) {
        expect(
          BudgetPacing.projectedMonthEnd(
              limit: 20000, spent: 800, today: DateTime(2026, 6, day)),
          isNull,
          reason: 'day $day is too early to extrapolate',
        );
      }
      expect(
        BudgetPacing.projectedMonthEnd(
            limit: 20000, spent: 800, today: DateTime(2026, 6, 3)),
        isNotNull,
        reason: 'day 3 is the first projection',
      );
    });

    test('is null with no budget set', () {
      expect(
          BudgetPacing.projectedMonthEnd(
              limit: null, spent: 5000, today: DateTime(2026, 6, 10)),
          isNull);
    });

    test('on the last day the projection equals what was actually spent', () {
      final r = BudgetPacing.projectedMonthEnd(
          limit: 20000, spent: 18000, today: DateTime(2026, 6, 30));
      expect(r, 18000);
    });

    test('an over-budget pace is detectable before the month ends', () {
      // ₹12,000 by the 10th of a 30-day month projects to ₹36,000 — well over
      // a ₹20,000 budget, and flagged with 20 days still left to correct it.
      final r = BudgetPacing.projectedMonthEnd(
          limit: 20000, spent: 12000, today: DateTime(2026, 6, 10))!;
      expect(r, 36000);
      expect(r > 20000, isTrue);
    });
  });
}
