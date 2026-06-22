import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._();
  NotificationService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  static const _txnChannelId = 'expense_tracker_txn';
  static const _txnChannelName = 'New transactions';

  static const _labelChannelId = 'expense_tracker_unknown';
  static const _labelChannelName = 'Needs labelling';

  static const _budgetChannelId = 'klaro_budget';
  static const _budgetChannelName = 'Budget alerts';

  /// Safe to call from the background isolate too (idempotent).
  Future<void> initialize() async {
    if (_initialized) return;
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const settings = InitializationSettings(android: android);
    await _plugin.initialize(settings);
    _initialized = true;
  }

  /// A new spend was captured — show it instantly (the "auto-appear" alert).
  Future<void> showTransaction({
    required String merchant,
    required double amount,
    required String category,
    bool needsLabel = false,
  }) async {
    await initialize();
    final amountStr = '₹${amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2)}';
    final title = '$amountStr · $merchant';
    final body = needsLabel ? 'Tap to label this expense' : 'Added to $category';
    await _plugin.show(
      // Unique-ish id per merchant+amount so distinct txns stack.
      (merchant + amountStr).hashCode.abs() % 100000,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          needsLabel ? _labelChannelId : _txnChannelId,
          needsLabel ? _labelChannelName : _txnChannelName,
          channelDescription: 'Alerts when a new expense is detected from SMS',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }

  /// A budget crossed a threshold (80% nearing / 100% exceeded). Fired at most
  /// once per level per month — see BudgetService.checkAlerts.
  Future<void> showBudgetAlert({
    required String label,
    required double spent,
    required double limit,
    required bool exceeded,
  }) async {
    await initialize();
    String fmt(double v) => '₹${v.toStringAsFixed(v % 1 == 0 ? 0 : 2)}';
    final pct = (spent / limit * 100).round();
    final title = exceeded
        ? '$label budget exceeded'
        : '$label budget at $pct%';
    final body = '${fmt(spent)} of ${fmt(limit)} spent this month';
    await _plugin.show(
      ('budget$label$exceeded').hashCode.abs() % 100000,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _budgetChannelId,
          _budgetChannelName,
          channelDescription: 'Alerts when a monthly budget is nearly or fully used',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
      ),
    );
  }
}
