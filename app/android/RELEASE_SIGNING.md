# Release signing

The Play Store identifies an app by the key it was signed with. An APK signed
with the debug key cannot ever be replaced by one signed with the real key, so
this has to be right before the first upload — not after.

Nothing here belongs in git. `android/key.properties`, `*.jks` and `*.keystore`
are already gitignored; keep the keystore file itself outside the repository.

## 1. Create the keystore

Once, on a machine you control. Back it up somewhere you will still have in
five years — losing it means losing the ability to update the app at all.

```sh
keytool -genkey -v \
  -keystore ~/qamar-upload-key.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias qamar
```

## 2. Point the build at it

Create `android/key.properties` (this file, not the keystore, lives beside the
project):

```properties
storePassword=<the store password you just chose>
keyPassword=<the key password you just chose>
keyAlias=qamar
storeFile=/absolute/path/to/qamar-upload-key.jks
```

## 3. Build

```sh
flutter build appbundle --release      # what Play wants
flutter build apk --release --split-per-abi   # for direct install
```

The build logs a warning and falls back to the debug key when
`key.properties` is missing, so a release build never silently produces an
unpublishable artifact.

## Play App Signing

Google re-signs uploads with a key it holds. The key above is then the *upload*
key: if it is ever compromised you can ask Google to reset it, which is why it
is worth enrolling. The app's identity on the Store stays the same either way.
