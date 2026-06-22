/// Compile-time build configuration (Phase 7.3 ingestion / distribution split).
///
/// Klaro ships in two distributions from one codebase:
///  • **power** (direct APK): SMS auto-capture ON — `--dart-define=KLARO_SMS=true`
///    (the default), built with the `full` Android flavor.
///  • **play** (Play Store): SMS OFF — `--dart-define=KLARO_SMS=false`, built with
///    the `play` flavor whose manifest declares no SMS permissions, so it passes
///    Google's SMS-permission review. Import happens via manual entry and the
///    paste/forward text-import path instead.
///
/// Gate every SMS-capture code path on [kSmsEnabled]. The on-device parser and
/// the shared category list are NOT gated — they're plain utilities with no
/// permission implication.
const bool kSmsEnabled = bool.fromEnvironment('KLARO_SMS', defaultValue: true);
