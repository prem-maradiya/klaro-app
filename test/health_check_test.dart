// The health report: what Klaro tells the user about its own condition.
//
// Every bug found on a real phone this week was a SILENT failure — a denied
// permission, a blocked read, an alert that never fired. Each one looked
// identical to "nothing to report". These tests pin down that the report says
// so out loud, and — just as important — that it does not cry wolf, because a
// screen full of scary warnings is one the user learns to ignore.
import 'package:flutter_test/flutter_test.dart';
import 'package:expense_tracker/services/health_check.dart';

/// Every answer a device could give, set directly.
class FakeProbe implements HealthProbe {
  FakeProbe({
    this.smsBuild = true,
    this.sms = true,
    this.notifications = true,
    this.background = true,
    this.reachable = true,
    this.signedIn = true,
    this.pendingChanges = 0,
    this.syncFailed = false,
  });

  @override
  final bool smsBuild;
  final bool sms;
  final bool notifications;
  final bool background;
  final bool reachable;
  @override
  final bool signedIn;
  @override
  final int pendingChanges;
  @override
  final bool syncFailed;

  @override
  Future<bool> get smsPermitted async => sms;
  @override
  Future<bool> get notificationsPermitted async => notifications;
  @override
  Future<bool> get backgroundAllowed async => background;
  @override
  Future<bool> get backendReachable async => reachable;
}

void main() {
  Future<HealthReport> report(FakeProbe p) => HealthReport.run(p);

  HealthCheck find(HealthReport r, String titlePart) =>
      r.checks.firstWhere((c) => c.title.contains(titlePart));

  group('a healthy phone', () {
    test('reports everything fine and offers no fixes', () async {
      final r = await report(FakeProbe());
      expect(r.overall, HealthStatus.ok);
      expect(r.problemCount, 0);
      expect(r.checks.every((c) => c.fix == null), isTrue,
          reason: 'nothing to fix means nothing to nag about');
    });
  });

  group('the failures that used to be invisible', () {
    test('blocked SMS access is called a problem, not left silent', () async {
      final r = await report(FakeProbe(sms: false));
      final c = find(r, 'bank messages');
      expect(c.status, HealthStatus.problem);
      expect(c.fix, isNotNull);
      expect(r.overall, HealthStatus.problem);
    });

    test('denied notifications say budget warnings will never arrive', () async {
      // The exact Android 13+ failure: the permission was never requested, so
      // every alert was dropped while the feature looked implemented.
      final r = await report(FakeProbe(notifications: false));
      final c = find(r, 'Alerts');
      expect(c.status, HealthStatus.problem);
      expect(c.detail, contains('never reach you'));
    });

    test('restricted background capture warns without overstating it', () async {
      // Nothing is lost — payments still appear on next open — so this is a
      // warning, not a problem. Overstating it would train the user to ignore
      // the report.
      final r = await report(FakeProbe(background: false));
      expect(find(r, 'while closed').status, HealthStatus.warning);
      expect(r.overall, HealthStatus.warning);
      expect(r.problemCount, 0);
    });
  });

  group('does not pile on', () {
    test('background is not mentioned when SMS is blocked outright', () async {
      // Advising a battery setting while Klaro cannot read messages at all is
      // noise on top of the real problem.
      final r = await report(FakeProbe(sms: false, background: false));
      expect(r.checks.any((c) => c.title.contains('while closed')), isFalse);
    });

    test('a build without SMS is not asked about SMS at all', () async {
      // The Play build has no SMS permission by design — flagging its absence
      // would report a fault that does not exist.
      final r = await report(FakeProbe(smsBuild: false, sms: false));
      expect(r.checks.any((c) => c.title.contains('bank messages')), isFalse);
      expect(r.overall, HealthStatus.ok);
    });

    test('sync is not reported when signed out', () async {
      final r = await report(FakeProbe(signedIn: false, pendingChanges: 5));
      expect(r.checks.any((c) => c.title.contains('Syncing')), isFalse);
    });
  });

  group('sync condition', () {
    test('being offline is reassuring, not alarming', () async {
      // Nothing is lost offline, and the user should be told that plainly.
      final r = await report(FakeProbe(reachable: false, pendingChanges: 3));
      final c = find(r, 'Syncing');
      expect(c.status, HealthStatus.warning);
      expect(c.detail, contains('safe on this phone'));
    });

    test('all backed up when there is nothing waiting', () async {
      final c = find(await report(FakeProbe()), 'Syncing');
      expect(c.status, HealthStatus.ok);
      expect(c.detail, contains('backed up'));
    });

    test('exhausted retries are surfaced even while online', () async {
      final r = await report(FakeProbe(syncFailed: true, pendingChanges: 2));
      expect(find(r, 'Syncing').status, HealthStatus.warning);
    });

    test('counts read naturally for one change', () async {
      final c = find(await report(FakeProbe(pendingChanges: 1)), 'Syncing');
      expect(c.detail, contains('1 change '));
    });
  });

  group('overall severity', () {
    test('the worst finding wins', () async {
      final r = await report(FakeProbe(notifications: false, background: false));
      expect(r.overall, HealthStatus.problem,
          reason: 'a problem outranks a warning');
    });
  });
}
