import 'package:supabase_flutter/supabase_flutter.dart';
import '../config/supabase_config.dart';

/// Thin wrapper over Supabase Auth. The session (and its refresh) is persisted
/// by supabase_flutter; the access token it holds is the JWT the backend
/// verifies. Everything user-facing goes through here so screens never touch
/// the SDK directly.
class AuthService {
  static final AuthService instance = AuthService._();
  AuthService._();

  SupabaseClient get _client => Supabase.instance.client;
  GoTrueClient get _auth => _client.auth;

  Session? get session => _auth.currentSession;
  User? get currentUser => _auth.currentUser;
  bool get isSignedIn => _auth.currentSession != null;
  String? get email => _auth.currentUser?.email;

  /// The current access token (JWT) for the API's Authorization header, or null
  /// when signed out. supabase_flutter refreshes it in the background, so this
  /// is always reasonably fresh.
  String? get accessToken => _auth.currentSession?.accessToken;

  /// Emits on sign-in / sign-out / token refresh — drives the auth gate.
  Stream<AuthState> get onAuthStateChange => _auth.onAuthStateChange;

  Future<void> signIn(String email, String password) =>
      _auth.signInWithPassword(email: email.trim(), password: password);

  /// Creates the account and triggers Supabase's verification email. The user
  /// must confirm before they can sign in (email confirmation is enabled).
  Future<AuthResponse> signUp(String email, String password) =>
      _auth.signUp(email: email.trim(), password: password);

  /// Browser-based Google OAuth, returning to [SupabaseConfig.oauthRedirect].
  /// Requires the Google provider enabled in Supabase + the deep link
  /// registered (Android intent-filter).
  Future<bool> signInWithGoogle() => _auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: SupabaseConfig.oauthRedirect,
        authScreenLaunchMode: LaunchMode.externalApplication,
      );

  Future<void> sendPasswordReset(String email) =>
      _auth.resetPasswordForEmail(email.trim());

  Future<void> signOut() => _auth.signOut();
}
