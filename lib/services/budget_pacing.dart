/// Pure budget-pacing maths.
///
/// Deliberately free of `DateTime.now()` and of any stored settings: every input
/// is passed in. That keeps the formulas — which carry the fiddly edge cases
/// (last day of the month, an exhausted budget, too little of the month to
/// extrapolate) — directly testable, while [ExpenseProvider] stays responsible
/// for supplying today's real values.
class BudgetPacing {
  const BudgetPacing._();

  /// Days remaining in [today]'s month, counting today itself.
  ///
  /// Counting today matters: on the last day of the month the answer is 1, not
  /// 0, so [safeToSpend] divides by a sane number instead of blowing up.
  static int daysLeft(DateTime today) {
    // Day 0 of next month == last day of this month (Dart normalizes it).
    final lastDay = DateTime(today.year, today.month + 1, 0).day;
    return lastDay - today.day + 1;
  }

  /// Total days in [today]'s month.
  static int daysInMonth(DateTime today) =>
      DateTime(today.year, today.month + 1, 0).day;

  /// What can still be spent today without breaking the monthly budget: what's
  /// left, spread evenly across the days that remain.
  ///
  /// [spent] already includes anything spent today, so the figure falls through
  /// the day — the behaviour you want from "what can I spend right now?".
  /// Returns null when there's no budget to divide, and 0 once it's used up.
  static double? safeToSpend({
    required double? limit,
    required double spent,
    required int daysLeft,
  }) {
    if (limit == null || limit <= 0) return null;
    if (daysLeft <= 0) return null; // defensive; daysLeft is never < 1
    final remaining = limit - spent;
    if (remaining <= 0) return 0;
    return remaining / daysLeft;
  }

  /// Where the month lands if the current pace holds.
  ///
  /// Null for the first two days: a single coffee on the 1st would extrapolate
  /// to an alarming month, and a number that cries wolf gets ignored.
  static const int minDayForProjection = 3;

  static double? projectedMonthEnd({
    required double? limit,
    required double spent,
    required DateTime today,
  }) {
    if (limit == null || limit <= 0) return null;
    if (today.day < minDayForProjection) return null;
    return spent / today.day * daysInMonth(today);
  }
}
