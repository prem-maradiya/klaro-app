/// The ONLY file in Klaro that talks to `another_telephony`.
///
/// Everything else depends on the plugin-free [SmsSource] contract, so swapping
/// or upgrading the SMS plugin is a change here and nowhere else. It also keeps
/// the untestable surface small and reviewable: if a bug can only be caught on a
/// real phone, it has to live in this file.
library;

import 'dart:convert';
import 'dart:ui';

import 'package:another_telephony/telephony.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'budget_service.dart';
import 'notification_service.dart';
import 'sms_service.dart';
import 'sms_source.dart';

/// Adapts the plugin to Klaro's [SmsSource] contract.
class TelephonySmsSource implements SmsSource {
  TelephonySmsSource();

  final Telephony _telephony = Telephony.instance;

  static const _columns = [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE];

  // Newest-first, always. The contract promises it and the limit depends on it:
  // `limit` is there to bound parse time, so it must drop the OLDEST messages.
  // Leaving this off once meant a 13k-message inbox returned in the platform's
  // own order and the user's recent payments were never read.
  static final _newestFirst = [OrderBy(SmsColumn.DATE, sort: Sort.DESC)];

  static InboxMessage _toInbox(SmsMessage m) => InboxMessage(
        sender: m.address ?? '',
        body: m.body ?? '',
        date: m.date != null
            ? DateTime.fromMillisecondsSinceEpoch(m.date!)
            : DateTime.now(),
      );

  @override
  Future<bool> requestPermission() async =>
      await _telephony.requestSmsPermissions ?? false;

  @override
  void listenIncoming(void Function(InboxMessage) onMessage) {
    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage m) => onMessage(_toInbox(m)),
      onBackgroundMessage: backgroundSmsHandler,
      listenInBackground: true,
    );
  }

  @override
  Future<List<InboxMessage>> readInbox({DateTime? since, int limit = 2000}) async {
    final messages = since == null
        ? await _telephony.getInboxSms(
            columns: _columns,
            sortOrder: _newestFirst,
          )
        : await _telephony.getInboxSms(
            columns: _columns,
            filter: SmsFilter.where(SmsColumn.DATE)
                .greaterThan(since.millisecondsSinceEpoch.toString()),
            sortOrder: _newestFirst,
          );
    return messages.take(limit).map(_toInbox).toList();
  }
}

// ---------------------------------------------------------------------------
// Background capture
// ---------------------------------------------------------------------------

/// Runs in a SEPARATE isolate when an SMS arrives while the app is closed or
/// backgrounded: parses it, stores it locally so it's there on next launch, and
/// notifies so the spend "appears" instantly.
///
/// Lives here because the plugin dictates its signature (a top-level
/// `vm:entry-point` taking the plugin's own message type), which is exactly the
/// kind of coupling this file exists to contain.
@pragma('vm:entry-point')
void backgroundSmsHandler(SmsMessage message) async {
  // Register plugins in this background isolate (SharedPreferences, notifications).
  DartPluginRegistrant.ensureInitialized();

  final msg = TelephonySmsSource._toInbox(message);

  // Contacts aren't loaded in the background isolate, so payee->Personal won't
  // apply here; the app re-evaluates on next open.
  final expense = SmsService.parseExpense(
      body: msg.body, sender: msg.sender, date: msg.date);
  if (expense == null) return;

  try {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(kLocalExpensesKey);
    final list = raw != null ? (jsonDecode(raw) as List<dynamic>) : <dynamic>[];
    list.insert(0, expense.toJson());
    await prefs.setString(kLocalExpensesKey, jsonEncode(list));
  } catch (_) {}

  await NotificationService.instance.showTransaction(
    merchant: expense.merchant,
    amount: expense.amount,
    category: expense.category ?? 'Other',
    needsLabel: expense.needsLabel,
  );

  // Budget thresholds can be crossed by a background capture too.
  await BudgetService.checkAlerts();
}
