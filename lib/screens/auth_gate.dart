import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import 'home_screen.dart';
import 'login_screen.dart';

/// Decides what the app shows based on auth state. Rebuilds on sign-in /
/// sign-out / token refresh, so logging in or out swaps the screen with no
/// manual navigation.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: AuthService.instance.onAuthStateChange,
      builder: (context, _) {
        return AuthService.instance.isSignedIn
            ? const HomeScreen()
            : const LoginScreen();
      },
    );
  }
}
