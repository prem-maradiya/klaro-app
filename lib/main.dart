import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/build_config.dart';
import 'config/supabase_config.dart';
import 'providers/expense_provider.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/budget_service.dart';
import 'services/notification_service.dart';
import 'services/sms_service.dart';
import 'services/telephony_sms_source.dart';
import 'theme/klaro.dart';

// Error tracking (Phase 7.5). Compiled in via --dart-define=SENTRY_DSN=...;
// empty (the default) means Sentry is off and the app runs normally.
const String _sentryDsn = String.fromEnvironment('SENTRY_DSN');

void main() {
  if (_sentryDsn.isEmpty) {
    _bootstrap();
  } else {
    SentryFlutter.init(
      (options) {
        options.dsn = _sentryDsn;
        options.environment = const String.fromEnvironment(
          'SENTRY_ENVIRONMENT',
          defaultValue: 'production',
        );
        // Finance app: never attach PII (request bodies, user data).
        options.sendDefaultPii = false;
        options.tracesSampleRate = 0;
      },
      appRunner: _bootstrap,
    );
  }
}

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Auth + accounts: restores any persisted session and refreshes its token.
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  await ApiService.instance.init();

  // Composition root: this is the one place that decides WHICH inbox Klaro
  // reads. Everything downstream depends only on the plugin-free SmsSource
  // contract, so tests can hand it a fake and the no-SMS (Play) build simply
  // never wires one up.
  if (kSmsEnabled) {
    SmsService.instance.configureSource(TelephonySmsSource());
  }

  await NotificationService.instance.initialize();
  // Loads the cached budgets instantly; refreshes from the backend async.
  await BudgetService.instance.initialize();
  runApp(
    ChangeNotifierProvider(
      create: (_) => ExpenseProvider(),
      child: const KlaroApp(),
    ),
  );
}

class KlaroApp extends StatelessWidget {
  const KlaroApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Klaro',
      debugShowCheckedModeBanner: false,
      theme: Klaro.theme(),
      home: const SplashScreen(),
    );
  }
}
