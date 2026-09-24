import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';

/// The one-tap sign-in providers.
///
/// Apple is not optional once Google or Facebook is offered: App Store review
/// guideline 4.8 requires an equivalent privacy-preserving login wherever a
/// third-party one is available, and Sign in with Apple is what satisfies it.
enum OAuthChoice { google, apple, facebook }

/// Identity per spec_mvp.txt §29.1: Supabase anonymous sign-in for instant
/// start, then optional upgrade to Apple / Google / Facebook / email OTP so
/// the profile survives a reinstall or device change. Phone OTP is explicitly
/// deferred in the spec.
///
/// Every one of these is a real call. What they still need is configuration
/// in the Supabase dashboard — a client ID and secret per provider — without
/// which the provider returns an error the app surfaces rather than hides.
abstract class Account {
  /// One-tap sign-in. Opens the provider in a browser tab and returns as soon
  /// as it has been launched; completion arrives on [changes], because the
  /// user leaves the app and comes back through a deep link.
  Future<void> startOAuth(OAuthChoice provider);

  /// Starts linking an email to the current (anonymous) user, keeping the
  /// same id and therefore all of their data. Sends a six-digit code.
  Future<void> startLink(String email);
  Future<void> confirmLink({required String email, required String token});

  /// Signs in to an account that already exists, on a new device.
  Future<void> startSignIn(String email);
  Future<void> confirmSignIn({required String email, required String token});

  /// Signs in with a password, which sends no email at all.
  ///
  /// Every other route here depends on the project's SMTP server being able to
  /// deliver a message. When it cannot — and right now it cannot, the server
  /// answers `535 Invalid username` and Supabase returns a 500 — a code that
  /// never arrives is the end of the road. This one does not ask anybody to
  /// send anything, which is precisely why it exists.
  Future<void> signInWithPassword({required String email, required String password});

  /// Sets or replaces the password on the account already signed in.
  ///
  /// Does not send mail either: changing a password is not a change of
  /// address, and Supabase only mails for the latter.
  Future<void> setPassword(String password);

  /// Fires whenever the signed-in identity changes — including when the user
  /// returns from a provider's browser tab, which is the only way the app
  /// learns that an OAuth flow succeeded.
  Stream<void> get changes;

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

  /// Where the provider sends the browser back to. Registered as an intent
  /// filter on Android and a URL type on iOS; Supabase must also list it under
  /// Authentication → URL Configuration → Redirect URLs, or the provider
  /// refuses the callback.
  static const redirectUrl = 'com.qamar.app://login-callback';

  static OAuthProvider _provider(OAuthChoice c) => switch (c) {
        OAuthChoice.google => OAuthProvider.google,
        OAuthChoice.apple => OAuthProvider.apple,
        OAuthChoice.facebook => OAuthProvider.facebook,
      };

  @override
  Stream<void> get changes => _client.auth.onAuthStateChange;

  /// One-tap sign-in, preserving the guest's data where possible.
  ///
  /// An anonymous user gets `linkIdentity`, which attaches the provider to the
  /// id they already have — so the meals, profile and wallet they built up
  /// before signing in survive. `signInWithOAuth` would mint a second user and
  /// strand the first, which is the failure people notice a week later when
  /// their history is gone.
  @override
  Future<void> startOAuth(OAuthChoice provider) async {
    final p = _provider(provider);
    if (isAnonymous && currentUser != null) {
      await _client.auth.linkIdentity(p, redirectTo: redirectUrl);
      return;
    }
    await _client.auth.signInWithOAuth(p, redirectTo: redirectUrl);
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

  @override
  Future<void> signInWithPassword({required String email, required String password}) async {
    await _client.auth.signInWithPassword(email: email, password: password);
  }

  @override
  Future<void> setPassword(String password) async {
    await _client.auth.updateUser(UserAttributes(password: password));
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
