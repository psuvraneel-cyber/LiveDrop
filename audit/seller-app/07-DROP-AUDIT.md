# 07 — Drop Management Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Create → configure → add products → publish → public URL → buyer discovery → live → close (→ reopen) |
| Executed | SQL suite 12 (status transitions, slug, one-live rule, approval gate), suite 16 (close with claims), suite 13.10 (thresholds); code trace of drops screens, `EnvConfig`, buyer-web drop route/catalogue |
| Not executed | End-to-end run against a deployed buyer site and hosted DB |

## 1. Flow as implemented

| Step | Seller app | Server | Buyer web |
|---|---|---|---|
| Create | `CreateDropScreen`: title, slug (auto from title, editable, `^[a-z0-9-]+$`), shipping fee, optional free-shipping threshold, optional stream URL → INSERT `status='draft'` | RLS own; unique slug (global) → `SLUG_TAKEN` | — |
| Configure | Same screen in edit mode; **slug editable in any status** | No status-aware lock | — |
| Add products | Intake attaches to the target drop (live → draft → any) | RLS own drop | Visible only when live |
| Publish | Drops list → GO LIVE dialog → direct UPDATE `status='live'`, `live_started_at` | `enforce_drops_seller_approval` (approval), `idx_drops_one_live_per_seller` | `/drop/<slug>` (force-dynamic) |
| Public URL | `EnvConfig.getDropUrl(slug)` = `${BUYER_BASE_URL}/drop/<slug>` (default `https://livedrop-in.vercel.app`; `build-seller-apk.ps1` does not pass `BUYER_BASE_URL`) | — | Route exists and matches |
| Copy/share | Dashboard copy/share of drop URL; product share → `…/drop/<slug>#<CODE>` | — | No product anchors (SA-DROP-006) |
| Buyers discover | — | `drops_public_read` (live/closed of approved sellers), `public_products_catalog` | SSR + Realtime (`*` on products, version-gated) + 3 s polling fallback; CDN `s-maxage=5/10, stale-while-revalidate=59` |
| Live | Dashboard pill (green "LIVE"), elapsed time | Checkout RPC requires `status='live'` | Live catalogue |
| Close | CLOSE DROP dialog → `close_drop` RPC | 024: releases unpaid **unclaimed** holds, keeps claimed and advance-paid orders, expires their open attempts | Drop page → "not found" (query filters `live`) |
| Reopen | "Re-open Draft" button on closed drops (dialog text says "Closing this drop…") | closed→draft→live **allowed** | Live again |

Scheduled drops (start time) do not exist.

## 2. Verification results

| Check | Result | Evidence |
|---|---|---|
| Slug generation | From title, lowercase/hyphenated; seller can edit | `create_drop_screen.dart:70-76, 176-200` |
| Uniqueness | Global unique index → friendly `SLUG_TAKEN` | `seller_repository.dart:541-546` |
| Slug stability while live | **Not enforced** — change accepted, old links 404 | 12.4c (SA-DROP-002) |
| One live drop per seller | Enforced | 12.4d PASS |
| Approval before go-live | Enforced | 12.6 PASS |
| Direct →closed bypassing RPC | Blocked | 12.4a PASS |
| live → draft without closure protocol | **Allowed** (no UI button) | 12.4b (SA-DROP-003) |
| Reopen closed drop | **Allowed** (UI offers it; docs/09 forbids) | 12.5 (SA-DROP-001) |
| Close with buyer claims in flight | Claims and holds preserved | 16.2 PASS |
| Close RPC failure handling | Client ignores the JSON result | SA-DROP-005 |
| Pre-live readiness | No checks (unsynced intake, UPI disabled, zero products) | SA-DROP-004 |
| Drop-level free-shipping threshold | Shown to buyers, **ignored by checkout** | 13.10 (SA-PAY-008) |
| Suspended seller's live drop | Keeps selling | 12.7 (SA-ONB-002) |

## 3. Critical question — does the buyer site show exactly the seller's drop and inventory?

| Item | Same? | Basis |
|---|---|---|
| Title | Yes | Both read `drops.title` |
| Seller | Yes for approved sellers; profile fields can be tampered with anonymously (SA-SEC-001) | `public_seller_storefronts` |
| Products | Yes once synced; queued/failed intake items appear in the seller app as "Available" but not on the buyer site (SA-INT-001) | `public_products_catalog`; T17 |
| Prices | Yes (server price); buyer totals can differ from the configured drop threshold (SA-PAY-008) | 13.10 |
| Images | Same URLs (public bucket) | — |
| Availability | Buyer side is near-real-time (Realtime + 3 s polling + version gate; CDN may serve an up-to-~1 min stale HTML shell that the client then corrects). **Seller side is the stale one** (no realtime on Products, SA-RT-001). Expired holds stay "reserved" on both sides for hours (SA-OPS-001). | `catalog-realtime.ts`, `next.config.ts:26-38` |

The end-to-end chain (create → publish → copy URL → open buyer site → compare title/seller/products/prices/images/availability) is consistent **by construction** for synced pieces; it was not executed against a deployed environment in this audit (NOT TESTED). A Playwright scenario for it is listed in [20](20-TEST-COVERAGE-AUDIT.md#4-tests-to-add-before-real-sellers).

## 4. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-DROP-001 | MEDIUM | P1 | Closed drops can be reopened; misleading dialog |
| SA-DROP-002 | MEDIUM | P1 | Slug editable while live (shared links break) |
| SA-DROP-004 | MEDIUM | P1 | No pre-live readiness gate |
| SA-DROP-003 | MEDIUM | P2 | live→draft bypasses safe closure (API) |
| SA-DROP-005 | LOW | P2 | `close_drop` result ignored |
| SA-DROP-006 | LOW | P2 | Product `#CODE` links not handled; closed drop shows "not found" |
| SA-PAY-008 | HIGH | P1 | Drop threshold ignored by checkout |
| SA-ONB-002 | MEDIUM | P1 | Suspension does not close live drops |
| SA-INV-002 | MEDIUM | P1 | Intake may target a closed drop |
