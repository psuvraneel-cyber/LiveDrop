# 06 — Product / Inventory and Camera Intake Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Product lifecycle (create → image → code → price → size → save → edit → publish → buyer visibility → reserve → sold → fulfilled); camera/gallery intake and image pipeline (brief sections 8 and 9) |
| Executed | SQL suite 12 (codes, direct mutation guards, inserts, mark sold); Flutter audit tests T14–T19 and T25 (queue), T22–T24 (image pipeline); code trace of intake and inventory screens |
| Not executed | Camera on a real device (permissions, lifecycle, memory, speed on low-end hardware) |

## 1. Lifecycle as implemented

```
Intake (camera/gallery) ─► ImageService (isolate) ─► OfflineIntakeQueue.enqueue (files + manifest)
   │ optimistic "Available" card in UI                         │
   ▼                                                           ▼
 processQueue: upload angle 1..n (Storage, upsert) ─► INSERT products(status='available')
                                                              │ (CHECK code, UNIQUE(drop,code), price>0, title≤100, size≤30)
                                                              ▼
 Buyer catalogue (public_products_catalog, live drops of approved sellers) ─► checkout reserves (RPC)
   ─► verify payment → 'sold' (RPC) ─► ready/ship (RPC)       Edit: update_product (available only)
                                                              Sold elsewhere: mark_product_sold_offline (available only, irreversible)
```

| Stage | Server rule | Client behaviour | Verdict |
|---|---|---|---|
| Create | Insert by owner; code regex; unique per drop | Code suggested `#<prefix><nn>`, editable free text | Unvalidated input fails late (SA-INT-001) |
| Image | Public bucket, folder = uid | 1:1 crop, ≤1200 px, JPEG q85, EXIF kept | Orientation PASS (T22); EXIF leak (SA-SEC-004); size above ADR budget (SA-PERF-003) |
| Price | `price_paisa > 0` INT | Whole rupees, `> 0` check | No sanity warning (SA-INV-004) |
| Size | `≤ 30` chars | Chips: Free Size, XS–XXL | OK |
| Save | — | Enqueue + "Piece saved! Syncing…" | Optimistic success before server acceptance |
| Edit | `update_product` only when `available`; direct UPDATE blocked by trigger | Edit disabled for reserved/sold | **PASS** (12.2a/b) |
| Publish | Visible when the drop is live and seller approved | — | Correct; intake may target a closed drop (SA-INV-002) |
| Reserve | `create_order_with_reservation` locks rows, one winner | Not live-updated in Products tab | Server PASS (14.1); client stale (SA-RT-001) |
| Sold | Verification marks sold; `mark_product_sold_offline` for other channels | Mark Sold enabled on reserved; no undo | SA-INV-001 |
| Delete/hide | DB allows deleting never-ordered pieces | No UI | SA-INV-006 |

## 2. Product test matrix (brief section 8)

| Case | Behaviour | Evidence |
|---|---|---|
| Duplicate code | UNIQUE(drop, code) → `DUPLICATE_PRODUCT_CODE`; queue keeps retrying forever; after a lost response the product exists but the queue item fails permanently | T16 (SA-OFF-003) |
| Duplicate product (same photo twice) | Accepted; no duplicate detection | Code |
| Invalid price | Client blocks ≤ 0 and non-numeric; DB CHECK > 0 | Code |
| Zero/negative price | Blocked (client + DB) | Code |
| Invalid size | Chips only in intake; edit dialog + RPC length check | Code / 025 |
| Invalid code (`101`, `A5`, `SAREE01`, `A-07`) | Queued, shown as Available, fails in background with 23514, retried forever | 12.1, T17 (SA-INT-001) |
| Title > 100 chars | Same late failure path (CHECK) | 003:9 |
| Missing image | Not possible from UI (enqueue requires ≥ 1 image) | `offline_intake_queue.dart:198-202` |
| Corrupted image | Decode throws → "Capture failed / Gallery import failed" snackbar | `camera_intake_screen.dart:264-274, 300-309` |
| Slow upload | No per-item progress; only "Queue: N" badge | Code |
| Interrupted upload | Per-angle resume (`remoteImageUrls` persisted); upsert makes re-upload safe | Code (good) |
| Retry upload | Automatic backoff ≤ 64 s + manual Retry banner; no classification | SA-OFF-003 |
| Network loss | Capture/enqueue works offline; inventory list cannot load (error swallowed → empty/old list) | SA-OFF-001 |
| Product deletion | No UI | SA-INV-006 |
| Product editing | Available only; price/title/size via RPC | 025, PASS |
| Sold state | Irreversible "Mark Sold" | 12.9 |
| Reserved state | Shown only after manual refresh | SA-RT-001 |
| Stale state | No realtime on products; IndexedStack never refreshes | SA-CQ-001 |
| Concurrent modifications | `update_product` row-locks; last write wins (no version check) — acceptable | 025 |

## 3. Rapid live intake — friction measurement (code-derived; device timing NOT TESTED)

Steady state "Save & Next Garment" loop, single angle, title left default ("Item #A07"):

