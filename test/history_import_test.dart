// The first-run history import: on a brand-new install the phone's inbox
// already holds months of bank messages, so Klaro should offer to pull them in
// rather than opening empty.
//
// Written to chase a real mystery: on a new phone the offer never appeared, and
// with the logic spread across startup, storage and the SMS plugin there was no
// way to ask "what does this actually do?" except by reinstalling on a device.
// With a fake inbox and mocked storage, the whole flow answers in milliseconds.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:expense_tracker/providers/expense_provider.dart';
import 'package:expense_tracker/services/sms_service.dart';
import 'package:expense_tracker/services/sms_source.dart';

import 'sms_import_test.dart' show FakeSmsSource;

void main() {
  // SharedPreferences ships its own in-memory test mode, so there is no reason
  // to wrap it — the seam already exists.
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(SmsService.instance.resetSourceForTest);

  InboxMessage msg(String merchant, double amount, DateTime on) => InboxMessage(
        sender: 'AX-SBIUPI',
        body: 'Dear UPI user A/C X1234 debited by $amount on 24May26 '
            'trf to $merchant Refno ${on.millisecondsSinceEpoch}. -SBI',
        date: on,
      );

  group('first run', () {
    test('offers the history import when the inbox has never been scanned', () async {
      SmsService.instance.configureSource(FakeSmsSource([]));
      final p = ExpenseProvider.withExpenses([]);

      expect(p.needsHistoryImport, isFalse, reason: 'not decided yet');
      await p.catchUpFromInbox();
      expect(p.needsHistoryImport, isTrue,
          reason: 'a fresh install should be offered its own history');
    });

    test('does not offer it again once the user has been asked', () async {
      // Simulates a later launch: the catch-up baseline exists AND the offer
      // was already resolved.
      SharedPreferences.setMockInitialValues({
        'last_catchup_ms': DateTime.now().millisecondsSinceEpoch,
        'history_import_done': true,
      });
      SmsService.instance.configureSource(FakeSmsSource([]));
      final p = ExpenseProvider.withExpenses([]);

      await p.catchUpFromInbox();
      expect(p.needsHistoryImport, isFalse);
    });

    test('the offer survives an app restart when the user never answered it',
        () async {
      // The scenario that actually happened on a new phone. Startup can reach
      // the catch-up scan through a path where the offer is never rendered (the
      // very first call is gated on SMS permission, and a later resume runs it
      // anyway). That call consumes the "first run" by writing the baseline —
      // so on the next launch the app thinks it has already asked, and the user
      // is never offered their own history. The question that matters is "has
      // the user RESOLVED this?", not "is this the first scan?".
      SmsService.instance.configureSource(FakeSmsSource([]));

      final first = ExpenseProvider.withExpenses([]);
      await first.catchUpFromInbox(); // consumes first-run, user sees nothing

      final afterRestart = ExpenseProvider.withExpenses([]);
      await afterRestart.catchUpFromInbox();

      expect(afterRestart.needsHistoryImport, isTrue,
          reason: 'still unanswered, so it must still be offered');
    });

    test('a first run that already declined is not re-asked', () async {
      // The baseline is missing (as on a fresh install) but the user has
      // previously said no — the decision must win over the fresh-install check.
      SharedPreferences.setMockInitialValues({'history_import_done': true});
      SmsService.instance.configureSource(FakeSmsSource([]));
      final p = ExpenseProvider.withExpenses([]);

      await p.catchUpFromInbox();
      expect(p.needsHistoryImport, isFalse);
    });
  });

  group('acting on the offer', () {
    test('importing pulls the inbox in and clears the offer', () async {
      final now = DateTime(2026, 8, 8, 12);
      SmsService.instance.configureSource(FakeSmsSource([
        msg('ZOMATO', 285, now.subtract(const Duration(days: 1))),
        msg('BLINKIT', 222, now.subtract(const Duration(days: 3))),
      ]));
      final p = ExpenseProvider.withExpenses([]);
      await p.catchUpFromInbox();
      expect(p.needsHistoryImport, isTrue);

      final r = await p.importHistory();

      expect(r.added, 2);
      expect(r.found, 2);
      expect(p.needsHistoryImport, isFalse, reason: 'never ask twice');
    });

    test('declining clears the offer for good', () async {
      SmsService.instance.configureSource(FakeSmsSource([]));
      final p = ExpenseProvider.withExpenses([]);
      await p.catchUpFromInbox();

      await p.dismissHistoryImport();
      expect(p.needsHistoryImport, isFalse);

      // And a later launch must not resurrect it.
      final p2 = ExpenseProvider.withExpenses([]);
      await p2.catchUpFromInbox();
      expect(p2.needsHistoryImport, isFalse);
    });

    test('importing twice does not double-count', () async {
      final now = DateTime(2026, 8, 8, 12);
      SmsService.instance.configureSource(FakeSmsSource([
        msg('ZOMATO', 285, now.subtract(const Duration(days: 1))),
      ]));
      final p = ExpenseProvider.withExpenses([]);

      final first = await p.importHistory();
      expect(first.added, 1);

      // The offer is spent, so importHistory won't run again — but the manual
      // menu import uses the same pipeline and must stay idempotent.
      await p.importFromInbox();
      expect(p.expenses.length, 1, reason: 're-import must dedupe');
    });

    test('an empty inbox is reported as "found nothing", not as an import', () async {
      SmsService.instance.configureSource(FakeSmsSource([]));
      final p = ExpenseProvider.withExpenses([]);

      final r = await p.importHistory();
      expect(r.added, 0);
      expect(r.found, 0, reason: 'lets the UI say "no messages" vs "up to date"');
    });
  });
}
