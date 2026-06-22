// Accuracy harness: runs the REAL parser against the full dump of the user's
// bank SMS (test/fixtures/sms_corpus.json) and prints a report — how many
// parsed, likely MISSES (look like debits but didn't parse), and SUSPICIOUS
// parses (polluted merchant / balance-as-amount / Unknown). Personal data;
// the corpus file is gitignored. Run: flutter test test/parser_report_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/services/sms_service.dart';

// Independent "this is a REAL completed debit" heuristic — mirrors the parser's
// exclusions so that a "miss" means a genuinely missed spend (not a declined /
// requested / refunded / scheduled / zero-amount message).
bool _looksLikeDebit(String body) {
  final b = body.toLowerCase();
  final hasAmount = RegExp(r'(?:rs\.?|inr)\s*[\d,]+(?:\.\d+)?|debited by\s+[\d,]+').hasMatch(b);
  final zeroAmt = RegExp(r'(?:rs\.?|inr)\s*0+(?:\.0+)?\b').hasMatch(b) &&
      !RegExp(r'(?:rs\.?|inr)\s*[1-9]').hasMatch(b);
  final hasDebitVerb = b.contains('debited') ||
      b.contains('spent') ||
      RegExp(r'\bsent\b').hasMatch(b) ||
      b.contains('withdrawn') ||
      b.contains('trf to') ||
      b.contains('transfer to') ||
      b.contains('debit') ||
      RegExp(r'\bdr\b').hasMatch(b) ||
      b.contains(' paid ');
  final notReal =
      // credits / refunds / reversals
      b.contains('credited to your') ||
          b.contains('is credited') ||
          b.contains('credited with') ||
          b.trimLeft().startsWith('credited') ||
          b.contains('dr-rev') ||
          b.contains('reversal') ||
          b.contains('refund') ||
          b.contains('received from') ||
          b.contains('deposited') ||
          // not-completed
          b.contains('otp') ||
          b.contains('declined') ||
          b.contains('failed') ||
          b.contains('could not') ||
          b.contains('has requested') ||
          b.contains('requested money') ||
          b.contains('requested payment') ||
          b.contains('will be debited') ||
          b.contains('on approval') ||
          b.contains('on approving') ||
          b.contains('scheduled') ||
          // promos / info
          b.contains('voucher') ||
          b.contains('cashback') ||
          b.contains('% off') ||
          b.contains('apply now') ||
          (b.contains('available balance') && !b.contains('debited'));
  return hasAmount && !zeroAmt && hasDebitVerb && !notReal;
}

bool _suspiciousParse(String merchant, double amount) {
  if (merchant == 'Unknown' || merchant == 'Card payment') return true;
  if (RegExp(r'\bBal\b|Refno|Ref\s|UPI:|A/c|Acct|debited|credited', caseSensitive: false)
      .hasMatch(merchant)) return true;
  if (RegExp(r'\d{6,}').hasMatch(merchant)) return true; // long digit runs
  if (amount >= 100000) return true; // likely grabbed a balance
  return false;
}

String _snip(String s, int n) =>
    s.replaceAll('\n', ' ').substring(0, s.length < n ? s.length : n);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parser accuracy report over real bank SMS', () {
    final file = File('test/fixtures/sms_corpus.json');
    if (!file.existsSync()) {
      print('No corpus file — run the adb dump first.');
      return;
    }
    final List corpus = jsonDecode(file.readAsStringSync());

    int parsed = 0;
    final misses = <Map>[];
    final suspicious = <String>[];
    final falsePositives = <String>[];

    for (final rec in corpus) {
      final address = (rec['address'] ?? '').toString();
      final body = (rec['body'] ?? '').toString();
      if (body.isEmpty) continue;

      final e = SmsService.parseExpense(body: body, sender: address, date: DateTime(2026, 6, 8));
      final candidate = _looksLikeDebit(body);

      if (e != null) {
        parsed++;
        if (_suspiciousParse(e.merchant, e.amount)) {
          suspicious.add("Rs${e.amount} '${e.merchant}' <= ${_snip(body, 90)}");
        }
        if (!candidate) {
          falsePositives.add("Rs${e.amount} '${e.merchant}' <= ${_snip(body, 90)}");
        }
      } else if (candidate) {
        misses.add({'a': address, 'b': body});
      }
    }

    print('\n======== PARSER ACCURACY REPORT ========');
    print('Total bank SMS in corpus : ${corpus.length}');
    print('Parsed as debit          : $parsed');
    print('Likely MISSES            : ${misses.length}  (look like debits but parser returned null)');
    print('SUSPICIOUS parses        : ${suspicious.length}  (polluted merchant / balance-as-amount / Unknown)');
    print('Likely FALSE POSITIVES   : ${falsePositives.length}  (parsed but does not look like a debit)');

    print('\n---- MISS samples (up to 30) ----');
    for (final m in misses.take(30)) {
      print('[${m['a']}] ${_snip(m['b'].toString(), 130)}');
    }

    print('\n---- SUSPICIOUS-PARSE samples (up to 30) ----');
    for (final s in suspicious.take(30)) {
      print(s);
    }

    print('\n---- FALSE-POSITIVE samples (up to 20) ----');
    for (final f in falsePositives.take(20)) {
      print(f);
    }
    print('======== END REPORT ========\n');
  });

  test('diagnostic: AI-fallback candidate count', () {
    final file = File('test/fixtures/sms_corpus.json');
    if (!file.existsSync()) return;
    final List corpus = jsonDecode(file.readAsStringSync());
    int candidates = 0;
    final samples = <String>[];
    for (final rec in corpus) {
      final body = (rec['body'] ?? '').toString();
      final sender = (rec['address'] ?? '').toString();
      if (SmsService.looksLikeUnparsedTxn(sender, body)) {
        candidates++;
        if (samples.length < 15) samples.add('[$sender] ${_snip(body, 100)}');
      }
    }
    print('\n>> AI-fallback candidates (regex-failed but txn-like): $candidates of ${corpus.length}');
    for (final s in samples) {
      print('   $s');
    }
  });

  test('diagnostic: IDBI "transaction of" card SMS', () {
    final file = File('test/fixtures/sms_corpus.json');
    if (!file.existsSync()) return;
    final List corpus = jsonDecode(file.readAsStringSync());
    int n = 0;
    for (final rec in corpus) {
      final body = (rec['body'] ?? '').toString();
      if (!RegExp(r'transaction of', caseSensitive: false).hasMatch(body)) continue;
      if (n++ >= 12) break;
      final e = SmsService.parseExpense(
          body: body, sender: (rec['address'] ?? '').toString(), date: DateTime(2026, 6, 8));
      print('[${e == null ? "NULL" : "${e.merchant} | Rs${e.amount}"}] <= ${_snip(body, 110)}');
    }
  });
}
