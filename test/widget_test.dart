import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/services/sms_service.dart';

void main() {
  // SmsService.instance constructs the Telephony plugin, which registers a
  // platform channel handler — needs the test binding initialized first.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SmsService.parseExpense', () {
    test('parses HDFC debit SMS with known merchant', () {
      final expense = SmsService.parseExpense(
        body: 'Rs.250.00 debited from a/c XX1234 to VPA zomato@icici on 15-01-25. Ref 123456.',
        sender: 'AD-HDFCBK',
        date: DateTime(2025, 1, 15),
      );
      expect(expense, isNotNull);
      expect(expense!.amount, 250.0);
      expect(expense.merchant, 'Zomato');
      expect(expense.isLabeled, true);
    });

    test('returns null for OTP SMS', () {
      final expense = SmsService.parseExpense(
        body: 'Your OTP is 123456. Do not share.',
        sender: 'AD-HDFCBK',
        date: DateTime.now(),
      );
      expect(expense, isNull);
    });

    test('parses credit SMS as income (money in)', () {
      final expense = SmsService.parseExpense(
        body: 'Rs.500.00 credited to your a/c XX1234.',
        sender: 'AD-SBIINB',
        date: DateTime.now(),
      );
      expect(expense, isNotNull);
      expect(expense!.amount, 500.0);
      expect(expense.isIncome, true);
      expect(expense.direction, 'credit');
      expect(expense.category, 'Income');
    });

    test('marks unknown UPI as unlabeled', () {
      final expense = SmsService.parseExpense(
        body: 'Rs.150.00 debited from a/c XX5678 to VPA shop12345@upi on 20-01-25.',
        sender: 'AD-AXIS',
        date: DateTime(2025, 1, 20),
      );
      expect(expense, isNotNull);
      expect(expense!.isLabeled, false);
      expect(expense.needsLabel, true);
    });

    test('parses AU Bank UPI debit with known merchant', () {
      final expense = SmsService.parseExpense(
        body: 'Dr INR 217.00 - AU A/c X0356 29-MAY-2026\nUPI/DR/651552180328/Blinkit/HDFC/50200\nBal INR 1,862.54',
        sender: 'AD-AUBANK-S',
        date: DateTime(2026, 5, 29),
      );
      expect(expense, isNotNull);
      expect(expense!.amount, 217.0);
      expect(expense.merchant, 'Blinkit');
      expect(expense.category, 'Grocery');
      expect(expense.method, 'upi');
    });

    test('card txn is named by bank', () {
      final expense = SmsService.parseExpense(
        body: 'IDBI Bank A/c N1705 Dr for INR 199.37 CardTxn:VISA-POI/CENT. Bal INR 965.94 on 24MAY 00:20hrs.',
        sender: 'JD-IDBIBK-S',
        date: DateTime(2026, 5, 24),
      );
      expect(expense, isNotNull);
      expect(expense!.amount, 199.37);
      expect(expense.merchant, 'Card (IDBI)');
      expect(expense.isLabeled, true);
      expect(expense.method, 'card');
      expect(expense.isCard, true);
    });

    test('card fee is categorized as Bills', () {
      final expense = SmsService.parseExpense(
        body: 'Alert! Your AU Bank A/c No. X0356 has been Dr with INR 588.82 on 24-APR-2026 for Debit Card Fee FY26 XX3180.',
        sender: 'CP-AUBANK-S',
        date: DateTime(2026, 4, 24),
      );
      expect(expense, isNotNull);
      expect(expense!.merchant, 'Card Fee (AU)');
      expect(expense.category, 'Bills');
      expect(expense.method, 'card');
    });

    test('rejects promotional voucher SMS (false positive)', () {
      final expense = SmsService.parseExpense(
        body: 'Rs.250 voucher unlocked on your AU RuPay Platinum Debit Card. Claim within 90 days.',
        sender: 'VM-AUBANK-S',
        date: DateTime(2026, 5, 24),
      );
      expect(expense, isNull);
    });

    test('rejects declined payment SMS', () {
      final expense = SmsService.parseExpense(
        body: 'Incorrect CVV! Payment of Rs.500.00 on your AU Bank Debit Card XX3180 was DECLINED.',
        sender: 'AD-AUBANK-S',
        date: DateTime(2026, 5, 24),
      );
      expect(expense, isNull);
    });

    test('rejects card OTP SMS even though it has a merchant', () {
      final expense = SmsService.parseExpense(
        body: 'OTP is 576970 for txn at ANTHROPIC for USD 23.60 on your card XXXX 0065.',
        sender: 'JK-IDBIBK-T',
        date: DateTime(2026, 5, 24),
      );
      expect(expense, isNull);
    });
  });
}
