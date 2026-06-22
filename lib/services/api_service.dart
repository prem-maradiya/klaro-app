import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/expense.dart';
import '../models/recurring.dart';
import 'auth_service.dart';

/// Result of probing a backend: reachable + key OK, reachable but the key is
/// rejected, or not reachable at all.
enum ApiTestResult { ok, unauthorized, unreachable }

/// Outcome of a text-import attempt (`/ingest/text`).
class IngestTextOutcome {
  const IngestTextOutcome({
    this.expense,
    this.noTransaction = false,
    this.unauthorized = false,
    this.unreachable = false,
  });

  /// The created (or deduped-existing) expense, when the import succeeded.
  final Expense? expense;

  /// Backend reached but found no completed transaction in the text (422).
  final bool noTransaction;
  final bool unauthorized;
  final bool unreachable;

  bool get ok => expense != null;
}

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  static const _prefsKey = 'backend_url';
  static const _prefsKeyApiKey = 'api_key';

  // Production cloud API (multi-tenant, Supabase-backed). Overridable in
  // Settings for local dev (http://localhost:8000 with `adb reverse`, or a LAN IP).
  static const String defaultUrl = 'https://klaro-api.vercel.app';

  String _baseUrl = defaultUrl;
  String get baseUrl => _baseUrl;

  String _apiKey = '';
  String get apiKey => _apiKey;

  /// Sent on every request. During the Phase 7 cutover we send BOTH:
  ///  • Authorization: Bearer (Supabase JWT) — required by the multi-tenant API;
  ///  • X-API-Key — used by the legacy single-tenant API.
  /// Each backend ignores the header it doesn't use, so one build works against
  /// either during the transition.
  Map<String, String> get _headers {
    final token = AuthService.instance.accessToken;
    return {
      'Content-Type': 'application/json',
      if (_apiKey.isNotEmpty) 'X-API-Key': _apiKey,
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Load the saved backend URL + API key. Call once at startup.
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.trim().isNotEmpty) {
      _baseUrl = saved.trim();
    }
    _apiKey = (prefs.getString(_prefsKeyApiKey) ?? '').trim();
  }

  /// Persist and apply a new backend URL.
  Future<void> setBaseUrl(String url) async {
    _baseUrl = _normalize(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, _baseUrl);
  }

  /// Persist and apply a new API key ('' = no auth).
  Future<void> setApiKey(String key) async {
    _apiKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKeyApiKey, _apiKey);
  }

  static String _normalize(String url) {
    var u = url.trim();
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    // strip trailing slash
    if (u.endsWith('/')) u = u.substring(0, u.length - 1);
    return u;
  }

  /// Probe a backend: /health checks reachability (never needs auth), then a
  /// tiny authenticated request checks the API key. Pass [url]/[apiKey] to
  /// test candidate values from the Settings screen without saving them.
  Future<ApiTestResult> testConnection({String? url, String? apiKey}) async {
    final target =
        (url == null || url.trim().isEmpty) ? _baseUrl : _normalize(url);
    final key = (apiKey ?? _apiKey).trim();
    try {
      final res = await http
          .get(Uri.parse('$target/health'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode != 200) return ApiTestResult.unreachable;
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      if (body['status'] != 'healthy') return ApiTestResult.unreachable;
    } catch (_) {
      return ApiTestResult.unreachable;
    }
    try {
      final res = await http.get(
        Uri.parse('$target/expenses?limit=1'),
        headers: {
          'Content-Type': 'application/json',
          if (key.isNotEmpty) 'X-API-Key': key,
        },
      ).timeout(const Duration(seconds: 8));
      if (res.statusCode == 401 || res.statusCode == 403) {
        return ApiTestResult.unauthorized;
      }
      return ApiTestResult.ok;
    } catch (_) {
      return ApiTestResult.unreachable;
    }
  }

  Future<Expense?> createExpense(Expense expense) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/expenses'),
            headers: _headers,
            body: jsonEncode(expense.toJson()),
          )
          .timeout(const Duration(seconds: 10));

      // 201 = created, 200 = server-side dedupe matched an existing row
      // (retry/re-import) — either way the returned row is authoritative.
      if (res.statusCode == 201 || res.statusCode == 200) {
        return Expense.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {
      // Backend not available — caller falls back to local storage
    }
    return null;
  }

  /// Delete an expense on the backend. Treats 404 as success (already gone).
  Future<bool> deleteExpense(int id) async {
    try {
      final res = await http
          .delete(Uri.parse('$_baseUrl/expenses/$id'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 204 || res.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  /// AI fallback parse for an SMS the on-device regex couldn't handle.
  /// Returns the structured result, or null if unreachable / not a transaction.
  Future<Map<String, dynamic>?> parseSms(String body, String sender) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/parse-sms'),
            headers: _headers,
            body: jsonEncode({'body': body, 'sender': sender}),
          )
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['is_transaction'] == true) return data;
      }
    } catch (_) {}
    return null;
  }

  /// Compliant non-SMS import: send pasted/forwarded transaction text (a UPI or
  /// receipt SMS, or a bank email) for the backend to parse + ingest. Returns the
  /// created/existing [Expense], or null with a reason in [IngestTextOutcome] via
  /// [ingestTextDetailed]. This is the import path on builds without SMS access.
  Future<Expense?> ingestText(String text, {String source = 'email'}) async {
    final outcome = await ingestTextDetailed(text, source: source);
    return outcome.expense;
  }

  /// Like [ingestText] but distinguishes "no transaction found" (422) from an
  /// unreachable backend, so the UI can show the right message.
  Future<IngestTextOutcome> ingestTextDetailed(String text,
      {String source = 'email'}) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/ingest/text'),
            headers: _headers,
            body: jsonEncode({'text': text, 'source': source}),
          )
          .timeout(const Duration(seconds: 20));
      if (res.statusCode == 201 || res.statusCode == 200) {
        return IngestTextOutcome(
          expense: Expense.fromJson(jsonDecode(res.body) as Map<String, dynamic>),
        );
      }
      if (res.statusCode == 422) {
        return const IngestTextOutcome(noTransaction: true);
      }
      if (res.statusCode == 401 || res.statusCode == 403) {
        return const IngestTextOutcome(unauthorized: true);
      }
    } catch (_) {}
    return const IngestTextOutcome(unreachable: true);
  }

  /// Backend expenses, optionally for one month (YYYY-MM, IST-bucketed).
  /// Null when unreachable — callers must NOT treat that as "no expenses"
  /// (the pull-reconciler would otherwise delete everything locally).
  Future<List<Expense>?> fetchExpenses({String? month, int limit = 500}) async {
    try {
      final params = <String, String>{'limit': '$limit'};
      if (month != null) params['month'] = month;
      final uri = Uri.parse('$_baseUrl/expenses')
          .replace(queryParameters: params);
      final res =
          await http.get(uri, headers: _headers).timeout(const Duration(seconds: 10));

      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        return list.map((e) => Expense.fromJson(e as Map<String, dynamic>)).toList();
      }
    } catch (_) {}
    return null;
  }

  /// All budgets as {category|'overall': monthly limit}. Null when unreachable
  /// (distinct from an empty map, which means "no budgets set").
  Future<Map<String, double>?> fetchBudgets() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/budgets'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final list = jsonDecode(res.body) as List<dynamic>;
        return {
          for (final b in list)
            (b['category'] as String): ((b['amount'] as num).toDouble()),
        };
      }
    } catch (_) {}
    return null;
  }

  Future<bool> putBudget(String category, double amount) async {
    try {
      final res = await http
          .put(
            Uri.parse('$_baseUrl/budgets/$category'),
            headers: _headers,
            body: jsonEncode({'amount': amount}),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Treats 404 as success (already gone), same as expense deletes.
  Future<bool> deleteBudget(String category) async {
    try {
      final res = await http
          .delete(Uri.parse('$_baseUrl/budgets/$category'), headers: _headers)
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 204 || res.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  /// Detected recurring payments (subscriptions / EMIs / bills) with predicted
  /// next-due dates, computed server-side. Null when unreachable (distinct from
  /// an empty list, which means "nothing detected yet").
  Future<RecurringSummary?> fetchRecurring() async {
    try {
      final res = await http
          .get(Uri.parse('$_baseUrl/recurring'), headers: _headers)
          .timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        return RecurringSummary.fromJson(
            jsonDecode(res.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
  }

  /// Stop a detected recurring payment from showing in upcoming ("I cancelled
  /// this subscription"). Keyed server-side on the normalized merchant.
  Future<bool> dismissRecurring(String merchant) async {
    try {
      final res = await http
          .post(
            Uri.parse('$_baseUrl/recurring/dismiss'),
            headers: _headers,
            body: jsonEncode({'merchant': merchant}),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// Undo a dismissal — the payment can be re-detected again.
  Future<bool> restoreRecurring(String merchant) async {
    try {
      final res = await http
          .delete(
            Uri.parse('$_baseUrl/recurring/dismiss/${Uri.encodeComponent(merchant)}'),
            headers: _headers,
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 204;
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateExpenseLabel({
    required int id,
    required String merchant,
    required String category,
    bool? inBudget,
    bool? budgetReview,
  }) async {
    try {
      final res = await http
          .patch(
            Uri.parse('$_baseUrl/expenses/$id'),
            headers: _headers,
            body: jsonEncode({
              'merchant': merchant,
              'category': category,
              'is_labeled': true,
              // Only sent when a budget decision is being synced, so plain label
              // edits never disturb a payment's budget inclusion.
              if (inBudget != null) 'in_budget': inBudget,
              if (budgetReview != null) 'budget_review': budgetReview,
            }),
          )
          .timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
