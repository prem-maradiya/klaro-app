/// Turns Klaro's silent failures into visible ones.
///
/// Every capability this app depends on can be switched off by the phone
/// without telling anyone: a denied permission, an OEM battery policy, an
/// Android version that made a permission stricter. The app then keeps looking
/// perfectly healthy while doing nothing — notifications that never arrive read
/// exactly like "I haven't overspent", and a blocked inbox reads exactly like
/// "I have no messages".
///
/// Rather than guess what a given Android version or phone brand does, this
/// asks the device what is actually true right now, and says so in plain words.
library;

import 'package:flutter/foundation.dart';

/// How healthy one capability is.
enum HealthStatus {
  /// Working.
  ok,

  /// Works, but degraded — worth knowing, nothing is being lost right now.
  warning,

  /// Broken: something the user expects Klaro to do is not happening.
  problem,
}

/// One line in the health report.
@immutable
class HealthCheck {
  const HealthCheck({
    required this.title,
    required this.detail,
    required this.status,
    this.fix,
  });

  final String title;

  /// What is true, in the user's words — not an error code.
  final String detail;
  final HealthStatus status;

  /// What the user can do about it, when there is something.
  final String? fix;
}

/// What the health report needs to know about the device and the app.
///
/// An interface so the report's RULES can be tested without a phone: the
/// interesting part is how states combine into advice, not how a permission is
/// read. The real implementation lives in `device_capabilities.dart`, the only
/// file that touches permission APIs.
abstract class HealthProbe {
  /// Whether this build captures SMS at all (the Play build does not).
  bool get smsBuild;

  Future<bool> get smsPermitted;
  Future<bool> get notificationsPermitted;

  /// False when the OS may kill background capture to save battery.
  Future<bool> get backgroundAllowed;

  /// Whether the backend answered just now.
  Future<bool> get backendReachable;

  /// Whether a signed-in account exists to sync to.
  bool get signedIn;

  /// Local changes not yet pushed.
  int get pendingChanges;

  /// True once retries have been exhausted and changes are still waiting.
  bool get syncFailed;
}

/// Builds the report. Pure rules over [HealthProbe] answers.
class HealthReport {
  const HealthReport._(this.checks);

  final List<HealthCheck> checks;

  /// The worst status present — what the Settings entry should show at a glance.
  HealthStatus get overall {
    if (checks.any((c) => c.status == HealthStatus.problem)) {
      return HealthStatus.problem;
    }
    if (checks.any((c) => c.status == HealthStatus.warning)) {
      return HealthStatus.warning;
    }
    return HealthStatus.ok;
  }

  int get problemCount =>
      checks.where((c) => c.status == HealthStatus.problem).length;

  static Future<HealthReport> run(HealthProbe probe) async {
    final checks = <HealthCheck>[];

    // --- Capture ---------------------------------------------------------
    if (probe.smsBuild) {
      final smsOk = await probe.smsPermitted;
      checks.add(HealthCheck(
        title: 'Reading bank messages',
        status: smsOk ? HealthStatus.ok : HealthStatus.problem,
        detail: smsOk
            ? 'Klaro can read your bank SMS on this phone.'
            : 'Klaro cannot read your bank messages, so payments will not be '
                'logged automatically.',
        fix: smsOk ? null : 'Allow SMS access for Klaro in your phone settings.',
      ));

      // Only meaningful once SMS access exists — otherwise it is noise on top
      // of a bigger problem.
      if (smsOk) {
        final bgOk = await probe.backgroundAllowed;
        checks.add(HealthCheck(
          title: 'Catching payments while closed',
          status: bgOk ? HealthStatus.ok : HealthStatus.warning,
          detail: bgOk
              ? 'Payments are captured even when Klaro is not open.'
              : 'Your phone may stop Klaro in the background. Payments would '
                  'then only appear the next time you open the app.',
          fix: bgOk
              ? null
              : 'Allow background activity for Klaro in your battery settings.',
        ));
      }
    }

    // --- Telling you things ----------------------------------------------
    final notifOk = await probe.notificationsPermitted;
    checks.add(HealthCheck(
      title: 'Alerts and budget warnings',
      status: notifOk ? HealthStatus.ok : HealthStatus.problem,
      detail: notifOk
          ? 'Klaro can alert you about new payments and budget limits.'
          : 'Notifications are switched off, so budget warnings will never '
              'reach you — even when you go over.',
      fix: notifOk ? null : 'Turn on notifications for Klaro.',
    ));

    // --- Sync -------------------------------------------------------------
    if (probe.signedIn) {
      final online = await probe.backendReachable;
      final pending = probe.pendingChanges;
      final stuck = probe.syncFailed;
      final plural = pending == 1 ? 'change' : 'changes';

      // Wording tracks the tick beside it. "Still to upload" next to a green
      // tick reads as a contradiction; uploading in progress is simply what a
      // healthy sync looks like mid-flight.
      checks.add(HealthCheck(
        title: 'Syncing to your account',
        status: !online || stuck ? HealthStatus.warning : HealthStatus.ok,
        detail: !online
            ? 'Cannot reach Klaro right now. Your data is safe on this phone '
                'and will sync when the connection returns.'
            : stuck
                ? '$pending $plural could not be uploaded yet. Nothing is lost '
                    '— Klaro keeps retrying.'
                : pending > 0
                    ? 'Uploading $pending $plural…'
                    : 'Everything is backed up to your account.',
        fix: online && !stuck ? null : 'Check your internet connection.',
      ));
    }

    return HealthReport._(checks);
  }
}
