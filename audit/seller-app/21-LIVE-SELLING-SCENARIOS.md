# 21 — Seller Live-Commerce Efficiency Study (Scenarios A–J)

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Method | Each scenario was walked through the actual widget code (taps = discrete touches; typing counted separately), cross-checked with the server behaviour proven in suites 12–18 and audit tests T01–T25. Times are estimates for a practised seller on a mid-range phone; **no timed device session was possible** (see [16](16-ANDROID-AUDIT.md)). |
| Scale | Cognitive load: Low / Medium / High. Sync risk: chance that what the seller sees differs from server truth. |

## Summary

| Scenario | Current actions | Current screens | Proposed actions | Biggest risk today |
|---|---|---|---|---|
| A. 30 garments before a live | ~120 taps + 30 prices (≈6–8 min) | 3 | ~70 taps + 30 prices | Silent intake failures, queue loss/race |
| B. Start Facebook Live | 5–6 | 2–3 | 3 | Going live with unsynced pieces/UPI off |
| C. Buyer asks for A17 | 5–8 + typing | 2 | 3 | Stale status |
| D. A17 is reserved | 6–8 | 2 | 1–2 | Expired holds linger for hours |
| E. Buyer submits UTR | 0 (seller unaware) | 0 | 0 (alert arrives) | Claim unseen → expires |
| F. Seller verifies payment | 5 + 2 app switches + refresh | 1 | 2 + 1 app switch | Wrong context; refund ignored |
| G. Selling while claims arrive | n × F, discovered late | 1–3 | queue, sorted by deadline | Claims expire / late verifies |
| H. Sold on another channel | 5–6 | 2 | 3 (+ Undo) | Irreversible mis-tap |
| I. Network drops 30 s | — | — | — | Silent staleness, ambiguous outcomes |
| J. 15 orders rapidly | 15 full refetches; other tabs stale | 1–4 | incremental queue | Jank, missed attention items |

---

### Scenario A — Seller receives 30 garments before a live
| Measure | Current | Proposed |
|---|---|---|
| Actions | Create drop (≈6 taps + title/slug/fee typing) → Add Product → per garment: shutter, price field, digits, optional size, Save & Next = 3–5 taps → **≈90–150 taps + 30 prices** | Batch shoot (1 tap/garment) then a price list (1 tap + digits per row) → ≈2 taps + digits per garment |
| Screens | Drops/Create drop, Camera intake, Products | Drop Control Center, Intake (batch), Review list |
| Opportunities for error | Free-text code (`101`, `SAREE01` fail later, SA-INT-001); price typo (no check); wrong target drop if latest is closed (SA-INV-002); two phones → duplicate codes | Validated code chip, price outlier warning, explicit drop, server-checked next code |
| Data-sync risk | **High**: queue in cache dir (SA-OFF-001); re-opening intake during a sync loses progress and creates permanent failures (T25); no processing at app start; failed items show as "Available" | Durable idempotent queue, per-item status, Go Live blocked until synced |
| Cognitive load | Medium (repetitive, but camera-first is good) | Low |
| Recovery path | Only after sync and only while available (edit); failed queue items cannot be edited or discarded | Inline "Fix" for failed items; edit/discard before sync |

### Scenario B — Seller starts Facebook Live
| Measure | Current | Proposed |
|---|---|---|
| Actions | Home → Manage Drop → GO LIVE → Confirm → back → Copy link (5–6) | Drop Control Center: checklist → Go Live → share sheet opens with link (3) |
| Screens | 2–3 | 1 |
| Opportunities for error | Going live with unsynced/failed pieces, UPI disabled (buyers can reserve but not pay, SA-PAY-012), editing slug later breaks the shared link (SA-DROP-002) | Pre-flight checklist; slug locked when live |
| Data-sync risk | Low | Low |
| Cognitive load | Medium (must remember checks) | Low |
| Recovery path | Close + re-open is possible (contrary to docs) | Explicit "pause" semantics if needed |

### Scenario C — Viewer asks for "A17"
| Measure | Current | Proposed |
|---|---|---|
| Actions | Products tab → search → type `A17` → pull to refresh → open piece → Share → pick app (5–8 + typing) | Code pad FAB → `17` → piece card (status live) → Share (3) |
| Screens | 2 | 1 (overlay) |
| Opportunities for error | Reads a stale "Available" (no realtime); queued-but-failed piece looks available | Live status, holder shown |
| Data-sync risk | **High** (SA-RT-001) | Low |
| Cognitive load | Medium | Low |
| Recovery path | Tell viewer "check the link" | — |

### Scenario D — A17 is reserved
| Measure | Current | Proposed |
|---|---|---|
| Actions | Orders → (select drop) → search `A17` → card shows buyer + countdown (6–8) | Piece card already shows holder + minutes left (1–2) |
| Screens | 2 | 1 |
| Opportunities for error | Expired hold still "reserved" for hours (reaper ≈5×/day, SA-OPS-001) → seller force-releases; Release on a claimed order destroys a paid order (SA-PAY-005) | Lazy expiry frees the piece automatically; Release disabled while a claim exists |
| Data-sync risk | High | Low |
| Cognitive load | High (seller must judge whether a hold is "dead") | Low |
| Recovery path | Manual release (unsafe) | Waitlist / next-in-line (future) |

