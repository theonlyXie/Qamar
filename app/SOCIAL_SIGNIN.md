# Google, Apple and Facebook sign-in

The app code is done. Each provider still needs credentials created with the
provider and pasted into Supabase — that is a dashboard job, not a code one,
and until it is done the button reports "not switched on yet on the server"
rather than failing silently.

## The redirect URL, first

Every provider comes back to the same place:

```
com.qamar.app://login-callback
```

It is already registered in `android/app/src/main/AndroidManifest.xml` and
`ios/Runner/Info.plist`, and it is `AuthService.redirectUrl` in code. Add it in
the dashboard under **Authentication → URL Configuration → Redirect URLs**. If
these three do not match exactly, the provider signs the user in and the app
never finds out.

## Google

1. Google Cloud console → APIs & Services → Credentials.
2. Create an **OAuth client ID** of type *Web application*. This is the one
   Supabase uses, even for a mobile app — the flow runs through Supabase's
   callback, not the device.
3. Authorised redirect URI:
   `https://<project>.supabase.co/auth/v1/callback`
4. Supabase → Authentication → Providers → Google: paste the client ID and
   secret, enable.
5. Configure the OAuth consent screen. Until it is verified, only accounts you
   list as test users can sign in.

## Apple

Apple is required, not optional: App Store review guideline 4.8 rejects an app
that offers Google or Facebook login without an equivalent privacy-preserving
one, and Sign in with Apple is what satisfies it.

1. Apple Developer → Certificates, Identifiers & Profiles.
2. Enable the **Sign In with Apple** capability on the `com.qamar.app` App ID.
3. Create a **Services ID** (e.g. `com.qamar.app.web`), enable Sign In with
   Apple on it, and set the return URL to
   `https://<project>.supabase.co/auth/v1/callback`.
4. Create a **Key** with Sign In with Apple enabled and download the `.p8`.
   It downloads exactly once.
5. Supabase → Providers → Apple: Services ID as the client ID, then the team
   ID, key ID and the `.p8` contents.

## Facebook

1. developers.facebook.com → create an app → add **Facebook Login**.
2. Valid OAuth redirect URI:
   `https://<project>.supabase.co/auth/v1/callback`
3. Supabase → Providers → Facebook: paste the app ID and app secret, enable.
4. The app must be taken out of Development mode before anyone outside your
   test users can sign in.

## What the app does with the result

A guest who taps a provider is linked with `linkIdentity`, so the meals,
profile and wallet built up before signing in keep the same user id. A user who
is already signed in elsewhere gets `signInWithOAuth`. The distinction matters:
using `signInWithOAuth` on a guest would mint a second user and strand the
first, which nobody notices until a week later when their history is gone.
