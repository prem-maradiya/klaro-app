import 'dart:convert';
import 'dart:ui';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:another_telephony/telephony.dart';
import '../models/expense.dart';
import 'budget_service.dart';
import 'contacts_service.dart';
import 'notification_service.dart';

// Local storage key shared between the app and the background isolate.
const String kLocalExpensesKey = 'local_expenses';

// Top-level background handler — runs in a SEPARATE isolate when an SMS arrives
// while the app is closed / backgrounded. Parses it, stores it locally so it's
// there on next launch, and fires a notification so the spend "appears" instantly.
@pragma('vm:entry-point')
void backgroundSmsHandler(SmsMessage message) async {
  // Register plugins in this background isolate (SharedPreferences, notifications).
  DartPluginRegistrant.ensureInitialized();

  final body = message.body ?? '';
  final address = message.address ?? '';
  final date = message.date != null
      ? DateTime.fromMillisecondsSinceEpoch(message.date!)
      : DateTime.now();

  // Contacts aren't loaded in the background isolate, so payee->Personal won't
  // apply here; the app re-evaluates on next open.
  final expense = SmsService.parseExpense(body: body, sender: address, date: date);
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

class SmsService {
  static final SmsService instance = SmsService._();
  SmsService._();

  final Telephony _telephony = Telephony.instance;

  static const Map<String, String> _knownMerchants = {
    'zomato': 'Zomato',
    'swiggy': 'Swiggy',
    'instamartswiggy': 'Swiggy Instamart',
    'blinkit': 'Blinkit',
    'blinkitbygrofers': 'Blinkit',
    'grofers': 'Blinkit',
    'zepto': 'Zepto',
    'bigbasket': 'BigBasket',
    'dmart': 'DMart',
    'dunzo': 'Dunzo',
    'amazon': 'Amazon',
    'amazonpay': 'Amazon Pay',
    'flipkart': 'Flipkart',
    'myntra': 'Myntra',
    'nykaa': 'Nykaa',
    'uber': 'Uber',
    'ola': 'Ola Cabs',
    'rapido': 'Rapido',
    'netflix': 'Netflix',
    'spotify': 'Spotify',
    'hotstar': 'Disney+ Hotstar',
    'disneyhotstar': 'Disney+ Hotstar',
    'jiocinema': 'JioCinema',
    'primevideo': 'Amazon Prime',
    'phonepe': 'PhonePe',
    'paytm': 'Paytm',
    'gpay': 'Google Pay',
    'yesbank': 'Yes Bank',
  };

  static const Map<String, String> _merchantCategories = {
    'Zomato': 'Food',
    'Swiggy': 'Food',
    'Swiggy Instamart': 'Grocery',
    'Blinkit': 'Grocery',
    'Zepto': 'Grocery',
    'BigBasket': 'Grocery',
    'DMart': 'Grocery',
    'Dunzo': 'Grocery',
    'Amazon': 'Shopping',
    'Amazon Pay': 'Transfer',
    'Flipkart': 'Shopping',
    'Myntra': 'Shopping',
    'Nykaa': 'Shopping',
    'Uber': 'Transport',
    'Ola Cabs': 'Transport',
    'Rapido': 'Transport',
    'Netflix': 'Entertainment',
    'Spotify': 'Entertainment',
    'Disney+ Hotstar': 'Entertainment',
    'JioCinema': 'Entertainment',
    'Amazon Prime': 'Entertainment',
    'PhonePe': 'Transfer',
    'Paytm': 'Transfer',
    'Google Pay': 'Transfer',
  };

  // Amount right after a debit verb (handles SBI's "debited by 285.0" with no
  // currency prefix, plus "Sent Rs.150", "Dr INR 217", "debited for Rs 320"...).
  static final _amountVerbRegex = RegExp(
    r'(?:debited by|debited for|debit of|debited|sent|spent|paid|withdrawn|\bdr(?:\s+for)?)\s+(?:rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );
  // Fallback: first currency amount (handles "INR 240 debited", "Rs.2000 withdrawn").
  static final _amountRegex = RegExp(
    r'(?:Rs\.?|INR)\s*([0-9,]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  // Ordered by specificity — "to VPA" before generic "to"
  static final _upiPatterns = [
    RegExp(r'to VPA\s+([a-zA-Z0-9][a-zA-Z0-9._-]{0,50}@[a-zA-Z0-9]{2,20})', caseSensitive: false),
    RegExp(r'VPA\s+([a-zA-Z0-9][a-zA-Z0-9._-]{0,50}@[a-zA-Z0-9]{2,20})', caseSensitive: false),
    RegExp(r'to\s+([a-zA-Z0-9][a-zA-Z0-9._-]{1,50}@[a-zA-Z0-9]{2,20})\b', caseSensitive: false),
    RegExp(r'\b([a-zA-Z0-9][a-zA-Z0-9._-]{1,50}@[a-zA-Z0-9]{2,20})\b'),
  ];

  void Function(Expense)? onNewExpense;

  Future<bool> initialize() async {
    final granted = await _telephony.requestSmsPermissions ?? false;
    if (!granted) return false;

    _telephony.listenIncomingSms(
      onNewMessage: (SmsMessage msg) => _handleMessage(msg),
      onBackgroundMessage: backgroundSmsHandler,
      listenInBackground: true,
    );
    return true;
  }

  // Foreground path: app is open when the SMS arrives. The provider adds it to
  // the live list (via onNewExpense); we also fire the notification.
  Future<void> _handleMessage(SmsMessage message) async {
    final body = message.body ?? '';
    final address = message.address ?? '';
    final date = message.date != null
        ? DateTime.fromMillisecondsSinceEpoch(message.date!)
        : DateTime.now();

    var expense = parseExpense(body: body, sender: address, date: date);
    // Regex couldn't parse it but it looks like a real debit -> capture it as an
    // UNRECOGNIZED spend (amount only, unlabeled) so it's never silently lost and
    // the user can categorize it in one tap. No network, no LLM — nothing leaves
    // the device.
    expense ??= _unrecognizedExpense(body: body, sender: address, date: date);
    if (expense == null) return;

    await NotificationService.instance.showTransaction(
      merchant: expense.merchant,
      amount: expense.amount,
      category: expense.category ?? 'Other',
      needsLabel: expense.needsLabel,
    );

    onNewExpense?.call(expense);
  }

  /// Parse user-pasted transaction text (the "Import from text" feature) fully
  /// on-device — no network, no LLM. The user has explicitly said "this is a
  /// transaction", so we satisfy the bank-sender gate with a synthetic UPI
  /// sender and reuse the exact same parser as inbox SMS. Returns null if no
  /// completed debit/credit can be extracted. Replaces the old cloud /ingest/text.
  static Expense? parsePastedText(String text) {
    // A sender containing "upi" passes _isBankSms so the normal parser runs;
    // everything downstream (debit/credit/amount/merchant) is identical.
    return parseExpense(body: text, sender: 'pasted-upi', date: DateTime.now());
  }

  // Parses a single SMS body — returns null if it doesn't look like a debit.
  // Universal across Indian banks: detects the amount + merchant from the many
  // phrasings used by SBI, HDFC, ICICI, Axis, Kotak, IDFC, AU, IDBI, etc.
  // Static so it runs in the background isolate (no Telephony instance needed).
  static Expense? parseExpense({
    required String body,
    required String sender,
    required DateTime date,
  }) {
    if (!_isBankSms(sender, body)) return null;
    if (_isNonTransaction(body)) return null; // OTP / declined / promo / failed

    // Money IN (salary, refunds, transfers received) -> income. Checked before
    // the debit path because some credit SMS also carry a debit verb ("Rs X
    // debited from <sender> ... credited to your A/c"); _isCredit is precise
    // enough not to fire on a debit whose PAYEE is "credited" (e.g. "ZOMATO
    // credited"), so genuine spends still fall through to the debit path.
    if (_isCredit(body)) {
      return _parseCredit(body: body, sender: sender, date: date);
    }

    if (!_isDebit(body)) return null;

    final amount = _extractAmount(body);
    if (amount == null || amount <= 0) return null;

    final isCard = _isCardTxn(body);
    final method = isCard ? 'card' : 'upi';
    final bank = _detectBankName(sender, body);

    // Merchant-less debits with a clear identity: card/bank fees -> Bills,
    // ATM cash -> Cash, plain bank transfers -> Transfer.
    final special = _specialDebit(body: body, amount: amount, date: date, bank: bank, isCard: isCard);
    if (special != null) return special;

    // Merchant: a VPA (merchant@bank) or a name from any bank phrasing
    // (trf to X / To X On / At X / UPI/.../X / Info: UPI/X / X credited).
    final vpa = _extractUpiId(body);
    final merchantText = _extractMerchant(body);

    final known = _matchKnownMerchant(text: merchantText, vpa: vpa);
    String? merchant = known;
    String? category = known != null ? _merchantCategories[known] : null;
    bool labeled = known != null;

    // Known person in contacts -> Personal, auto-labeled.
    if (merchant == null) {
      final payee = merchantText ?? _nameFromVpa(vpa);
      final contact = ContactsService.instance.matchContactName(payee);
      if (contact != null) {
        merchant = contact;
        category = 'Personal';
        labeled = true;
      }
    }

    // Fallbacks when not recognised.
    if (merchant == null) {
      if (merchantText != null && merchantText.isNotEmpty) {
        merchant = merchantText; // real but unrecognised merchant -> user/AI labels
        labeled = false;
      } else if (vpa != null) {
        merchant = vpa;
        labeled = false;
      } else if (isCard) {
        merchant = bank != null ? 'Card ($bank)' : 'Card payment';
        category = 'Other';
        labeled = true;
      } else {
        merchant = 'Unknown';
        labeled = false;
      }
    }

    return Expense(
      merchant: merchant,
      amount: amount,
      date: date,
      rawSms: body,
      upiId: vpa ?? merchantText,
      isLabeled: labeled,
      category: category,
      method: method,
    );
  }

  // --- Income (credit) parsing -------------------------------------------

  // Amount tied to a credit verb (mirrors _amountVerbRegex for debits) so we
  // grab the credited amount, not the trailing balance.
  static final _amountCreditVerbRegex = RegExp(
    r'(?:credited by|credited for|credited with|credited|received from|received|deposited|credit of)\s+(?:rs\.?|inr)?\s*([0-9,]+(?:\.[0-9]{1,2})?)',
    caseSensitive: false,
  );

  // Payer / source of an incoming payment, across bank phrasings.
  static final List<RegExp> _creditSourcePatterns = [
    RegExp(
        r'(?:transfer from|received from|from VPA|by VPA|from)\s+([A-Za-z0-9][A-Za-z0-9 &._@-]{1,40}?)(?:\s+Ref|\s+Refno|\s+on\b|\s+UPI\b|\.|,|\n|$)',
        caseSensitive: false),
  ];

  // Parses a money-IN SMS into an income Expense. Merchant is the payer/source
  // when we can find one, else "Income"; category is always Income, pre-labeled.
  static Expense? _parseCredit({
    required String body,
    required String sender,
    required DateTime date,
  }) {
    final amount = _extractCreditAmount(body);
    if (amount == null || amount <= 0) return null;

    final vpa = _extractUpiId(body);
    final source = _extractCreditSource(body) ?? _nameFromVpa(vpa);
    final merchant =
        (source != null && source.trim().isNotEmpty) ? source.trim() : 'Income';

    return Expense(
      merchant: merchant,
      amount: amount,
      date: date,
      rawSms: body,
      upiId: vpa,
      isLabeled: true,
      category: 'Income',
      method: 'upi',
      direction: 'credit',
    );
  }

  static double? _extractCreditAmount(String body) {
    final m = _amountCreditVerbRegex.firstMatch(body);
    if (m != null) {
      final v = double.tryParse(m.group(1)!.replaceAll(',', ''));
      if (v != null && v > 0) return v;
    }
    // Fallback: first currency amount in the message.
    final m2 = _amountRegex.firstMatch(body);
    if (m2 == null) return null;
    return double.tryParse(m2.group(1)!.replaceAll(',', ''));
  }

  static String? _extractCreditSource(String body) {
    for (final p in _creditSourcePatterns) {
      final m = p.firstMatch(body);
      if (m != null) {
        final s = m.group(1)!.trim();
        // Require letters — skip bare account/ref numbers.
        if (RegExp(r'[A-Za-z]{2,}').hasMatch(s)) return s;
      }
    }
    return null;
  }

  // True when an SMS looks like a bank debit (from a bank, has an amount, not a
  // non-transaction/credit) but our regex did NOT recognise the debit format —
  // a candidate for the on-device "Unrecognized" capture (never sent anywhere).
  static bool looksLikeUnparsedTxn(String sender, String body) {
    if (!_isBankSms(sender, body)) return false;
    if (_isNonTransaction(body) || _isCredit(body)) return false;
    if (_isDebit(body)) return false; // regex already handles these
    // Notices/ads that carry an amount but aren't actual spends.
    final b = body.toLowerCase();
    if (b.contains('mandate') ||
        b.contains('http') ||
        b.contains('click') ||
        b.contains('term plan') ||
        b.contains('buy a') ||
        b.contains("b'day") ||
        b.contains('insurance') ||
        b.contains('policy') ||
        b.contains('plan for') ||
        b.contains('loan') ||
        b.contains('offer') ||
        b.contains('upto ')) {
      return false;
    }
    return _extractAmount(body) != null;
  }

  // A bank debit the regex couldn't fully parse. We still capture the amount
  // (so the spend total stays correct) and keep the raw SMS on-device, marking
  // it unlabeled so it lands in the "Needs label" tray for one-tap
  // categorization — which trains the learning categorizer. This replaces the
  // old cloud LLM fallback: nothing is sent off the device.
  static Expense? _unrecognizedExpense({
    required String body,
    required String sender,
    required DateTime date,
  }) {
    if (!looksLikeUnparsedTxn(sender, body)) return null;
    final amount = _extractAmount(body);
    if (amount == null || amount <= 0) return null;
    return Expense(
      merchant: 'Unknown',
      amount: amount,
      date: date,
      rawSms: body,
      isLabeled: false, // -> shows in the Unrecognized / Needs-label tray
      category: null,
      method: _isCardTxn(body) ? 'card' : 'upi',
    );
  }

  // Merchant-name patterns across banks, tried in priority order.
  static final List<RegExp> _merchantPatterns = [
    // UPI ref lines: UPI/DR|CR|P2M|P2A/<ref>/<MERCHANT>/...  (AU, Axis)
    RegExp(r'UPI/(?:DR|CR|P2M|P2A)/\w+/([^/\n]+)', caseSensitive: false),
    // IDFC First: "Info: UPI/<MERCHANT>/<ref>"
    RegExp(r'Info:\s*UPI/([^/\n]+)/', caseSensitive: false),
    // SBI / PNB: "trf to <MERCHANT> Ref..." and spelled-out "transfer to / transferred to".
    RegExp(r'trf to\s+([A-Za-z0-9][A-Za-z0-9 &._-]{1,40}?)(?:\s+Refno|\s+Ref|\s+on\b|\.|,|\n|$)',
        caseSensitive: false),
    RegExp(
        r'transfer(?:red)?\s+to\s+([A-Za-z0-9][A-Za-z0-9 &._-]{1,40}?)(?:\s+Ref|\s+Refno|\.|,|\n|$)',
        caseSensitive: false),
    // IDBI UPI-AutoPay / mandate debit: "...debited ... towards <MERCHANT> for
    // Create Mandate AutoPay..." (also "towards <MERCHANT> on ..."). Scoped to
    // the "towards X for/on" phrasing so it captures NETFLIX, not the trailing
    // "-IDBI Bank" the AU \d{3,}-<name> pattern below would otherwise grab.
    RegExp(r'\btowards\s+([A-Za-z][A-Za-z0-9 &._-]{1,40}?)\s+(?:for|on)\b',
        caseSensitive: false),
    // HDFC: "...To <MERCHANT> On..."
    RegExp(r'\bTo\s+([A-Za-z][A-Za-z0-9 &._-]{1,40}?)\s+On\b', caseSensitive: false),
    // Card POS: "...At <MERCHANT> On..."
    RegExp(r'\bAt\s+([A-Za-z][A-Za-z0-9 &._-]{1,40}?)\s+On\b', caseSensitive: false),
    // ICICI / IDBI: "<MERCHANT> credited" — optionally preceded by a balance
    // ("; Bal Rs 196497.31 SOUTH SPICE CAF credited") which must be skipped.
    RegExp(
        r'(?:bal(?:ance)?[:.]?\s+(?:rs\.?|inr)?\s*[\d,.]+\s+)?([A-Za-z][A-Za-z0-9 &._-]{1,40}?)\s+credited',
        caseSensitive: false),
    // AU debit-card line: "...RDE-3180-70015742   -ZOMATO LTD\nBal..." — merchant
    // is the last segment after a ref number + dash, before the balance line.
    RegExp(r'\d{3,}\s*-\s*([A-Za-z][A-Za-z0-9 .&*]{2,40}?)\s*(?:\n|Bal\b|$)', caseSensitive: false),
    // Card POS "at <MERCHANT>" (intl txns: merchant then big-space/phone/country).
    RegExp(
        r'\bat\s+([A-Za-z][A-Za-z0-9 .&*]{2,40}?)(?:\s{2,}|\s+\+?\d{6,}|\s+on your\b|\s+from\b|\n|$)',
        caseSensitive: false),
  ];

  static String? _extractMerchant(String body) {
    for (final p in _merchantPatterns) {
      final m = p.firstMatch(body);
      if (m != null) {
        final s = m.group(1)!.trim();
        if (RegExp(r'[A-Za-z]{2,}').hasMatch(s)) return s;
      }
    }
    return null;
  }

  // Derives a human-ish name from a VPA prefix (e.g. "john.doe@oksbi" -> "john doe").
  static String? _nameFromVpa(String? vpa) {
    if (vpa == null) return null;
    final prefix = vpa.split('@').first;
    final name = prefix.replaceAll(RegExp(r'[._-]+'), ' ').trim();
    return name.isEmpty ? null : name;
  }

  // Excludes messages that look like debits but aren't actual money leaving:
  // OTPs, declined/failed payments, and promotional offers.
  static bool _isNonTransaction(String body) {
    final b = body.toLowerCase();
    return b.contains('otp') ||
        b.contains('one time password') ||
        b.contains('declined') ||
        b.contains('could not') ||
        b.contains('not been') ||
        b.contains('unsuccessful') ||
        b.contains('failed') ||
        b.contains('voucher') ||
        b.contains('reward unlocked') ||
        b.contains('cashback') ||
        b.contains('will be debited') ||
        b.contains('has been blocked') ||
        b.contains('is blocked') ||
        // Payment requests / collect requests — money has NOT left yet.
        b.contains('has requested') ||
        b.contains('requested money') ||
        b.contains('requested payment') ||
        b.contains('request money') ||
        b.contains('to pay using') ||
        b.contains('on approval') ||
        b.contains('on approving') ||
        // Scheduled autopay/mandate notices — future, not yet debited.
        b.contains('scheduled on') ||
        (b.contains('autopay') && b.contains('scheduled')) ||
        // UPI mandate setup/revoke notices (NOT executed autopay debits, which
        // legitimately say "... debited ... UPI Mandate").
        b.contains('mandate successfully') ||
        b.contains('mandate created') ||
        b.contains('mandate revoked') ||
        b.contains('mandate cancelled') ||
        // Promotional offers.
        b.contains('festival') ||
        b.contains('brings you') ||
        b.contains('shop karo') ||
        b.contains('% off') ||
        b.contains(' off on') ||
        b.contains('use code') ||
        b.contains('click here') ||
        b.contains('apply now') ||
        // Service / maintenance notices (not transactions).
        b.contains('maintenance alert') ||
        b.contains('scheduled maintenance') ||
        b.contains('planned maintenance') ||
        b.contains('system upgrade') ||
        b.contains('will be unavailable') ||
        b.contains('service disruption');
  }

  static bool _isCardTxn(String body) {
    final b = body.toLowerCase();
    return b.contains('cardtxn') ||
        b.contains('card txn') ||
        b.contains('-poi') ||
        b.contains('debit card') ||
        b.contains('credit card') ||
        b.contains('bank card') ||
        b.contains('card ending') ||
        b.contains('on your card') ||
        b.contains('pos ') ||
        RegExp(r'card\s+(?:no\.?\s*)?x+\d', caseSensitive: false).hasMatch(b);
  }

  static bool _isCardFee(String body) {
    final b = body.toLowerCase();
    return b.contains('card fee') ||
        b.contains('annual fee') ||
        b.contains('joining fee') ||
        b.contains('maintenance charge') ||
        b.contains('amc');
  }

  // Debits that have no real merchant but a clear identity, so they get a
  // sensible name + category instead of "Unknown".
  static Expense? _specialDebit({
    required String body,
    required double amount,
    required DateTime date,
    required bool isCard,
    String? bank,
  }) {
    final b = body.toLowerCase();
    Expense mk(String name, String cat) => Expense(
          merchant: name,
          amount: amount,
          date: date,
          rawSms: body,
          isLabeled: true,
          category: cat,
          method: isCard ? 'card' : 'upi',
        );

    // ATM cash withdrawal.
    if (b.contains('atm') &&
        (b.contains('withdrawn') || b.contains('withdrawal') || b.contains('cash wdl'))) {
      return mk('ATM Withdrawal', 'Cash');
    }

    // Card / bank fees & charges -> Bills.
    if (_isCardFee(body)) {
      return mk(bank != null ? 'Card Fee ($bank)' : 'Card Fee', 'Bills');
    }
    if (b.contains('sms_alert') ||
        b.contains('sms alert') ||
        b.contains('service charge') ||
        b.contains('convenience fee') ||
        b.contains('conv fee') ||
        b.contains('markup') ||
        b.contains('_charge_') ||
        RegExp(r'for\s+\w*charge', caseSensitive: false).hasMatch(b)) {
      return mk(bank != null ? 'Bank Charge ($bank)' : 'Bank Charge', 'Bills');
    }

    // Plain account-to-account transfer with no merchant -> Transfer.
    if (b.contains('mobile bkg') ||
        b.contains('mobile banking') ||
        b.contains('net banking') ||
        b.contains('netbanking') ||
        b.contains('thru neft') ||
        b.contains('via neft') ||
        b.contains('thru imps') ||
        b.contains('by transfer of') ||
        b.contains('debit by transfer') ||
        b.contains('credited to a/c no')) {
      return mk('Bank Transfer', 'Transfer');
    }

    return null;
  }

  // Recognises the bank from the SMS sender or body, for naming card payments.
  static const Map<String, String> _banks = {
    'idbi': 'IDBI',
    'aubank': 'AU',
    'au bank': 'AU',
    'hdfc': 'HDFC',
    'icici': 'ICICI',
    'sbi': 'SBI',
    'axis': 'Axis',
    'kotak': 'Kotak',
    'yesbank': 'Yes',
    'idfc': 'IDFC',
    'indusind': 'IndusInd',
    'rbl': 'RBL',
    'pnb': 'PNB',
    'canara': 'Canara',
    'federal': 'Federal',
    'bandhan': 'Bandhan',
  };

  static String? _detectBankName(String sender, String body) {
    final hay = '${sender.toLowerCase()} ${body.toLowerCase()}';
    for (final entry in _banks.entries) {
      if (hay.contains(entry.key)) return entry.value;
    }
    return null;
  }

  // Read existing SMS from inbox (for initial import). [sinceMs] optionally
  // limits how far back to look (epoch ms) — used by the first-run history
  // import to pull, say, the last 6 months instead of the entire inbox.
  Future<List<Expense>> importInboxExpenses({
    int maxMessages = 400,
    int? sinceMs,
  }) async {
    final messages = sinceMs == null
        ? await _telephony.getInboxSms(
            columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
          )
        : await _telephony.getInboxSms(
            columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
            filter:
                SmsFilter.where(SmsColumn.DATE).greaterThan(sinceMs.toString()),
            sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
          );
    return _parseMessages(messages.take(maxMessages));
  }

  /// Catch-up scan: parse only the inbox SMS that arrived after [sinceMs]
  /// (epoch ms). Run on app open/resume to self-heal transactions the
  /// background receiver missed — OEMs (Vivo especially) sometimes kill the
  /// receiver, and a missed SMS otherwise stays invisible until a full
  /// manual import.
  Future<List<Expense>> catchUpExpenses({required int sinceMs}) async {
    final messages = await _telephony.getInboxSms(
      columns: [SmsColumn.ADDRESS, SmsColumn.BODY, SmsColumn.DATE],
      filter: SmsFilter.where(SmsColumn.DATE).greaterThan(sinceMs.toString()),
      sortOrder: [OrderBy(SmsColumn.DATE, sort: Sort.DESC)],
    );
    return _parseMessages(messages);
  }

  Future<List<Expense>> _parseMessages(Iterable<SmsMessage> messages) async {
    final expenses = <Expense>[];
    for (final msg in messages) {
      final body = msg.body ?? '';
      final address = msg.address ?? '';
      final date = msg.date != null
          ? DateTime.fromMillisecondsSinceEpoch(msg.date!)
          : DateTime.now();

      // Parse on-device; anything that looks like a real debit but doesn't fully
      // parse is captured as an Unrecognized spend (never sent off-device).
      final expense = parseExpense(body: body, sender: address, date: date) ??
          _unrecognizedExpense(body: body, sender: address, date: date);
      if (expense != null) expenses.add(expense);
    }
    return expenses;
  }

  static bool _isBankSms(String address, String body) {
    final addr = address.toLowerCase();
    final b = body.toLowerCase();
    if (addr.contains('hdfc') || addr.contains('sbi') || addr.contains('icici') ||
        addr.contains('axis') || addr.contains('kotak') || addr.contains('idfc') ||
        addr.contains('yes') || addr.contains('paytm') || addr.contains('phonepe') ||
        addr.contains('bank') || addr.contains('upi') || addr.contains('bk')) {
      return true;
    }
    // Fallback: body mentions UPI or debit from bank account
    return b.contains('upi') || (b.contains('debited') && b.contains('a/c'));
  }

  // Money coming IN. Precise so it does NOT trip on a debit SMS that mentions
  // the payee being credited (ICICI "BLINKIT credited") or a transfer that says
  // "...debited... and credited to a/c no...". Also catches refunds/reversals.
  static bool _isCredit(String body) {
    final b = body.toLowerCase();
    final trimmed = b.trimLeft();
    // Reversal / refund (e.g. "Credited INR 500 ... UPI/DR-REV/...").
    if (b.contains('dr-rev') ||
        b.contains('debit reversal') ||
        b.contains('reversal') ||
        b.contains('refund')) {
      return true;
    }
    // A message that STARTS by announcing a credit is money in.
    if (trimmed.startsWith('credited')) return true;
    return b.contains('credited to your') ||
        b.contains('is credited') ||
        b.contains('credited with') ||
        b.contains('credited for') || // IDBI: "A/c credited for INR X thru UPI"
        b.contains('credited by') || // SBI: "A/c credited by Rs X transfer from"
        b.contains('received from') ||
        b.contains('received rs') ||
        b.contains('received inr') ||
        b.contains('deposited') ||
        b.contains('upi/cr/');
  }

  static bool _isDebit(String body) {
    final b = body.toLowerCase();
    return b.contains('debited') ||
        b.contains('debit') ||
        b.contains('upi/dr/') ||
        RegExp(r'\bdr\b').hasMatch(b) || // AU Bank: "Dr INR 217.00"
        b.contains('trf to') ||
        b.contains(' paid ') ||
        b.contains('payment of') ||
        b.contains('sent rs') ||
        b.contains('sent inr') ||
        b.contains(' sent ') ||
        b.contains('spent') ||
        b.contains('withdrawn');
  }

  static double? _extractAmount(String body) {
    // Prefer the amount tied to a debit verb (avoids grabbing the balance).
    final m1 = _amountVerbRegex.firstMatch(body);
    if (m1 != null) {
      final v = double.tryParse(m1.group(1)!.replaceAll(',', ''));
      if (v != null && v > 0) return v;
    }
    final m2 = _amountRegex.firstMatch(body);
    if (m2 == null) return null;
    return double.tryParse(m2.group(1)!.replaceAll(',', ''));
  }

  static String? _extractUpiId(String body) {
    for (final pattern in _upiPatterns) {
      final match = pattern.firstMatch(body);
      if (match != null) {
        final vpa = match.group(1)!;
        // Reject obvious email addresses embedded in regular text
        if (vpa.contains('.com') || vpa.contains('.in') || vpa.contains('.org')) {
          // Allow only if it looks like a VPA (short suffix like @oksbi, @ybl, @icici)
          final suffix = vpa.split('@').last.toLowerCase();
          if (suffix.length > 12) continue;
        }
        return vpa.toLowerCase();
      }
    }
    return null;
  }


  // Matches a known merchant from either the transaction merchant text or a VPA
  // prefix. Returns the canonical merchant name, or null if unrecognised.
  static String? _matchKnownMerchant({String? text, String? vpa}) {
    final candidates = <String>[];
    if (text != null) {
      candidates.add(text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''));
    }
    if (vpa != null) {
      candidates.add(
        vpa.split('@').first.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), ''),
      );
    }

    for (final c in candidates) {
      if (c.isEmpty) continue;
      if (_knownMerchants.containsKey(c)) return _knownMerchants[c];
      for (final entry in _knownMerchants.entries) {
        if (c.contains(entry.key)) return entry.value;
      }
    }
    return null;
  }

  static String categoryFor(String merchant) {
    return _merchantCategories[merchant] ?? 'Other';
  }

  static List<String> get allCategories => const [
        'Food',
        'Grocery',
        'Shopping',
        'Transport',
        'Entertainment',
        'Personal',
        'Transfer',
        'Bills',
        'Health',
        'Fuel',
        'Cash',
        'Other',
      ];
}
