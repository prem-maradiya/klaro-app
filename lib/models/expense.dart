import 'dart:convert';
import 'package:crypto/crypto.dart';

class Expense {
  final int? id;
  final String merchant;
  final double amount;
  final DateTime date;
  final String rawSms;
  final String? upiId;
  final bool isLabeled;
  final String? category;

  /// How the payment was made: 'upi' (default) or 'card'.
  final String method;

  /// Money direction: 'debit' (a spend, the default) or 'credit' (income —
  /// salary, refunds, transfers received). Income is excluded from spending
  /// totals and budgets, and shown in the net-flow view.
  final String direction;

  /// True when a local edit (label/rename) hasn't reached the backend yet —
  /// retried by the sync engine. Only meaningful for expenses with an id;
  /// un-synced expenses (id == null) carry their edits in the eventual POST.
  final bool dirty;

  /// Whether this spend counts toward the monthly budget. Small day-to-day
  /// spends do (the default); a large one-off / fee payment is held out until
  /// the user decides. Never relevant for income (credits).
  final bool inBudget;

  /// A large/fee-like capture held out of the budget and awaiting the user's
  /// include/exclude decision (shown in the home review card).
  final bool budgetReview;

  const Expense({
    this.id,
    required this.merchant,
    required this.amount,
    required this.date,
    required this.rawSms,
    this.upiId,
    this.isLabeled = true,
    this.category,
    this.method = 'upi',
    this.direction = 'debit',
    this.dirty = false,
    this.inBudget = true,
    this.budgetReview = false,
  });

  bool get needsLabel => !isLabeled;
  bool get isCard => method == 'card';
  bool get isIncome => direction == 'credit';

  /// A spend the user excluded from the budget (and already reviewed) — shown
  /// with a "not in budget" tag in the transaction list.
  bool get excludedFromBudget => direction == 'debit' && !inBudget && !budgetReview;

  /// Synced means the backend has this expense AND all local edits to it.
  bool get isSynced => id != null && !dirty;

  /// One-way SHA-256 of the raw SMS with whitespace removed. Sent to the backend
  /// purely as a dedupe token for re-imports/retries — it is NOT reversible to
  /// the message, so the raw SMS itself never leaves the device. Matches the
  /// server's hashing (whitespace-stripped, utf-8, hex) so dedupe stays stable.
  /// Null for entries with no SMS (manual adds), which simply skip dedupe.
  String? get syncHash {
    final stripped = rawSms.replaceAll(RegExp(r'\s+'), '');
    if (stripped.isEmpty) return null;
    return sha256.convert(utf8.encode(stripped)).toString();
  }

  Expense copyWith({
    int? id,
    String? merchant,
    String? category,
    bool? isLabeled,
    String? method,
    String? direction,
    bool? dirty,
    bool? inBudget,
    bool? budgetReview,
  }) {
    return Expense(
      id: id ?? this.id,
      merchant: merchant ?? this.merchant,
      amount: amount,
      date: date,
      rawSms: rawSms,
      upiId: upiId,
      isLabeled: isLabeled ?? this.isLabeled,
      category: category ?? this.category,
      method: method ?? this.method,
      direction: direction ?? this.direction,
      dirty: dirty ?? this.dirty,
      inBudget: inBudget ?? this.inBudget,
      budgetReview: budgetReview ?? this.budgetReview,
    );
  }

  Map<String, dynamic> toJson() => {
        // 'id' is persisted locally so backend ids survive app restarts (needed
        // to PATCH edits). The backend ignores it on create (autoincrements).
        if (id != null) 'id': id,
        'merchant': merchant,
        'amount': amount,
        'date': date.toIso8601String(),
        'raw_sms': rawSms,
        'upi_id': upiId,
        'is_labeled': isLabeled,
        'category': category,
        'method': method,
        'direction': direction,
        'in_budget': inBudget,
        'budget_review': budgetReview,
        // Local-only sync state; the backend ignores unknown fields.
        'dirty': dirty,
      };

  /// Cleaned payload uploaded to the backend / web dashboard. Privacy boundary:
  /// this DELIBERATELY omits `raw_sms` and `upi_id` — the raw bank message,
  /// account numbers, payer names and balances NEVER leave the device. Only the
  /// curated transaction (merchant, amount, category, date + derived flags) and a
  /// one-way [syncHash] for dedupe are sent.
  ///
  /// `source` is sent explicitly because the server used to infer it from the
  /// presence of `raw_sms` — which we no longer upload.
  Map<String, dynamic> toSyncJson() => {
        if (id != null) 'id': id,
        'merchant': merchant,
        'amount': amount,
        'date': date.toIso8601String(),
        'is_labeled': isLabeled,
        'category': category,
        'method': method,
        'direction': direction,
        'in_budget': inBudget,
        'budget_review': budgetReview,
        'source': rawSms.trim().isNotEmpty ? 'sms' : 'manual',
        if (syncHash != null) 'raw_sms_hash': syncHash,
        'dirty': dirty,
      };

  factory Expense.fromJson(Map<String, dynamic> json) => Expense(
        id: json['id'],
        merchant: json['merchant'],
        amount: (json['amount'] as num).toDouble(),
        date: DateTime.parse(json['date']),
        rawSms: json['raw_sms'] ?? '',
        upiId: json['upi_id'],
        isLabeled: json['is_labeled'] ?? true,
        category: json['category'],
        method: json['method'] ?? 'upi',
        direction: json['direction'] ?? 'debit',
        dirty: json['dirty'] ?? false,
        inBudget: json['in_budget'] ?? true,
        budgetReview: json['budget_review'] ?? false,
      );
}
