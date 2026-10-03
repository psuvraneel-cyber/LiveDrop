# Android release signing — seller app (SA-AND-001)

Owner action required: yes (create the key, store the secrets, enrol in Play App Signing).
Applies to: `seller-app/android/app/build.gradle.kts`, `.github/workflows/seller-app-ci.yml`,
`scripts/build-seller-apk.ps1`.

## 1. Why this matters

Android identifies an app by its package name **and** its signing certificate. The first APK a seller
installs fixes the certificate for that install: a later APK signed with a different key cannot be
installed as an update, only after an uninstall, and an uninstall deletes the app's local data (the
offline intake queue with unsynced photos, and the login session).

Until now the release build type was signed with the Android **debug** key and CI only produced a debug
APK. From this change on:

- A release build (`flutter build apk --release`, `flutter build appbundle`, `assembleRelease`,
  `bundleRelease`, `installRelease`) is signed **only** with the LiveDrop upload key. When the key is not
  configured, the build stops before any task runs with a message that explains how to configure it.
  There is no fallback to the debug key.
- Debug builds (`flutter build apk --debug`, `flutter run`) and `flutter test` need no key and are unchanged.
- CI builds a signed App Bundle + APK on pushes to `main` and on manual runs, and verifies the certificate.

## 2. Create the upload keystore (once)

Do this on a trusted machine, not in CI, and never inside the repository folder.

```bash
keytool -genkeypair -v \
  -keystore livedrop-upload-keystore.jks \
  -storetype PKCS12 \
  -keyalg RSA -keysize 4096 \
  -validity 10000 \
  -alias livedrop-upload \
  -dname "CN=LiveDrop Seller Upload Key, O=LiveDrop, C=IN"
```

- `keytool` ships with any JDK (Android Studio: `<Android Studio>/jbr/bin/keytool`).
- Use a long random **ASCII** password (PKCS12 keystores reject non-ASCII passwords). For PKCS12 the key
  password is the same as the keystore password; enter it for both secrets below.
- `-validity 10000` (about 27 years) is what Google Play expects for a key that must outlive the app.

### Back it up before anything else

Losing the keystore or its password means:

- **With Play App Signing** (section 6): the upload key can be reset through Play Console support; no
  user impact.
- **Without Play App Signing** (APKs shared directly with sellers, as in `docs/31-release-and-versioning.md`
  §2.2): the key you just created *is* the app's identity. If it is lost, no future version can be
  installed as an update; every seller would have to uninstall and lose unsynced data.

Store the `.jks` file and its password in the team password manager (as an attachment + secret) **and** in
one offline encrypted copy held by a second person. Record where in the completion log below. Never commit
it: `*.jks`, `*.keystore` and `key.properties` are gitignored in `seller-app/android/.gitignore`, and the
secret-scan workflow flags them (`.gitleaks.toml`, rule `android-signing-material`).

### Record the certificate fingerprint

```bash
keytool -list -v -keystore livedrop-upload-keystore.jks -alias livedrop-upload | grep 'SHA256:'
```

The SHA-256 fingerprint is public information (it is inside every signed APK). It is used to pin the
certificate in CI (section 3).

## 3. Configure GitHub (CI release job)

Repository → Settings → Secrets and variables → Actions.

