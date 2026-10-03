# 12 — Offline / Network Resilience Audit

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Real offline behaviour of the seller app; the intake queue vs ADR-006 |
| Executed | Flutter audit tests T14–T19 and T25 against the real `OfflineIntakeQueue` with a server-like fake (UNIQUE/CHECK semantics, lost responses, corrupt manifest); code trace of every screen's failure path |
| Not executed | Airplane-mode runs on a device; Android cache eviction; process death on a device |

## 1. Verdict
Offline support exists **only for product intake**, and that queue is not durable or idempotent enough to be trusted before a live. Every other workflow requires the network and fails quietly (empty screens) rather than explicitly.

## 2. Test matrix (brief section 15)

| Case | Behaviour | Safe? | Evidence |
|---|---|---|---|
| Launch offline | Supabase initialises from the stored session; profile load fails → approval gate **fails open** to an empty dashboard with zeros and no error | Misleading | T07; `seller_dashboard_screen.dart:52-100` |
| Create product offline | Capture → compress → enqueue (files + manifest) works; UI shows the piece as "Available" | Partly — see durability | T14, products_inventory_screen.dart:69-91 |
| Capture image offline | Works (no network needed) | Yes | — |
| Edit product offline | `update_product` fails → error snackbar; not queued | Safe (explicit) | — |
| Mark sold offline | RPC fails → raw error; not queued | Safe | — |
| View orders offline | Orders: error state + Retry; Home: zeros; Payments: error + Retry; Products: last list or empty | Inconsistent | Code |
| Interruption mid-request (non-intake) | Verify: retry is idempotent ✔; Mark sold: retry → `ALREADY_SOLD` error; Release: retry → `ONLY_PENDING_CAN_BE_RELEASED`; seller cannot tell whether the first call succeeded | Confusing | RPC code |
| Interruption mid-intake-sync | Per-angle upload resumes (URLs persisted); product insert after a lost response → **permanent DUPLICATE failure** although the product exists | No | T16 |
| Intake reopened while a sync is still running (no network fault) | `CameraIntakeScreen` re-initialises the shared queue, reloading items from disk; the running sync completes on orphaned objects, the item stays "uploading", is re-sent and fails permanently as DUPLICATE (second upload orphaned in Storage) | No | T25 |
| Network restoration | No connectivity listener; queue retries only on its own timer (≤ 64 s) while the process lives, on intake screen open, or manual Retry | Slow / unreliable | `offline_intake_queue.dart:334-343`; `main.dart:189` |
| Duplicate replay | Not idempotent (no client-side id / idempotency key) | No | T16 |
| Conflicting updates | Only code collisions (two devices, same suggested code) → permanent failure | No | T16/T17 |
| Force-close during queued operation | Manifest persisted with status; resumes when the queue is processed again (not on app start) | Partly | `main.dart:189` (initialize only) |
| Corrupt/partial manifest | Read error swallowed; next save overwrites the file → **all queued items lost** | No | T19 |
| Item enqueued while a sync runs | Not included in that run; waits for next trigger | Delay | T18 |
| OS clears cache / user taps "Clear cache" | Queue lives in `Directory.systemTemp` (= app cache dir on Android) → lost | No | T14 |
| Storage growth | Completed items + JPEGs never deleted; "Clear Image Cache" is a no-op | No | T15, settings |

## 3. ADR-006 conformance

| ADR-006 decision | Implementation | Status |
|---|---|---|
| SQLite queue (`sqflite`) | JSON file (`queue.json`) rewritten on every change | Deviates (no atomic write → corruption risk) |
| Statuses pending → compressing → uploading → syncing_db → synced | pending → uploading → uploaded → completed / failed | Equivalent |
| Delete local file on synced | Never deleted | **Not implemented** (SA-OFF-002) |
| Retry with backoff on reconnection (`connectivity_plus`) | Timer backoff only; no connectivity trigger | **Not implemented** (SA-OFF-001) |
| Persistent sync badge in header | Badge on intake screen; banner on Products | Partial |
| Block Go Live until all items synced | Not enforced | **Not implemented** (SA-DROP-004) |
| "Zero data loss during network drops" | Cache-dir storage, manifest overwrite on corruption | Not met |

## 4. What is unsafe offline (and should stay online-only)
Payment verification, rejection, hold release, mark sold, dispatch, drop go-live/close: they decide money and unique inventory against current server state. Queuing them offline would create conflicts the seller cannot resolve mid-live. They should be **disabled with an explicit "Offline — reconnect to verify" state**, not queued.

## 5. Recommended architecture (proportionate)
1. **Intake queue (keep, harden)**: app support directory + atomic write-rename (or SQLite per ADR-006); client-generated product UUID (or idempotency key) so replays are safe; error classes `transient` / `needs_edit` / `conflict` with edit/discard actions; process on app start, on resume, on connectivity regained; delete local files after success; block Go Live while items are pending/failed.
2. **Read-through cache** for the last known live state (orders, claims, products) with an "as of hh:mm" stamp and a clear offline banner — lets the seller keep talking on stream with approximate state.
3. **No general offline command queue** for money/inventory actions (not justified; risk of double-acting on stale state).

## 6. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-OFF-001 | HIGH | P1 | Queue in cache dir; corrupt manifest loses everything; no start/connectivity processing |
| SA-OFF-003 | MEDIUM | P1 | Not idempotent; permanent errors retried forever; no edit/discard |
| SA-OFF-002 | MEDIUM | P2 | Local files never pruned; Clear Cache fake |
| SA-INT-001 | HIGH | P0 | Invalid input accepted offline, fails later silently |
| SA-AUTH-002 | MEDIUM | P1 | Offline start shows an empty "approved" dashboard |
| SA-DROP-004 | MEDIUM | P1 | Go Live not blocked by unsynced intake |
