import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

// Loads the device contacts once and matches UPI payee names against them.
// Used to auto-categorize payments to people you know as "Personal".
class ContactsService {
  static final ContactsService instance = ContactsService._();
  ContactsService._();

  final List<_Contact> _contacts = [];
  bool _loaded = false;

  bool get isLoaded => _loaded;

  Future<void> initialize() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) return;

      final contacts = await FlutterContacts.getContacts(withProperties: false);
      _contacts.clear();
      for (final c in contacts) {
        final tokens = _tokenize(c.displayName);
        if (tokens.isNotEmpty) {
          _contacts.add(_Contact(c.displayName.trim(), tokens));
        }
      }
      _loaded = true;
    } catch (_) {
      // Permission denied or plugin error — feature simply stays off.
    }
  }

  /// Seed the matcher with names instead of reading the address book.
  ///
  /// The matching rules below are pure, but they were only reachable after a
  /// real device handed over real contacts — so the one thing worth testing
  /// (does a merchant ever get mistaken for a friend?) could not be tested at
  /// all. Only the LOAD needs the plugin, so only the load is stubbed here;
  /// wrapping the whole plugin would be indirection for a single call.
  @visibleForTesting
  void loadNamesForTest(List<String> names) {
    _contacts
      ..clear()
      ..addAll([
        for (final n in names)
          if (_tokenize(n).isNotEmpty) _Contact(n.trim(), _tokenize(n)),
      ]);
    _loaded = true;
  }

  // Returns the contact's display name if the payee name matches a contact,
  // else null. Matching is token-based and order-independent: a contact
  // matches when all tokens of the shorter name appear in the other name.
  String? matchContactName(String? payeeName) {
    if (!_loaded || payeeName == null) return null;
    final payeeTokens = _tokenize(payeeName);
    if (payeeTokens.isEmpty) return null;

    for (final c in _contacts) {
      if (_isMatch(c.tokens, payeeTokens)) return c.displayName;
    }
    return null;
  }

  // A contact matches a payee when its name tokens line up with the payee's.
  // Prefix-aware so bank-truncated names match (e.g. contact "Adil Deokar" vs
  // bank "Adil Rahul Deok"), and tolerant of extra middle names.
  static bool _isMatch(Set<String> contactTokens, Set<String> payeeTokens) {
    if (contactTokens.isEmpty || payeeTokens.isEmpty) return false;
    int matched = 0;
    for (final ct in contactTokens) {
      for (final pt in payeeTokens) {
        final prefixOk = ct.length >= 4 &&
            pt.length >= 4 &&
            (ct.startsWith(pt) || pt.startsWith(ct));
        if (ct == pt || prefixOk) {
          matched++;
          break;
        }
      }
    }
    // Short contact names must match fully; longer ones need >= 2 token hits.
    if (contactTokens.length <= 2) return matched >= contactTokens.length;
    return matched >= 2;
  }

  // Lowercase alphabetic tokens of length >= 3 (drops initials, honorifics noise).
  static Set<String> _tokenize(String name) {
    return name
        .toLowerCase()
        .split(RegExp(r'[^a-z]+'))
        .where((t) => t.length >= 3)
        .toSet();
  }
}

class _Contact {
  final String displayName;
  final Set<String> tokens;
  _Contact(this.displayName, this.tokens);
}
