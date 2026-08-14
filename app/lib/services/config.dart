/// Runtime configuration for real backend/AI/payment integrations.
///
/// The app runs entirely offline by default — [AppState] (lib/state/app_state.dart)
/// is a faithful, self-contained port of the prototype's mock logic and needs
/// no network access to demonstrate every screen and flow. Everything in
/// lib/services/ is the integration *seam* for wiring real infrastructure —
/// present, typed, and ready to fill in, but not exercised by the UI yet.
/// Flip [useSupabase] once real credentials are supplied (see app/README.md)
/// and wire a repository-backed AppState variant before shipping.
class QamarConfig {
  QamarConfig._();

  /// Shown on the You screen so a tester can tell at a glance which build is
  /// on the phone. Keep in step with `version:` in pubspec.yaml — reading the
  /// real value at runtime would mean adding package_info_plus, which is not
  /// worth a dependency for one label.
  static const buildLabel = '0.7.0 (7)';

  /// Supplied via --dart-define=SUPABASE_URL=... at build time. Never commit
  /// real values — this file only reads them from the environment.
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Base URL of the server-side AI gateway (Edge Function or equivalent).
  /// Per spec_mvp.txt §29.1: "No API key or model credential is shipped in
  /// the app; all AI requests pass through the server gateway" — the app
  /// never holds an OpenAI/etc key directly.
  static const aiGatewayUrl = String.fromEnvironment('AI_GATEWAY_URL');

  /// Public site. The store listings require reachable privacy and support
  /// URLs, and the app must link to the same terms the subscription is sold
  /// under.
  static const site = 'https://dr-qamar.com';
  static const privacyUrl = '$site/privacy';
  static const termsUrl = '$site/terms';
  static const supportUrl = '$site/support';
  static const deleteDataUrl = '$site/delete-account';

  static bool get useSupabase => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
  static bool get useAiGateway => aiGatewayUrl.isNotEmpty;
}
