# 18 — UI / UX Audit and Seller Redesign Exercise

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Every seller screen against the brief's criteria (section 22), redesign exercise (section 23), redesign principles (section 35) |
| Executed | Screen-by-screen code walkthrough (widget trees, sizes, colours, copy), tap counting, colour-contrast computation, audit widget tests (T01–T13, T20–T21) |
| Not executed | Usability sessions with sellers; device screenshots (no device available) |

## 1. Overall assessment
The visual identity (obsidian + gold, serif headings, pill badges) is coherent and premium. The operational design is not yet built for a live: state is static, important states are missing or hidden, several controls are placeholders, and the most frequent live actions sit at the top of screens or two levels deep. The redesign below keeps the identity and changes the information architecture and interaction model.

## 2. Screen-by-screen evaluation

Legend: ✔ good · ◐ partial · ✖ problem.

| Screen | Hierarchy | Taps / navigation | Error prevention | Feedback & states (loading/empty/error) | Destructive actions | One-handed / targets | Live suitability |
|---|---|---|---|---|---|---|---|
| Login | ✔ | ✔ | ◐ (no caps-lock/visibility hints beyond eye icon) | ✔ messages, timeout | — | ✔ | — |
| Registration (3 steps) | ✔ | ◐ form lost on Back/kill | ✔ validators | ◐ no timeout on sign-up | — | ✔ | — |
| Pending approval | ◐ no status/ETA | ✔ | — | ◐ | — | ✔ | — |
| Home / dashboard | ◐ wrong KPIs for live (total orders badge, list-price "Revenue") | ✔ quick tiles | — | ✖ errors become zeros; static data | — | ◐ tiles mid-screen | ✖ static, no exceptions, LIVE in green |
| Products | ✔ filters, search | ◐ search at top | ✖ queued/failed shown as Available | ◐ failure banner generic | ✖ (via details) | ◐ | ✖ no live status |
| Product details | ✔ | ✔ | ✖ Mark Sold on reserved | ◐ raw errors | ✖ irreversible Mark Sold | ◐ 44 dp | ◐ |
| Camera intake | ✔ camera-first, multi-angle | ✔ 3–5 taps/garment | ✖ code free text, price unchecked | ◐ "Saved! Syncing…" before acceptance; `##A01` | — | ✔ large shutter | ◐ good base |
| Drops list | ✔ | ✔ | ◐ reopen allowed | ◐ | ✖ reopen dialog says "Closing…" | ◐ | ◐ no pre-live checklist |
| Create/Edit drop | ✔ | ✔ | ✖ slug editable while live | ✔ | — | ◐ | ◐ |
| Orders (Kanban) | ◐ 4 tabs, no closed/refund tab | ◐ search+drop selector at top | ✖ Dispatch on balance-due | ◐ error+retry; realtime only per drop | ✖ Release next to WhatsApp, no claim warning | ◐ 40 dp buttons | ✖ |
| Order card | ✔ code, amount, countdown | ✔ | ✖ actions vs state | ◐ UTC time | ✖ Release unsafe with claim | ◐ 40 dp | ◐ |
| Order details | ✔ timeline, amounts | ◐ | ✖ "Mark as Ready" ships | ✖ crash on double-space names | — | ◐ | ◐ |
| Dispatch dialog | ✔ | ✔ | ◐ default courier | ✔ | — | ◐ dialog fields | — |
| Shipping label screen | ◐ | ✖ entry shortcut picks random order | ✖ fake AWB prefilled, Auto fake | ✖ "Generate & Share" ships; Share/Download fake | ✖ ships without confirm | ✔ | — |
| Payments queue | ◐ UTR prominent, garment missing | ✔ inline actions | ✖ mislabels type; no late/refund consequence | ✖ fake screenshot; remarks ignored; success ignores refund | ◐ reject always releases | ◐ 44 dp | ✖ static, no time left |
| Payment settings | ✔ | ✔ | ✔ VPA regex | ✔ | ✖ VPA change without re-auth | ✔ | ◐ no live warning |
| Settings / More | ✔ | ✔ | ◐ silent fee fallbacks | ✖ fake toggles, fake cache clear, fixed "Verified" | ✔ sign-out confirm | ✔ | — |
| Analytics | ✔ charts | ✔ | — | ◐ UTC days | — | ✔ | — (post-live) |

