# ADR-012: Android Release Signing and CI Release Builds

## Status
**Accepted** — 2026-10-03. Approved by the project owner via the seller-app audit remediation request.

## Context
* **SA-AND-001:** `seller-app/android/app/build.gradle.kts` signed release builds with the Android debug key. Debug-signed APKs cannot be published to Play, cannot be upgraded by a properly signed build, and anyone with the public debug key could ship an "update".
* **SA-SEC-002:** a staging seller credential was committed in 0abdaeb (`scripts/seed-legitimate-staging-drop.mjs`) and nothing scanned new commits for secrets.
* **SA-CI-001 (partial):** CI used an unpinned Flutter version.

## Decision
1. Release builds are signed only with the owner's upload key from `seller-app/android/key.properties` (gitignored) or the env vars `LIVEDROP_KEYSTORE_PATH`, `LIVEDROP_KEYSTORE_PASSWORD`, `LIVEDROP_KEY_ALIAS`, `LIVEDROP_KEY_PASSWORD`. Without them the release task fails with a clear `GradleException`. `scripts/build-seller-apk.ps1` follows the same rule.
2. `seller-app-ci.yml`: pull requests run analyze, test and a debug build. Push to main and manual dispatch also run a release job that decodes `ANDROID_KEYSTORE_BASE64` into the runner temp directory, builds a signed AAB and APK, fails if either is signed with the debug certificate or does not match `vars.ANDROID_RELEASE_CERT_SHA256` (when set), and deletes the keystore. Without the secrets the job is skipped with a notice.
3. Flutter is pinned to 3.41.6 in CI.
4. `secret-scan.yml` runs gitleaks (`.gitleaks.toml`, redacted output) over the new commits of every push and pull request.
5. Owner runbooks: `docs/ops/android-release-signing.md`, `docs/ops/credential-rotation-runbook.md`.

## Consequences
* **Positive:** no debug-signed release can be produced by accident; release artefacts are reproducible in CI; new secrets are caught before merge.
* **Negative:** the owner must create and back up the keystore and add four GitHub secrets. Testers on debug-signed builds must uninstall once. The leaked credential is still in history until the owner rotates it and decides on a history purge.
* **Verification:** none automated yet. Neither the release job nor the gitleaks workflow has run, because both need the owner's GitHub secrets and a push. To be confirmed by the first CI run on main.
