/// A detected recurring payment (subscription / EMI / regular bill) returned by
/// the backend `/recurring` detector, with its predicted next due date.
class RecurringPayment {
  final String merchant;
  final double amount;
  final String? category;
  final String cadence; // "Weekly" | "Monthly" | "Yearly" | …
  final int occurrences; // how many past charges backed the detection
  final DateTime? lastPaid;
  final DateTime? nextDue;
  final String source; // "amount" | "brand" | "keyword"

  const RecurringPayment({
    required this.merchant,
    required this.amount,
    required this.category,
    required this.cadence,
    required this.occurrences,
    required this.lastPaid,
    required this.nextDue,
    required this.source,
  });

  factory RecurringPayment.fromJson(Map<String, dynamic> j) => RecurringPayment(
        merchant: (j['merchant'] ?? '') as String,
        amount: (j['amount'] as num?)?.toDouble() ?? 0,
        category: j['category'] as String?,
        cadence: (j['cadence'] ?? '') as String,
        occurrences: (j['occurrences'] as num?)?.toInt() ?? 0,
        lastPaid: _date(j['last_paid']),
        nextDue: _date(j['next_due']),
        source: (j['source'] ?? '') as String,
      );

  static DateTime? _date(dynamic v) =>
      (v is String && v.isNotEmpty) ? DateTime.tryParse(v) : null;
}

/// The full `/recurring` payload: detected items + their monthly-equivalent total.
class RecurringSummary {
  final List<RecurringPayment> items;
  final double monthlyTotal;

  const RecurringSummary({required this.items, required this.monthlyTotal});

  factory RecurringSummary.fromJson(Map<String, dynamic> j) => RecurringSummary(
        items: ((j['recurring'] as List<dynamic>?) ?? const [])
            .map((e) => RecurringPayment.fromJson(e as Map<String, dynamic>))
            .toList(),
        monthlyTotal: (j['monthly_total'] as num?)?.toDouble() ?? 0,
      );
}
