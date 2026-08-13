import 'package:supabase_flutter/supabase_flutter.dart';

/// Identity per spec_mvp.txt §29.1: Supabase anonymous sign-in for instant
/// start, then optional upgrade to Apple / Google / email OTP so the
/// profile survives a reinstall or device change. Phone OTP is explicitly
/// deferred in the spec.
///
/// Not wired into the app yet — [AppState] starts every session as a local
/// guest with no auth call at all. Call [AuthService.ensureSignedIn] during
/// app startup once you're ready to back the app with real Supabase Auth,
/// then thread the resulting `userId` into the repositories in
/// lib/services/repositories.dart.
class AuthService {
  final SupabaseClient _client;
  const AuthService(this._client);

  User? get currentUser => _client.auth.currentUser;
  bool get isAnonymous => currentUser?.isAnonymous ?? true;

  /// Starts (or resumes) a session. Anonymous sign-in requires anonymous
  /// sign-ins to be enabled in the Supabase project's Auth settings.
  Future<User> ensureSignedIn() async {
    final existing = currentUser;
    if (existing != null) return existing;
    final res = await _client.auth.signInAnonymously();
    if (res.user == null) {
      throw StateError('Anonymous sign-in did not return a user');
    }
    return res.user!;
  }

  /// Upgrades the current anonymous session to a real Apple identity,
  /// preserving the same user_id (spec_mvp.txt: "Preserve anonymous user ID;
  /// controlled merge when identity already belongs to another account").
  /// Requires the `sign_in_with_apple` package and native entitlement setup
  /// — deliberately not added as a dependency until you're ready to wire it.
  Future<void> linkApple({required String idToken, String? nonce}) async {
    await _client.auth.signInWithIdToken(provider: OAuthProvider.apple, idToken: idToken, nonce: nonce);
  }

  /// Same shape for Google — requires the `google_sign_in` package and a
  /// configured OAuth client ID, added when you wire this up for real.
  Future<void> linkGoogle({required String idToken, String? accessToken}) async {
    await _client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken, accessToken: accessToken);
  }

  Future<void> sendEmailOtp(String email) async {
    await _client.auth.signInWithOtp(email: email);
  }

  Future<void> verifyEmailOtp({required String email, required String token}) async {
    await _client.auth.verifyOTP(type: OtpType.email, email: email, token: token);
  }

  Future<void> signOut() => _client.auth.signOut();
}
