/// The boundary between Klaro and the phone's SMS inbox.
///
/// This file deliberately imports NO plugin. It defines what Klaro needs from
/// an inbox in Klaro's own words; `telephony_sms_source.dart` is the only file
/// that knows those words are spoken to `another_telephony`.
///
/// Why bother: the parsing logic was always testable (hence the bank-format
/// suite), but the code that *fetches* messages was not — it called the plugin
/// directly, so no test could reach it. That is exactly where the "import read
/// the oldest messages and found nothing" bug lived, and why it survived 69
/// passing tests until it was found by hand on a real phone. With a seam here,
/// a fake inbox can be handed to [SmsService] in a plain unit test.
library;

/// One message from the inbox, reduced to the three things Klaro actually uses.
///
/// Not the plugin's `SmsMessage`: if that type leaked into the app, every caller
/// would be coupled to the plugin again and swapping or upgrading it would ripple
/// everywhere. Keeping our own type means a plugin change is a one-file change.
class InboxMessage {
  const InboxMessage({
    required this.sender,
    required this.body,
    required this.date,
  });

  /// Sender id as the network gives it, e.g. `AD-AUBANK-S`.
  final String sender;
  final String body;
  final DateTime date;
}

/// Read access to the SMS inbox, plus live delivery of new messages.
abstract class SmsSource {
  /// Ask the user for SMS access. True if Klaro may read the inbox.
  Future<bool> requestPermission();

  /// Deliver messages as they arrive while the app is in the foreground.
  void listenIncoming(void Function(InboxMessage) onMessage);

  /// Messages from the inbox, **newest first**, at most [limit] of them, and —
  /// when [since] is given — only those received after it.
  ///
  /// Newest-first and the limit are part of the CONTRACT, not an implementation
  /// detail, because the two together are load-bearing: [limit] exists to bound
  /// parse time on a large inbox, so it has to cut the OLDEST messages. An
  /// implementation that returns the platform's own order silently discards the
  /// user's most recent payments — which is precisely the bug this seam exists
  /// to make expressible in a test.
  Future<List<InboxMessage>> readInbox({DateTime? since, int limit});
}