### Scenario E — Buyer submits UTR
| Measure | Current | Proposed |
|---|---|---|
| Actions | None — the seller is not told (no push, Payments not live) | Heads-up notification + Live queue item with deadline |
| Opportunities for error | Fake UTR locks the piece for 24 h (SA-PAY-007); same UTR on two orders (SA-PAY-011) | Claim cap during live, duplicate warning on card |
| Data-sync risk | High (claim invisible until refresh) | Low |
| Cognitive load | High (must remember to check) | Low |
| Recovery path | If missed for 24 h the claim expires and disappears (SA-PAY-003) | Never auto-expire claimed money |

### Scenario F — Seller verifies payment
| Measure | Current | Proposed |
|---|---|---|
| Actions | Payments tab → pull to refresh → find card → Copy UTR → switch to bank app → back → Verify → Confirm (**5 taps, 2 app switches**) | Queue card → Copy UTR → bank → Verify (bottom, confirm inline) (**2 taps, 1 round trip**) |
| Screens | 1 + external | 1 + external |
| Opportunities for error | "Advance Payment" label on full payments (T09); no garment shown (T13); fake screenshot (T12); late-claim consequences hidden; refund flag ignored (SA-PAY-004); late advance marked fully paid (SA-PAY-001) | Type + amount due vs total, garment thumbnail, late/refund banner, server fixes |
| Data-sync risk | Medium | Low |
| Cognitive load | High | Medium (bank check remains manual by design) |
| Recovery path | No undo; reject always releases (SA-PAY-010) | "Ask to fix (keep hold)" path; refund tracking |

### Scenario G — Selling continues while several claims arrive
| Measure | Current | Proposed |
|---|---|---|
| Actions | Periodically leave the stream app, open Payments, refresh, process oldest first (card order = claim time) | Live tab badge + notifications; queue sorted by deadline; process in 2 taps each |
| Screens | 1–3 | 1 |
| Opportunities for error | Forgetting to check; verifying a late claim that re-sells a piece another buyer is reserving (SA-PAY-002) | Server lock fix; late claims flagged |
| Data-sync risk | High | Low |
| Cognitive load | High | Medium |
| Recovery path | None if a claim expired | Claims never vanish |

### Scenario H — One item sold through another channel (e.g. WhatsApp)
| Measure | Current | Proposed |
|---|---|---|
| Actions | Products → search → open piece → Mark Sold → Confirm (5–6) | Code pad → piece → "Sold elsewhere" (swipe) → Undo available 5 s (3) |
| Screens | 2 | 1 |
| Opportunities for error | Button enabled on reserved pieces (server rejects with raw error, 12.9); mis-tap is irreversible (SA-INV-001) | Disabled for reserved with explanation; Undo RPC |
| Data-sync risk | Low (server locks) | Low |
| Cognitive load | Medium | Low |
| Recovery path | None | Undo window |

### Scenario I — Network drops for 30 seconds
| Measure | Current | Proposed |
|---|---|---|
| Behaviour | No banner; RPCs fail with raw messages; retried verify is safe (idempotent) but release/mark-sold retries show confusing errors; realtime reconnects silently without catch-up; intake keeps queueing (good) but sync waits for the next timer/trigger | Offline banner; money/inventory actions disabled with reason; automatic catch-up refetch when the channel resubscribes; queue resumes on connectivity |
| Opportunities for error | Seller repeats an action not knowing the first succeeded; announces stale availability | Outcome shown from server state after reconnect |
| Data-sync risk | High | Low |
| Cognitive load | High | Low |
| Recovery path | Manual pull-to-refresh on each tab | Automatic |

### Scenario J — 15 orders arrive rapidly
| Measure | Current | Proposed |
|---|---|---|
| Behaviour | Orders tab (only if a drop is selected) refetches the full nested list per event — 15+ downloads, possible out-of-order overwrite; Home/Products/Payments stale; no ordering by urgency | Incremental updates; one summary refresh; action queue (expiring holds, claims) on top; batched notification "15 new orders" |
| Actions to triage | Scroll Pending tab, read countdowns per card | Read the top of the queue |
| Opportunities for error | Missing an expiring hold or a claim among many cards; jank on low-end phones (SA-PERF-001) | — |
| Data-sync risk | Medium–High | Low |
| Cognitive load | High | Medium |
| Recovery path | Manual refresh | Automatic |

## Better workflows — summary
1. **Live Command Center + action queue** (scenarios C–G, J).
2. **Code pad** for instant lookup (C, D, H).
3. **Batch intake + validated codes + durable queue** (A).
4. **Pre-live checklist + locked slug** (B).
5. **Push for claims/late claims/expiring windows** (E, G).
6. **Server fixes that remove seller judgement calls**: lazy hold expiry, claim-aware release, never-expire claimed money, refund state (D, E, F, G).
7. **Offline/online honesty**: banners, disabled actions, automatic catch-up (I).
