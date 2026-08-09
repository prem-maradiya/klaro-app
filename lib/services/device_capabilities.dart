/// The real [HealthProbe]: asks this phone, right now, what Klaro is allowed
/// to do.
///
/// The only file that touches permission APIs, so version-specific behaviour is
/// contained here rather than assumed across the app. Deliberately asks the
/// device instead of branching on the Android version — a phone brand can
/// restrict something at any version, and what matters is whether the capability
/// works HERE, not which OS release this is.
library;

import 'package:permission_handler/permission_handler.dart';

import '../config/build_config.dart';
import 'api_service.dart';
import 'auth_service.dart';
import 'health_check.dart';

class DeviceCapabilities implements HealthProbe {
  const DeviceCapabilities({
    required this.pendingChanges,
    required this.syncFailed,
  });

  /// Passed in rather than read from the provider, so this stays a plain
  /// description of the device and does not reach into app state.
  @override
  final int pendingChanges;

  @override
  final bool syncFailed;

  @override
  bool get smsBuild => kSmsEnabled;

  @override
  Future<bool> get smsPermitted => Permission.sms.isGranted;

  @override
  Future<bool> get notificationsPermitted => Permission.notification.isGranted;

  @override
  Future<bool> get backgroundAllowed =>
      Permission.ignoreBatteryOptimizations.isGranted;

  @override
  bool get signedIn => AuthService.instance.isSignedIn;

  @override
  Future<bool> get backendReachable async =>
      await ApiService.instance.testConnection() != ApiTestResult.unreachable;
}