| Kind | Name | Value |
|---|---|---|
| Secret | `ANDROID_KEYSTORE_BASE64` | the `.jks` file, base64-encoded on one line |
| Secret | `ANDROID_KEYSTORE_PASSWORD` | keystore password |
| Secret | `ANDROID_KEY_ALIAS` | `livedrop-upload` (or the alias you chose) |
| Secret | `ANDROID_KEY_PASSWORD` | key password (same as the keystore password for PKCS12) |
| Secret | `SUPABASE_URL` | production project URL (already used by the debug build) |
| Secret | `SUPABASE_ANON_KEY` | production anon key (already used by the debug build) |
| Variable | `ANDROID_RELEASE_CERT_SHA256` | the SHA-256 fingerprint from section 2 (colons and case do not matter) |
| Variable (optional) | `BUYER_BASE_URL` | public buyer site URL baked into the app (defaults to the app's built-in URL) |

Base64-encode the keystore without line breaks:

```bash
# Linux
base64 -w 0 livedrop-upload-keystore.jks > keystore.b64
# macOS
base64 -i livedrop-upload-keystore.jks | tr -d '\n' > keystore.b64
```

```powershell
# Windows PowerShell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("C:\secure\livedrop-upload-keystore.jks")) |
  Set-Content -NoNewline keystore.b64
```

With the GitHub CLI (it prompts for values that are not piped, so they do not land in shell history):

```bash
gh secret set ANDROID_KEYSTORE_BASE64 < keystore.b64
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS --body livedrop-upload
gh secret set ANDROID_KEY_PASSWORD
gh variable set ANDROID_RELEASE_CERT_SHA256 --body "<SHA-256 fingerprint>"
rm keystore.b64   # Windows: Remove-Item keystore.b64
```

Optional but recommended: Settings → Environments → `android-release` (the release job uses this
environment; GitHub creates it on the first run). Add *Deployment branches: main* and, if you want a
human gate, *Required reviewers*. You may also move the four `ANDROID_*` secrets into this environment
so only the release job can read them.

### What CI does

`.github/workflows/seller-app-ci.yml`

| Job | When | What |
|---|---|---|
| `validate-flutter` | every push to main/master/feat/fix branches, pull requests, manual | Flutter **3.41.6** (pinned, verified), `flutter analyze`, `flutter test`, debug APK (staging config; no secrets for pull requests from forks), artifact kept 7 days |
| `release-android` | push to `main`, manual run (`workflow_dispatch`) | If `ANDROID_KEYSTORE_BASE64` is not set: skipped with a notice. Otherwise: decodes the keystore into the runner temp dir, checks keystore/alias, writes `key.properties`, builds `app-release.aab` and `app-release.apk` with `APP_ENV=production`, verifies the signature (fails on the Android debug certificate, on APK/AAB certificate mismatch, on a mismatch with `ANDROID_RELEASE_CERT_SHA256`, and on a debuggable APK), uploads both (30 days) and deletes the keystore and `key.properties` |

`versionCode` = the workflow run number (or the `build_number` input of a manual run); `versionName`
comes from `pubspec.yaml`. Every upload to Play needs a higher `versionCode` than the last one; if you
ever built a higher number elsewhere, start a manual run with a larger `build_number`.

## 4. Local release builds

Create `seller-app/android/key.properties` (gitignored):

```properties
storeFile=C:/secure/livedrop-upload-keystore.jks
storePassword=<keystore password>
keyAlias=livedrop-upload
keyPassword=<key password>
```

- `storeFile`: absolute path recommended. A relative path is resolved against `seller-app/android/`.
- The file is read with `java.util.Properties`: on Windows use forward slashes or double backslashes
  (`C:\\secure\\...`); a single backslash is an escape character.
- Alternative without a file: set `LIVEDROP_KEYSTORE_PATH`, `LIVEDROP_KEYSTORE_PASSWORD`,
  `LIVEDROP_KEY_ALIAS`, `LIVEDROP_KEY_PASSWORD` in the environment. `key.properties` wins when both exist.

Then:

```powershell
.\scripts\build-seller-apk.ps1 -CheckSigningOnly         # only checks the configuration
.\scripts\build-seller-apk.ps1 -AppBundle -BuildNumber 12  # analyze, test, signed APK + AAB, certificate check
```

The script refuses to start when signing is not configured, and fails if an artifact turns out to be signed
with the Android debug certificate. Without a key you can still build `flutter build apk --debug` for testing.

## 5. Verify any APK or App Bundle by hand

```bash
# APK (Android SDK build-tools)
apksigner verify --print-certs app-release.apk
# AAB or APK (any JDK)
keytool -printcert -jarfile app-release.aab
```

The signer must be your upload certificate (`CN=LiveDrop Seller Upload Key, ...`, SHA-256 as recorded),
never `CN=Android Debug, O=Android, C=US`.

## 6. Enrol in Play App Signing (recommended)

1. Play Console → *Create app* (package `store.livedrop.seller_app`).
2. *Test and release* → *App integrity* → *App signing*: choose **Let Google manage and protect your app
   signing key** (Google generates the app signing key; your keystore becomes the *upload* key).
3. Upload the first `app-release.aab` from the CI artifact to an **Internal testing** track and add the
   sellers' Google accounts as testers. Updates then install over the previous version.
4. Copy the *App signing key certificate* SHA-256 shown on the App signing page into the team notes: APKs
   installed from Play carry that certificate, not the upload certificate.
5. If the upload key is lost or leaked: Play Console → App signing → *Request upload key reset*.

## 7. Moving existing testers off debug-signed builds

Any seller who installed an APK built before this change has a debug-signed app. The first release-signed
build cannot update it in place:

1. Make sure the seller's intake queue is empty (Products screen shows no *Syncing*/*Failed* items).
2. Uninstall the old app, install the release build (from Play internal testing or the CI artifact), log in.

## 8. Completion record

| Step | Done by | Date (UTC) | Notes (never paste secrets) |
|---|---|---|---|
| Upload keystore created (alias, validity) | | | |
| Keystore + password backed up (password manager entry name; offline copy holder) | | | |
| `ANDROID_*` secrets and `ANDROID_RELEASE_CERT_SHA256` set | | | |
| `android-release` environment protection configured (optional) | | | |
| First CI release run green (run URL) | | | |
| Play App Signing enrolled; app signing certificate SHA-256 recorded | | | |
| Existing testers migrated (section 7) | | | |
