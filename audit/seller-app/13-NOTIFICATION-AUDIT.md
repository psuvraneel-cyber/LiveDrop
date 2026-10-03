# 13 — Notifications / Background Execution Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | FCM, local notifications, foreground/background alerts, preferences, deep links, Android permissions, background execution |
| Executed | Dependency and manifest inspection; code search for messaging/notification APIs; Settings screen trace |
| Not executed | Device (no notifications exist to test) |

## 1. What exists

| Capability | Present? | Evidence |
|---|---|---|
| Firebase Cloud Messaging | **No** (`firebase_messaging` absent; no `google-services.json`) | `pubspec.yaml`, `android/app` |
| Local notifications | **No** (`flutter_local_notifications` absent) | `pubspec.yaml` |
| Foreground in-app alerts | Snackbars only for the seller's own actions; no alert for incoming events | Code |
| Background alerts | None | — |
| Payment-claim / order / reservation / shipping alerts | None | — |
| Notification preferences | Three switches ("New orders", "Payment claims", "Hold expiries") that only change local booleans | `seller_settings_screen.dart:31-35, 524-597` |
| Haptics/sound preference | Switch with no effect (haptics class has no enabled flag) | `boutique_haptics.dart` |
| Deep links (tap → screen) | None (no intent filters) | `AndroidManifest.xml:33-36` |
| `POST_NOTIFICATIONS` permission (Android 13+) | Not declared / requested | Manifest |
| Server-side triggers (Edge Function, DB webhook) | None (`supabase/functions` empty) | — |
| Background execution (WorkManager, foreground service) | None | — |

Verification items from the brief (arrives, actionable, opens correct screen, no duplicates, logout clears seller state) are **not applicable — nothing exists to verify**.

## 2. Operational consequences of the missing push
During a live the seller's phone shows Facebook/Instagram/YouTube (or the seller streams from one phone and manages from another). With no alerts:
1. **Payment claims wait unseen.** Buyers who paid see "waiting for boutique"; with the 24-hour window and the reaper, unverified claims eventually expire and the money disappears from the app (SA-PAY-003).
2. **Fake-UTR holds go unnoticed** for hours (SA-PAY-007).
3. **Late claims and refund obligations** are never surfaced (SA-PAY-004).
4. **Balance payments** for advance orders are not prompted (SA-ORD-006).
5. The Settings screen tells the seller alerts are on — false assurance (SA-UX-002).

## 3. Recommended minimal design
| Event (DB) | Who | Priority | Tap opens |
|---|---|---|---|
| `payment_attempts` → `awaiting_seller_verification` | seller of the drop | high (heads-up) | claim card |
| → `late_claim_pending_review` | seller | high | claim card (late) |
| claim window ≤ 2 h left | seller | high | claim card |
| new order (live drop) | seller | default (batched every N s during busy lives) | order |
| refund owed created | seller | high | exception center |
| intake sync failed (needs edit) | local notification | default | queue item |

Implementation sketch: database webhook or trigger → `pg_net`/Edge Function → FCM HTTP v1 with a per-seller device-token table (rotated on login, removed on logout); Android notification channels per class; `POST_NOTIFICATIONS` runtime request with rationale; App Links for routing (SA-AND-003). Throttle/aggregate order alerts during peaks to avoid spam.

## 4. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-NOT-001 | HIGH | P1 | No push/local notifications; fake toggles |
| SA-AND-003 | MEDIUM | P1 | No deep links for notification routing |
| SA-UX-002 | MEDIUM | P1 | No-op controls create false assurance |
| SA-PAY-003 | CRITICAL | P0 | Unseen claims expire (made likely by the missing alerts) |
