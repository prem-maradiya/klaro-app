// Inbox-reading behaviour, tested with a FAKE inbox — no phone, no plugin.
//
// This is the tier of test that did not exist before. The bank-format suite
// covered parsing (pure functions), but the code that FETCHES messages called
// the SMS plugin directly, so nothing could reach it. That is exactly where the
// "import read the oldest messages and found nothing" bug lived: 69 tests
// passed while a real phone with a 13k-message inbox silently imported nothing.
//
// With SmsSource as a seam, a fake inbox can now stand in for the phone.
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/services/sms_service.dart';
import 'package:expense_tracker/services/sms_source.dart';

/// An in-memory inbox that honours the [SmsSource] contract: newest first,
/// optionally bounded by [since], capped at [limit].
class FakeSmsSource implements SmsSource {
  FakeSmsSource(this.messages, {this.permissionGranted = true});

  final List<InboxMessage> messages;
  final bool permissionGranted;

  /// Records what the service asked for, so tests can assert on the request and
  /// not just the result.
  int? lastLimit;
  DateTime? lastSince;
  void Function(InboxMessage)? listener;

  @override
  Future<bool> requestPermission() async => permissionGranted;

  @override
  void listenIncoming(void Function(InboxMessage) onMessage) =>
      listener = onMessage;

  @override
  Future<List<InboxMessage>> readInbox({DateTime? since, int limit = 2000}) async {
    lastSince = since;
    lastLimit = limit;
    final sorted = [...messages]..sort((a, b) => b.date.compareTo(a.date));
    final filtered =
        since == null ? sorted : sorted.where((m) => m.date.isAfter(since));
    return filtered.take(limit).toList();
  }
}

void main() {
  final service = SmsService.instance;

  tearDown(service.resetSourceForTest);

  InboxMessage debit({
    required String merchant,
    required double amount,
    required DateTime on,
  }) =>
      InboxMessage(
        sender: 'AX-SBIUPI',
        // A real SBI format from the bank-format corpus.
        body: 'Dear UPI user A/C X1234 debited by $amount on 24May26 '
            'trf to $merchant Refno ${on.millisecondsSinceEpoch}. -SBI',
        date: on,
      );

  group('importing from a large inbox', () {
    // The shape of the real failure: thousands of messages spanning years, and
    // a cap far below that total. The cap must drop the OLDEST, never the newest.
    late FakeSmsSource inbox;
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 8, 8, 12);
      inbox = FakeSmsSource([
        // 1000 ancient messages...
        for (var i = 0; i < 1000; i++)
          debit(
              merchant: 'OLDSHOP',
              amount: 10,
              on: now.subtract(Duration(days: 400 + i))),
        // ...and one payment from this morning.
        debit(merchant: 'ZOMATO', amount: 285, on: now.subtract(const Duration(hours: 2))),
      ]);
      service.configureSource(inbox);
    });

    test('a recent payment survives a cap smaller than the inbox', () async {
      final found = await service.importInboxExpenses(maxMessages: 50);
      expect(found.any((e) => e.amount == 285), isTrue,
          reason: "today's payment must not be cut by the cap");
    });

    test('the cap is passed down, not applied after fetching', () async {
      // If the service fetched everything and trimmed afterwards, the source
      // would never learn the limit — and on a real phone that means parsing
      // 13k messages on the UI thread.
      await service.importInboxExpenses(maxMessages: 50);
      expect(inbox.lastLimit, 50);
    });

    test('a full import asks for no lower bound', () async {
      await service.importInboxExpenses();
      expect(inbox.lastSince, isNull);
    });
  });

  group('catch-up scan', () {
    test('asks only for messages after the given moment', () async {
      final now = DateTime(2026, 8, 8, 12);
      final cutoff = now.subtract(const Duration(days: 1));
      final inbox = FakeSmsSource([
        debit(merchant: 'ZOMATO', amount: 285, on: now),
        debit(merchant: 'OLDSHOP', amount: 99, on: now.subtract(const Duration(days: 30))),
      ]);
      service.configureSource(inbox);

      final found =
          await service.catchUpExpenses(sinceMs: cutoff.millisecondsSinceEpoch);

      expect(inbox.lastSince, cutoff);
      expect(found.length, 1, reason: 'the 30-day-old spend is out of range');
      expect(found.single.amount, 285);
    });
  });

  group('permission handling', () {
    test('initialize reports failure and does not listen when denied', () async {
      final inbox = FakeSmsSource([], permissionGranted: false);
      service.configureSource(inbox);

      expect(await service.initialize(), isFalse);
      expect(inbox.listener, isNull,
          reason: 'must not start listening without permission');
    });

    test('initialize starts listening once granted', () async {
      final inbox = FakeSmsSource([]);
      service.configureSource(inbox);

      expect(await service.initialize(), isTrue);
      expect(inbox.listener, isNotNull);
    });
  });

  group('safety net', () {
    test('using SMS without wiring an inbox fails loudly, not silently', () {
      // A silent no-op here would look exactly like "the user has no messages",
      // which is the failure mode that cost an afternoon on a real device.
      service.resetSourceForTest();
      expect(service.hasSource, isFalse);
      expect(() => service.importInboxExpenses(), throwsStateError);
    });
  });
}