Typography/density/consistency: consistent tokens; 11 px labels and 40 % white text are hard to read outdoors (SA-UX-003). Motion: subtle and acceptable; the infinite LIVE pulse is the only always-on animation. Terminology: mixes "Hold", "Reserved", "On Hold", "Payment Pending", "Verifying" for overlapping states — define one vocabulary (Available · Reserved · Claimed · Paid · Packed · Shipped · Closed).

## 3. Principle compliance (brief section 35)

| # | Principle | Current | Gap |
|---|---|---|---|
| 1 | Efficiency > decoration | ◐ | Decorative greeting/emblem fine; missing operational data |
| 2 | Common actions minimal navigation | ◐ | Verify needs tab switch + refresh; code lookup needs tab + search |
| 3 | Critical actions visible immediately | ✖ | Claims/expiring holds not surfaced on Home |
| 4 | No state hidden behind menus | ✖ | Cancelled/expired/refund-owed hidden entirely |
| 5 | Strong urgency hierarchy | ◐ | Countdown + red border < 3 min on cards; nothing global |
| 6 | Semantic colour | ◐ | LIVE pill green (should be red); otherwise aligned (gold actions, red reject/late, amber pending, green paid) |
| 7 | Premium Indian-luxury identity | ✔ | Keep |
| 8 | Not visually beautiful but slow | ◐ | Static data is the real slowness |
| 9 | Animations aid comprehension | ✔ | — |
| 10 | Comfortable one-handed targets | ◐ | 38–44 dp buttons, top-placed controls |
| 11 | Seller understands every mutation | ✖ | Optimistic "Saved", ignored refund flag, fake success snackbars |
| 12 | Destructive ops need confirmation/recovery | ◐ | Confirmations exist; no undo; Release ignores claims |

## 4. Redesign exercise

The redesign optimises **Sell → Organise → Reserve → Verify → Fulfil → Ship → Analyse** and assumes the server-side fixes in [22](22-IMPROVEMENT-ROADMAP.md) (live session store, summary RPC, claim-aware RPCs, refund state, push).

### 4.1 Navigation
Bottom bar (4 items, 56 dp, labels ≥ 12 px): **Live** (command center; becomes "Home" when no drop is live) · **Products** · **Orders** · **More**. Payments move into Live's action queue (with a badge on the Live tab). A floating **code pad** button (bottom-right, thumb zone) is available on Live/Products/Orders.

### 4.2 Live Command Center (replaces Home during a live)
```
┌──────────────────────────────────────────┐
│ ● LIVE 00:42  Diwali Silk Drop   [Copy] [Share] │  ← red pill (live), gold actions
│ Available 41   Reserved 7   Claimed 3   Paid 12 │  ← tap = filtered list
├──────────────────────────────────────────┤
│ NEEDS YOU NOW (sorted by urgency)            │
│ ▌Claim ₹2,580  #A17  Riya S.  UTR …8901  21h │  ← red/amber bar = time left
│ │   [Ask to fix]              [Verify ✓]     │  ← gold primary at thumb reach
│ ▌Late claim ₹250 #A09 — garment SOLD → refund │  ← red: consequence explained
│ ▌Hold expiring 2 min  #B03  Priya            │
│ ▌Upload failed  "101" — invalid code [Fix]   │
├──────────────────────────────────────────┤
│ Recent: #A21 reserved · #A17 claimed · …     │  ← neutral feed
└──────────────────────────────────────── [⌨ A17]┘  ← code pad FAB
```
Updates live via the session store; a thin banner shows "Live updates paused — reconnecting" when the channel drops.

### 4.3 Rapid Product Intake
Camera-first (as today) plus: validated code chip with auto `#` and next-code suggestion that checks server + queue; **price-first** sheet with large digits and quick chips (last 5 prices); size remembers last value; "Save & next" as the primary bottom button; duplicate-photo hint; queued items show **Syncing / Failed — Fix** inline with edit and discard; optional **batch mode** (shoot 30 photos now, assign code/price in a fast list later). Target ≤ 3 taps + price digits per garment, verified on a low-end phone.

