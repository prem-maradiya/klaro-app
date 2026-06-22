// Universal bank SMS parsing corpus — one realistic debit SMS per major Indian
// bank format. This is the spec for the universal parser: each must yield the
// right amount and a sensible merchant. Merchant names use known brands so we
// can also assert auto-categorization where relevant.
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/models/expense.dart';
import 'package:expense_tracker/services/sms_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final d = DateTime(2026, 5, 24);

  Expense parse(String body, String sender) {
    final e = SmsService.parseExpense(body: body, sender: sender, date: d);
    expect(e, isNotNull, reason: 'should parse: $body');
    return e!;
  }

  group('Universal bank debit formats', () {
    test('SBI UPI — "debited by 150.0 ... trf to"', () {
      final e = parse(
        'Dear UPI user A/C X1234 debited by 285.0 on 24May26 trf to ZOMATO Refno 123456789012. If not u? call 1800111109. -SBI',
        'AX-SBIUPI',
      );
      expect(e.amount, 285.0);
      expect(e.merchant, 'Zomato');
      expect(e.category, 'Food');
    });

    test('HDFC — "Sent Rs.X From ... To MERCHANT"', () {
      final e = parse(
        'Sent Rs.150.00 From HDFC Bank A/C x1234 To SWIGGY On 24-05 Ref 123456789. Not You? Call 18002586161',
        'JX-HDFCBK',
      );
      expect(e.amount, 150.0);
      expect(e.merchant, 'Swiggy');
    });

    test('HDFC card — "Spent Rs.X On Card ... At MERCHANT"', () {
      final e = parse(
        'Spent Rs.499 On HDFC Bank Card x1234 At AMAZON On 2026-05-24:18:30. Avl bal Rs.5000',
        'JX-HDFCBK',
      );
      expect(e.amount, 499.0);
      expect(e.merchant, 'Amazon');
      expect(e.isCard, true);
    });

    test('ICICI — "debited for Rs X ; MERCHANT credited"', () {
      final e = parse(
        'ICICI Bank Acct XX123 debited for Rs 320.00 on 24-May-26; BLINKIT credited. UPI:123456789012. Call 18002 for dispute.',
        'VM-ICICIB',
      );
      expect(e.amount, 320.0);
      expect(e.merchant, 'Blinkit');
      expect(e.category, 'Grocery');
    });

    test('Axis — "INR X debited ... UPI/P2M/ref/MERCHANT"', () {
      final e = parse(
        'INR 240.00 debited A/c no. XX1234 24-05-26 12:30:45 UPI/P2M/123456789/UBER. Call 18004195577. -Axis Bank',
        'TM-AXISBK',
      );
      expect(e.amount, 240.0);
      expect(e.merchant, 'Uber');
      expect(e.category, 'Transport');
    });

    test('Kotak — "Sent Rs.X from ... to vpa"', () {
      final e = parse(
        'Sent Rs.180.00 from Kotak Bank AC X1234 to swiggy@ybl on 24-05-26. UPI Ref 123456789012. Not you, kotak.com/fraud',
        'VK-KOTAKB',
      );
      expect(e.amount, 180.0);
      expect(e.merchant, 'Swiggy');
    });

    test('IDFC First — "debited by INR X ... Info: UPI/MERCHANT/ref"', () {
      final e = parse(
        'Your A/C XXXXX1234 is debited by INR 99.00 on 24-May-26. Info: UPI/NETFLIX/123456789. -IDFC FIRST Bank',
        'JX-IDFCFB',
      );
      expect(e.amount, 99.0);
      expect(e.merchant, 'Netflix');
      expect(e.category, 'Entertainment');
    });

    test('Yes Bank — "Rs X debited ... to vpa via UPI"', () {
      final e = parse(
        'Rs 410.00 debited from A/c XX1234 on 24-May-26 to bigbasket@ybl via UPI Ref 123456789. -YES BANK',
        'AD-YESBNK-S',
      );
      expect(e.amount, 410.0);
      expect(e.merchant, 'BigBasket');
      expect(e.category, 'Grocery');
    });

    test('PNB — "Debited INR X ... trf to MERCHANT"', () {
      final e = parse(
        'Dear Customer your A/C XX1234 Debited INR 199.00 Dt 24-05-26 trf to SPOTIFY Ref 123456. -PNB',
        'JX-PSBINS-P',
      );
      expect(e.amount, 199.0);
      expect(e.merchant, 'Spotify');
    });

    test('SBI spelled-out "transfer to MERCHANT" (real format)', () {
      final e = parse(
        'Dear SBI User, your A/c X2664-debited by Rs148.0 on 04Jul23 transfer to Zomato Ref No 3185 -SBI',
        'JM-SBIUPI',
      );
      expect(e.amount, 148.0);
      expect(e.merchant, 'Zomato');
    });

    test('IDBI debit-card "transaction of Rs X ... at MERCHANT" (real format)', () {
      final e = parse(
        'Dear Customer, transaction of Rs 145.00 dated 29-May-25 00:29:31 on your IDBI Bank Debit Card ending with 0065 at Resume-Now.com',
        'JD-IDBIBK-S',
      );
      print('  >> IDBI card parse: merchant="${e.merchant}" card=${e.isCard} amount=${e.amount}');
      expect(e.amount, 145.0);
      expect(e.isCard, true);
    });

    test('IDBI — "debited for Rs X; Bal Rs <bal> MERCHANT credited" (real format)', () {
      final e = parse(
        'IDBI Bank Acct XX705 debited for Rs 40.00 on 08-Jun-26; Bal Rs 196497.31 SOUTH SPICE CAFE credited. UPI:615949337128. -IDBI Bank',
        'JD-IDBIBK-S',
      );
      expect(e.amount, 40.0);
      expect(e.merchant, 'SOUTH SPICE CAFE'); // NOT "Bal Rs 196497.31 SOUTH SPICE CAFE"
    });

    test('IDBI UPI-AutoPay / mandate — "debited ... towards MERCHANT for Create Mandate AutoPay" (real format)', () {
      final e = parse(
        'Your account has been successfully debited with Rs 199.00 on 14-Jun-26 towards NETFLIX for Create Mandate AutoPay, RRN 103478598118-IDBI Bank',
        'JD-IDBIBK-S',
      );
      expect(e.amount, 199.0);
      expect(e.merchant, 'Netflix'); // NOT "IDBI Bank" (trailing -IDBI Bank) nor a contact
      expect(e.category, 'Entertainment');
      // An EXECUTED autopay debit — money left the account, so it's a spend.
      expect(e.direction, 'debit');
      expect(e.isIncome, false);
    });

    test('AU Bank — existing UPI/DR format still works', () {
      final e = parse(
        'Dr INR 217.00 - AU A/c X0356 24-MAY-2026\nUPI/DR/651552180328/Blinkit/HDFC/50200\nBal INR 1,862.54',
        'AD-AUBANK-S',
      );
      expect(e.amount, 217.0);
      expect(e.merchant, 'Blinkit');
    });

    test('SBI ATM withdrawal', () {
      final e = parse(
        'Rs.2000 withdrawn at SBI ATM S1AB1234 from A/c X1234 on 24-05-26. Avl Bal Rs.5000. -SBI',
        'AX-SBIUPI',
      );
      expect(e.amount, 2000.0);
    });

    test('does NOT parse a balance-enquiry / non-debit', () {
      final e = SmsService.parseExpense(
        body: 'Your A/c XX1234 balance is Rs.5000.00 as on 24-05-26. -SBI',
        sender: 'AX-SBIUPI',
        date: d,
      );
      expect(e, isNull);
    });
  });

  group('Income (credit) formats', () {
    Expense parseIncome(String body, String sender) {
      final e = SmsService.parseExpense(body: body, sender: sender, date: d);
      expect(e, isNotNull, reason: 'should parse as income: $body');
      expect(e!.isIncome, true, reason: 'should be a credit: $body');
      expect(e.direction, 'credit');
      expect(e.category, 'Income');
      return e;
    }

    test('SBI — salary "credited by Rs X transfer from PAYER"', () {
      final e = parseIncome(
        'Dear SBI User, your A/c X1234-credited by Rs.50000 on 01Jun26 transfer from ACME CORP Ref No 123 -SBI',
        'JM-SBIUPI',
      );
      expect(e.amount, 50000.0);
      expect(e.merchant.toUpperCase(), contains('ACME'));
    });

    test('IDBI — "A/c credited for INR X thru UPI" (grabs amount, not balance)', () {
      final e = parseIncome(
        'IDBI Bank Acct XX705 credited for INR 5000.00 on 09-Jun-26 thru UPI by john@oksbi; Bal Rs 200000.00. -IDBI Bank',
        'JD-IDBIBK-S',
      );
      expect(e.amount, 5000.0);
    });

    test('HDFC — "Rs X credited to your A/c" (amount before the verb)', () {
      final e = parseIncome(
        'Rs.1299.00 credited to your HDFC Bank A/c XX1234 on 09-Jun-26. Avl Bal Rs.5000.00',
        'JX-HDFCBK',
      );
      expect(e.amount, 1299.0);
    });

    test('refund / reversal is income', () {
      // NB: a clean reversal — SMS that say "failed" are intentionally dropped
      // by the non-transaction filter (a payment-failure notice moves no money,
      // and is safer to skip than to risk a false "will be refunded" credit).
      final e = parseIncome(
        'Your A/c XX1234 is credited with Rs 500.00 by a UPI reversal on 09-Jun-26. -Axis Bank',
        'TM-AXISBK',
      );
      expect(e.amount, 500.0);
    });

    test('a debit whose PAYEE is "credited" stays a spend (not income)', () {
      final e = SmsService.parseExpense(
        body:
            'ICICI Bank Acct XX123 debited for Rs 320.00 on 24-May-26; BLINKIT credited. UPI:123456789012.',
        sender: 'VM-ICICIB',
        date: d,
      );
      expect(e, isNotNull);
      expect(e!.isIncome, false);
      expect(e.direction, 'debit');
      expect(e.merchant, 'Blinkit');
    });
  });
}
