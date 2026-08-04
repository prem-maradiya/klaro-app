// Privacy acceptance test (on-device parsing + clean sync).
//
// Proves the core privacy promise in code: a real Indian bank SMS is parsed
// fully ON-DEVICE, and the payload uploaded to the backend/dashboard
// (`toSyncJson`) NEVER contains the raw SMS, account numbers, balances, refs or
// the VPA — only the curated transaction plus a one-way dedupe hash. The raw
// SMS is still RETAINED locally (`toJson`), so nothing is lost on the device.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/services/sms_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final d = DateTime(2026, 5, 24);

  // Each sample: the SMS, what the on-device parser should yield, and the
  // sensitive tokens (account no / balance / ref / VPA) that must NEVER appear
  // in the uploaded payload. Merchant + amount legitimately DO sync, so they are
  // never listed as secrets.
  final samples = <Map<String, dynamic>>[
    {
      'sender': 'AX-SBIUPI',
      'body':
          'Dear UPI user A/C X1234 debited by 285.0 on 24May26 trf to ZOMATO Refno 123456789012. -SBI',
      'amount': 285.0,
      'merchant': 'Zomato',
      'secrets': ['X1234', '123456789012'],
    },
    {
      'sender': 'JX-HDFCBK',
      'body':
          'Spent Rs.499 On HDFC Bank Card x1234 At AMAZON On 2026-05-24:18:30. Avl bal Rs.5000',
      'amount': 499.0,
      'merchant': 'Amazon',
      'secrets': ['x1234', '5000'], // card tail + balance
    },
    {
      'sender': 'VM-ICICIB',
      'body':
          'ICICI Bank Acct XX123 debited for Rs 320.00 on 24-May-26; BLINKIT credited. UPI:123456789012.',
      'amount': 320.0,
      'merchant': 'Blinkit',
      'secrets': ['XX123', '123456789012'],
    },
    {
      'sender': 'TM-AXISBK',
      'body':
          'INR 240.00 debited A/c no. XX1234 24-05-26 12:30:45 UPI/P2M/123456789/UBER. -Axis Bank',
      'amount': 240.0,
      'merchant': 'Uber',
      'secrets': ['XX1234', '123456789'],
    },
    {
      'sender': 'VK-KOTAKB',
      'body':
          'Sent Rs.180.00 from Kotak Bank AC X1234 to swiggy@ybl on 24-05-26. UPI Ref 123456789012.',
      'amount': 180.0,
      'merchant': 'Swiggy',
      'secrets': ['swiggy@ybl', '@ybl', 'X1234', '123456789012'], // VPA stripped
    },
    {
      'sender': 'AD-AUBANK-S',
      'body':
          'Dr INR 217.00 - AU A/c X0356 24-MAY-2026\nUPI/DR/651552180328/Blinkit/HDFC/50200\nBal INR 1,862.54',
      'amount': 217.0,
      'merchant': 'Blinkit',
      'secrets': ['X0356', '651552180328', '1,862.54', '1862.54'], // ref + balance
    },
    {
      'sender': 'JD-IDBIBK-S',
      'body':
          'IDBI Bank Acct XX705 debited for Rs 40.00 on 08-Jun-26; Bal Rs 196497.31 SOUTH SPICE CAFE credited. UPI:615949337128. -IDBI Bank',
      'amount': 40.0,
      'merchant': 'SOUTH SPICE CAFE',
      'secrets': ['XX705', '196497.31', '615949337128'], // account + balance + ref
    },
    {
      'sender': 'JM-SBIUPI',
      'body':
          'Dear SBI User, your A/c X1234-credited by Rs.50000 on 01Jun26 transfer from ACME CORP Ref No 123 -SBI',
      'amount': 50000.0,
      'merchant': 'ACME CORP', // income from a company, not a person
      'income': true,
      'secrets': ['X1234'],
    },
  ];

  group('Privacy: on-device parse, nothing sensitive uploaded', () {
    for (final s in samples) {
      test('${s['merchant']} — parsed locally, clean sync payload', () {
        final body = s['body'] as String;

        // 1) Parses fully on-device (no network anywhere in this call).
        final e = SmsService.parseExpense(
            body: body, sender: s['sender'] as String, date: d);
        expect(e, isNotNull, reason: 'should parse on-device: $body');
        expect(e!.amount, s['amount']);
        expect(e.merchant, s['merchant']);
        if (s['income'] == true) expect(e.isIncome, true);

        // 2) The uploaded payload (minus the dedupe hash, which is hex noise)
        //    must contain NONE of the raw message, account no, balance, ref or VPA.
        final sync = e.toSyncJson();
        final blob = jsonEncode(Map.of(sync)..remove('raw_sms_hash'));

        expect(sync.containsKey('raw_sms'), isFalse,
            reason: 'raw_sms must never be uploaded');
        expect(sync.containsKey('upi_id'), isFalse,
            reason: 'upi_id (VPA) must never be uploaded');
        expect(blob.contains(body), isFalse, reason: 'raw SMS body leaked');
        for (final secret in (s['secrets'] as List).cast<String>()) {
          expect(blob.contains(secret), isFalse,
              reason: 'leaked sensitive token "$secret" in payload: $blob');
        }

        // 3) Dedupe still works: a 64-char ONE-WAY hash is sent (not the text).
        final hash = sync['raw_sms_hash'];
        expect(hash, isA<String>());
        expect((hash as String).length, 64);
        expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), isTrue);
        expect(hash, isNot(equals(body.replaceAll(RegExp(r'\s+'), ''))));

        // 4) ...but the raw SMS is RETAINED locally (on-device store keeps it).
        expect(e.toJson()['raw_sms'], body,
            reason: 'raw SMS must remain in the on-device store');

        // 5) Source is sent explicitly (server no longer infers it from raw_sms).
        //    All these samples come from SMS, so it must be 'sms'.
        expect(sync['source'], 'sms');
      });
    }

    // Regression guard for the new-device flow: restore an account on a fresh
    // phone (rows arrive WITHOUT the raw SMS, by design), then import the inbox.
    // Identity must survive that gap via the hash, or every transaction would be
    // added a second time and the user's spending would silently double.
    test('a restored transaction still matches the same SMS re-parsed', () {
      final s = samples.first;
      final parsed = SmsService.parseExpense(
          body: s['body'] as String, sender: s['sender'] as String, date: d)!;

      // What the backend hands back on a new device: cleaned fields + the hash,
      // and explicitly no raw_sms / upi_id.
      final restored = Expense.fromJson({
        'id': 42,
        'merchant': parsed.merchant,
        'amount': parsed.amount,
        'date': parsed.date.toIso8601String(),
        'category': parsed.category,
        'is_labeled': parsed.isLabeled,
        'direction': parsed.direction,
        'raw_sms_hash': parsed.syncHash,
      });

      expect(restored.rawSms, isEmpty, reason: 'backend must not return the SMS');
      expect(restored.syncHash, isNull, reason: 'nothing to hash locally');
      expect(restored.dedupeHash, isNotNull);
      expect(restored.dedupeHash, parsed.dedupeHash,
          reason: 'restored row and re-parsed SMS must share one identity');
    });

    test('dedupe identity survives a local save/load round-trip', () {
      final restored = Expense.fromJson({
        'merchant': 'Zomato', 'amount': 285.0,
        'date': d.toIso8601String(), 'raw_sms_hash': 'f' * 64,
      });
      // Written to disk and read back (app restart) — the hash must persist,
      // since there's no raw SMS to recompute it from.
      final reloaded = Expense.fromJson(restored.toJson());
      expect(reloaded.dedupeHash, 'f' * 64);
    });

    test('two unrelated transactions never share an identity', () {
      final a = SmsService.parseExpense(
          body: samples[0]['body'] as String,
          sender: samples[0]['sender'] as String, date: d)!;
      final b = SmsService.parseExpense(
          body: samples[1]['body'] as String,
          sender: samples[1]['sender'] as String, date: d)!;
      expect(a.dedupeHash, isNot(equals(b.dedupeHash)));
    });

    test('blanket guarantee: no sample ever leaks its raw body or PII keys', () {
      for (final s in samples) {
        final e = SmsService.parseExpense(
            body: s['body'] as String, sender: s['sender'] as String, date: d)!;
        final sync = e.toSyncJson();
        expect(sync.containsKey('raw_sms'), isFalse);
        expect(sync.containsKey('upi_id'), isFalse);
        expect(jsonEncode(Map.of(sync)..remove('raw_sms_hash'))
            .contains(s['body'] as String), isFalse);
      }
    });
  });
}