### 4.4 Live Inventory View
Segmented filter: **Available · Reserved · Claimed · Paid · Sold** with live counts; each row shows code, thumbnail, price, holder + minutes left; swipe right = share piece link, swipe left = mark sold (available only) with a 5-second **Undo** snackbar backed by an undo RPC.

### 4.5 Live Order Queue
One list ordered by "needs action" (claimed → reserved expiring → paid not packed → packed not shipped); the four-tab Kanban remains as a secondary "pipeline" view, plus a **Closed** tab (cancelled, expired, refunds owed).

### 4.6 Payment Verification Queue (card spec)
| Field | Content |
|---|---|
| Buyer | Name + phone (tap → WhatsApp with order link) |
| Order | Code + garment thumbnail(s) + piece codes |
| Amount | Expected amount **and type** ("Advance ₹250 of ₹2,580" / "Full ₹2,580" / "Balance ₹2,330") |
| UTR | Monospace, copy button, "used on another order" warning |
| Submitted | Local time + "x min ago" |
| Time remaining | Countdown to verification deadline (red < 2 h) |
| Late claim banner | "Order was cancelled; garment available → will be re-reserved" or "garment sold → you must refund ₹X" |
| Actions | Bottom row: **Ask buyer to fix (keep hold)** · **Reject & release** · **Verify** (gold, largest) |

### 4.7 Global Seller Search
One field (and the code pad) searching product code/name, order code, buyer name, phone, UTR; results grouped (Pieces · Orders · Claims) with the next valid action inline.

### 4.8 Quick Actions (server-authorised, state-aware)
| Action | Available when (server rule) | RPC |
|---|---|---|
| Reserve for buyer (new) | piece available, drop live | new `seller_hold_for_buyer` (creates order + sends link) |
| Mark Sold (other channel) | piece available | `mark_product_sold_offline` (+ undo RPC) |
| Verify Payment | claimed attempt, order not terminal (or late with explicit consequence) | `verify_manual_upi_payment` |
| Mark Ready (Packed) | paid in full, not_ready | `mark_order_ready_to_ship` |
| Ship | paid + ready, real AWB | `mark_order_shipped` |
| Contact Buyer | any order | WhatsApp with order link + amount due |
Buttons are derived from `(status, payment_status, fulfilment_status, attempt status)` exactly as the RPCs check them — never shown when the server would refuse.

### 4.9 Exception Center
A filtered view of the action queue, always reachable from Live and More: **Payment claim waiting** (with deadline), **Reservation expiring**, **Stock conflict** (late claim vs resold piece), **Refund owed**, **Upload failed (needs edit)**, **Shipping missing** (paid > N days not shipped), **Order blocked** (balance due, hold expiring). Each item has one primary action.

### 4.10 Drop Control Center
Single screen per drop: status + **pre-live checklist** (pieces synced, UPI on, link ready), Go Live (red confirm), Copy/Share link (WhatsApp/Instagram), live monitor (counts), Close (with summary of holds/claims that remain), post-live summary. Slug locked once live.

### 4.11 Business Insights (post-live, not during)
Cash received (ledger), to collect (balances), refunds owed, pieces sold/unsold, sell-through %, top pieces, average time-to-pay, abandoned holds — computed in SQL, in IST.

## 5. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-UX-001 | MEDIUM | P1 | No live command view; no global search; LIVE colour semantics |
| SA-UX-002 | MEDIUM | P1 | Placeholder controls fake success |
| SA-UX-004 | MEDIUM | P2 | Touch targets and thumb reach |
| SA-UX-003 | LOW | P2 | Contrast ≈3.8:1; minimal screen-reader support |
| SA-UX-005 | LOW | P2 | Raw exception text shown to sellers |
| SA-SET-001 | MEDIUM | P2 | Silent fee fallbacks; threshold not editable |
| SA-INV-005 | LOW | P3 | `##A01` |
| SA-AUTH-006 | LOW | P3 | "Remember me" no-op |