| Step | Taps | Typing | Notes |
|---|---|---|---|
| Shutter | 1 | — | Camera preview stays open between garments |
| Wait for compression | — | — | 0.39 s (1280×720) – 3.0 s (12 MP) on a dev Xeon (T24); low-end phones slower (budget < 600 ms) |
| Price field | 1 | 3–5 digits | Number keyboard; no quick chips |
| Size (if not Free Size) | 1 | — | Chips |
| Title (optional) | 1 | free text | Default `Item #A07` is what buyers see |
| Save & Next | 1 | — | Snackbar reads `##A08 ready` (SA-INV-005) |
| **Total** | **3–5 taps + price digits** | | ≈ 8–15 s/garment estimated → within docs/22 budget (< 30 s), unverified on device |

Extra angle: +2 taps ("Add Another Angle", shutter) and another compression wait per angle (max 4).

**Opportunities for error:** editing the code (no validation; SA-INT-001), price typo (no confirmation; SA-INV-004), wrong target drop (silent; SA-INV-002), keyboard covering the save buttons on small phones (bottom sheet with `viewInsets` padding — needs device check), duplicate codes across two phones (suggestion uses only locally loaded products).

**Recovery from mistakes:** before sync — none (queued items cannot be edited or removed); after sync — edit while available; wrong photo — no replace action; wrong piece — only irreversible Mark Sold.

Friction reductions (detailed in [22](22-IMPROVEMENT-ROADMAP.md#c-ux-improvements)): validated code field with auto `#`, price-first sheet with last-used size and quick price chips, inline "Syncing / Failed — tap to fix" states, edit/discard queued items, batch "photograph 30 now, price later" mode, duplicate-photo hint.

## 4. Camera / image intake (brief section 9)

| Item | Implementation | Assessment |
|---|---|---|
| Camera permission | Requested implicitly by `camera` plugin on initialise; failure → "Hardware camera unavailable (…). Fallback to gallery available." | No rationale screen; permanently-denied state not handled (device test) |
| Gallery permission | `image_picker` (Android photo picker on 13+) | OK |
| Capture | `CameraController(ResolutionPreset.high, JPEG)`, `takePicture()`; fallback `image_picker` camera | OK |
| Cropping | Automatic centre 1:1 crop in `ImageService` (no manual crop) | Garments photographed in portrait lose top/bottom (product decision; consider 4:5) |
| Compression | Pure-Dart `image` decode/encode in `compute` isolate, ≤1200 px, JPEG q85 | Works; slower and larger than ADR-005 (SA-PERF-003) |
| Orientation | Decoder bakes EXIF orientation | **PASS** (T22) — earlier hypothesis refuted |
| Metadata | EXIF (make/model/GPS) preserved in public files | SA-SEC-004 |
| Upload | Queue, per angle, `upsert: true`, deterministic path | Resumable; orphaned objects if insert fails permanently |
| Progress | Count badge only | Weak |
| Retry | Backoff/Retry banner | No classification (SA-OFF-003) |
| Cancellation | No cancel of a queued item | Gap |
| Offline interruption | Files persisted before network | Good — but in the cache dir (SA-OFF-001) |
| Duplicate images | Not detected | Gap |
| Preview / thumbnails | Draft angles via `Image.memory` (76 px); inventory uses `Image.network` on full 1200 px images without `cacheWidth`; queued items show a placeholder (local path passed to `Image.network`) | Decode cost on lists; missing local thumbnails |
| Storage path | `product-images/{seller}/{drop}/{code}_{queueId}_{angle}.jpg` | Satisfies RLS (11.5a PASS) |
| Cache | Local JPEGs never deleted (T15) | SA-OFF-002 |
| Memory | Full-resolution bytes (up to ~16 MB for 12 MP) read into memory, then sent to an isolate; up to 4 processed angles kept in memory | Acceptable on mid-range; risky on 2–3 GB devices (NOT TESTED) |
| Lifecycle | Disposes on `inactive`, re-inits on `resumed` | Device validation required (SA-AND-004) |
| Repeated rapid intake | `_isProcessing` guard prevents double capture; one bottom sheet at a time | OK by code |

## 5. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-INT-001 | HIGH | P0 | Invalid codes/titles accepted, shown as Available, fail silently in background |
| SA-OFF-003 | MEDIUM | P1 | Queue not idempotent; permanent errors retried forever; items cannot be edited/discarded |
| SA-INV-001 | MEDIUM | P1 | Mark Sold offered on reserved pieces; no undo |
| SA-INV-002 | MEDIUM | P1 | Intake can target a closed drop silently |
| SA-SEC-004 | MEDIUM | P1 | EXIF/GPS published with product photos |
| SA-PERF-003 | MEDIUM | P2 | Image output above ADR-005 budget |
| SA-INV-003 | MEDIUM | P2 | DB accepts products inserted as sold/reserved |
| SA-INV-004 | LOW | P2 | No price sanity check |
| SA-INV-006 | LOW | P2 | No hide/delete for mistaken pieces |
| SA-INV-005 | LOW | P3 | `##A01` double hash |
| SA-AND-004 | LOW | P2 | Camera lifecycle needs device validation |
