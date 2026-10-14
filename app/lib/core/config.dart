/// Build-time configuration, injected with --dart-define-from-file=env/doctori.json
/// The publishable (anon) key is meant to live in the app: every table is protected
/// by Row Level Security on the server. Never put the service_role key here.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  /// Deep link used by email confirmation and password reset.
  /// Must be added in Supabase → Authentication → URL Configuration → Redirect URLs.
  static const authRedirect = 'com.doctori.app://login-callback';

  /// Sent with map tile requests (OpenStreetMap usage policy).
  static const appPackage = 'com.doctori.app';

  static bool get isConfigured => supabaseUrl.isNotEmpty && supabaseKey.isNotEmpty;
}
