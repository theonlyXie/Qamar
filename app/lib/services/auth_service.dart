import 'package:supabase_flutter/supabase_flutter.dart';

/// Identity per spec_mvp.txt §29.1: Supabase anonymous sign-in for instant
/// start, then optional upgrade to Apple / Google / email OTP so the
/// profile survives a reinstall or device change. Phone OTP is explicitly
/// deferred in the spec.
///
/// Email is implemented because it works with nothing but the Supabase
/// project that already exists. Apple and Google need native entitlements and
/// OAuth client IDs that are not set up yet, so their buttons are not shown —
/// a sign-in button that silently does nothing is worse than no button.
abstract class Account {
  /// Starts linking an email to the current (anonymous) user, keeping the
  /// same id and therefore all of their data. Sends a six-digit code.
  Future<void> startLink(String email);
  Future<void> confirmLink({required String email, required String token});

  /// Signs in to an account that already exists, on a new device.
  Future<void> startSignIn(String email);
  Future<void> confirmSignIn({required String email, required String token});

  /// The email on the current session, once linked.
  String? get email;
  bool get isAnonymous;
}

class AuthService implements Account {
  final SupabaseClient _client;
  const AuthService(this._client);

  User? get currentUser => _client.auth.currentUser;

  @override
  bool get isAnonymous => currentUser?.isAnonymous ?? true;

  @override
  String? get email {
    final e = currentUser?.email;
    return (e == null || e.isEmpty) ? null : e;
  }

  /// Linking, not signing in: `updateUser` attaches the address to the
  /// anonymous user that is already signed in, so the profile, meals and
  /// wallet built up as a guest survive. Signing in with OTP instead would
  /// create a second identity and strand the first.
  @override
  Future<void> startLink(String email) async {
    await _client.auth.updateUser(UserAttributes(email: email));
  }

  @override
  Future<void> confirmLink({required String email, required String token}) async {
    await _client.auth.verifyOTP(type: OtpType.emailChange, email: email, token: token);
  }

  @override
  Future<void> startSignIn(String email) async {
    await _client.auth.signInWithOtp(email: email);
  }

  @override
  Future<void> confirmSignIn({required String email, required String token}) async {
    await _client.auth.verifyOTP(type: OtpType.email, email: email, token: token);
  }

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

  /// Apple and Google, when the native side is ready.
  ///
  /// These are correct but unreachable from the UI: Apple needs the
  /// `sign_in_with_apple` package plus the Sign in with Apple entitlement, and
  /// Google needs `google_sign_in` plus an OAuth client ID per platform.
  /// Until that setup exists the buttons are not shown, rather than shown and
  /// wired to nothing.
  Future<void> linkApple({required String idToken, String? nonce}) async {
    await _client.auth.signInWithIdToken(provider: OAuthProvider.apple, idToken: idToken, nonce: nonce);
  }

  Future<void> linkGoogle({required String idToken, String? accessToken}) async {
    await _client.auth.signInWithIdToken(provider: OAuthProvider.google, idToken: idToken, accessToken: accessToken);
  }

  Future<void> signOut() => _client.auth.signOut();
}
