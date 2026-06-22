/// Supabase project connection (Phase 7). The anon key is a *publishable* key —
/// safe to ship in the app; per-user data is protected by RLS + the API's
/// per-user scoping, not by hiding this key.
class SupabaseConfig {
  static const String url = 'https://mcfsanvdokuiwijqbbmy.supabase.co';

  static const String anonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1jZnNhbnZkb2t1aXdpanFiYm15Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODE5MTQ5MjQsImV4cCI6MjA5NzQ5MDkyNH0.oc9BQ7Ouk6HEnT1e6Uc8YGwU3lovBIg9bUUHvkYxaIM';

  /// Deep link the Google OAuth flow returns to. Must be registered as an
  /// Android intent-filter AND added to Supabase Auth → URL Configuration →
  /// Redirect URLs.
  static const String oauthRedirect = 'io.supabase.klaro://login-callback/';
}
