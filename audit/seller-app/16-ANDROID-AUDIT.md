# 16 — Android / Mobile Reliability Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Manifest, permissions, lifecycle, back/process death, device classes, network, permissions denial, compatibility, keyboard, safe areas, screen sizes, accessibility, build/signing |
| Executed | Manifest/Gradle/CI review; `flutter analyze` (clean); widget-level tests on the host |
| **Not executed** | **Any physical device or emulator**: the Android SDK/emulator could not be installed (dl.google.com blocked from this environment) and no device was attached. Every runtime row below marked NOT TESTED needs the device plan in §4. |

## 1. Configuration

| Item | Value | Assessment |
|---|---|---|
| Application id | `store.livedrop.seller_app` | — |
| min/target/compile SDK | Flutter defaults (`flutter.minSdkVersion` etc.) | Pin explicitly for Play policy tracking |
| Signing | **release uses the debug key** (`build.gradle.kts:34-37`) | SA-AND-001 (P0) |
| CI artifact | `flutter build apk --debug` with staging URL/anon key, uploaded from a public repo | SA-CI-001 |
| Permissions | INTERNET, CAMERA, BLUETOOTH, BLUETOOTH_ADMIN, BLUETOOTH_CONNECT, BLUETOOTH_SCAN | Bluetooth unused (SA-AND-002); no POST_NOTIFICATIONS (no notifications exist) |
| Features | camera, autofocus `required=false` | Good (installs on camera-less devices) |
| Cleartext | `usesCleartextTraffic="true"` | SA-SEC-005 |
| Backup | default (allowed) | SA-SEC-006 |
| Exported components | `MainActivity` only (launcher) | OK |
| Intent filters | MAIN/LAUNCHER only — no deep links | SA-AND-003 |
| `<queries>` | https/http/whatsapp/tel/upi + WhatsApp packages | Correct for Android 11+ package visibility |
| Activity | `singleTop`, `adjustResize`, hardware accelerated, handles config changes | OK |

## 2. Runtime behaviour

| Topic | Code-level behaviour | Status |
|---|---|---|
| Orientation | Not locked; layouts are portrait-designed | NOT TESTED (SA-AND-006) |
| Lifecycle | Only the camera screen observes lifecycle; no refresh on resume anywhere else | PROVEN-CODE (SA-RT-002, SA-CQ-001) |
| Back button | Back on any tab exits the app; no confirm while live | PROVEN-CODE (SA-AND-006) |
| Process death | Tab state and in-memory forms (registration, intake sheet) lost; intake queue survives (cache dir); image_picker lost data not recovered | PROVEN-CODE / INFERRED |
| Background/foreground | No resume refresh; realtime reconnect library-managed | INFERRED |
| Low memory | Full-res bytes in memory during capture; up to 4 processed angles held; `Image.network` without `cacheWidth` in lists | INFERRED risk on 2–3 GB devices |
| Slow device | Pure-Dart JPEG decode/encode: 0.39–3.0 s on a dev Xeon (T24) → likely several seconds on Redmi 9A-class (budget 600 ms) | INFERRED (SA-PERF-003) |
| Poor network | Login 15 s timeout; no timeouts/retries elsewhere; silent empty states | PROVEN-CODE (SA-OBS-001) |
| Camera permission denied | Error text + gallery fallback; no settings deep link for permanently denied | NOT TESTED |
| Notification permission denied | N/A (no notifications) | — |
| Android version compatibility | Photo picker on 13+, package visibility declared | NOT TESTED |
| Keyboard | `adjustResize`; bottom sheets pad by `viewInsets`; price uses number keyboard | NOT TESTED on small screens |
| Safe areas | `SafeArea` used in shell, intake, inventory | OK by code |
| Screen sizes | Fixed paddings; 5-tab bottom bar with 11 px labels | NOT TESTED on 5" devices |
| Accessibility | ~3.8:1 contrast for muted text, 6 tooltips app-wide, no `Semantics` labels | SA-UX-003 |
| Printing | `printing` → Android print service / share sheet | NOT TESTED with thermal printers |
| External intents | WhatsApp (`whatsapp://` then `wa.me`), dialer, UPI, browser | NOT TESTED; country-code bug proven (T02) |

## 3. Release-engineering requirements before handing an APK to sellers
1. Create the upload/release keystore; store in CI secrets; sign release builds (SA-AND-001). The **first** distributed signature is permanent for that install base.
2. Build `--release` with explicit `SUPABASE_URL`, `SUPABASE_ANON_KEY`, `APP_ENV=production`, `BUYER_BASE_URL` (the PowerShell script does not pass `BUYER_BASE_URL`).
3. Version codes per build; distribute through Play internal testing (update path, crash reports via Play vitals until a crash SDK exists).
4. Remove unused permissions and cleartext; disable backup or exclude shared prefs.

## 4. Physical device validation plan (brief section 37) — to run before real sellers
Devices: one low-end (≈2–3 GB RAM, Android 11–12, e.g. Redmi 9A/10A class) and one mid-range (Android 14). Record results in `audit/seller-app/evidence/device/` with screen recordings.

| # | Test | Pass criteria |
|---|---|---|
| D1 | Cold launch (release build) | < 2.5 s to login/home (docs/22) |
| D2 | Login valid/invalid, airplane mode | Correct messages; no hang |
| D3 | Navigation through all tabs, Back on each tab | No unexpected exit during a live (after fix) |
| D4 | Product intake ×10 in a row, single angle | < 30 s per item; no frame freezes; queue reaches 0 |
| D5 | Intake with 4 angles, 12 MP camera | Compression time per angle recorded; no OOM |
| D6 | Camera permission denied / permanently denied | Clear guidance + gallery fallback |
| D7 | Notification shade, incoming call, app switch during intake | Preview recovers; no "used after dispose" |
| D8 | Image upload on throttled 3G; airplane mode mid-upload; kill app; relaunch | Items resume and complete without duplicates |
| D9 | Drop creation → go live → copy/share link → open on another phone | Buyer page matches (title, products, prices, images, availability) |
| D10 | Order receipt during a live (buyer on second phone) | Visible within 2 s (after realtime fix) |
| D11 | Payment claim → verification → buyer page update | State consistent on both sides |
| D12 | Background 10 min, return | Data refreshes; channel resubscribed |
| D13 | Network loss 30 s during verify | No double action; clear outcome |
| D14 | Keyboard on 5" screen (price, tracking, search fields) | Save buttons reachable |
| D15 | Label print to a 4×6 thermal printer and PDF share | Correct size; scannable barcode only with a real AWB |
| D16 | WhatsApp/dial/UPI intents incl. numbers starting 91 | Correct recipient (after fix) |
| D17 | Logout, login as another seller on the same phone | No data or queue crossover |
| D18 | Large font / TalkBack spot check | Primary actions usable and labelled |

## 5. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-AND-001 | HIGH | P0 | Release signed with debug key; CI only produces debug APK |
| SA-AND-005 | MEDIUM | P1 | No physical-device validation evidence |
| SA-AND-003 | MEDIUM | P1 | No deep links / App Links |
| SA-AND-002 | MEDIUM | P2 | Unused Bluetooth permissions |
| SA-AND-004 | LOW | P2 | Camera lifecycle needs device validation |
| SA-AND-006 | LOW | P2 | Back exits app; lost picker data; no orientation lock |
| SA-SEC-005 | LOW | P2 | Cleartext traffic allowed |
| SA-SEC-006 | LOW | P2 | Session included in backups |
