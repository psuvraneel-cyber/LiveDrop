# 08 — Facebook / Instagram Live Operations Audit (+ Dashboard)

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | The live loop: comment "A01" → find piece → buyer reserves → recognise buyer → payment → verify UTR → fulfil; dashboard "at a glance" (brief sections 11 and 18) |
| Executed | Code walk-through of every screen involved with tap counting; SQL suites 12–16 for the server side of each step; Flutter T07–T13, T20–T21 |
| Not executed | Timed usability session with a real seller on a device (recommended in [21](21-LIVE-SELLING-SCENARIOS.md)) |

## 1. How the live loop works today

LiveDrop's model is **buyer self-checkout**: the seller announces codes on the stream and shares the drop link; buyers reserve and pay on the web; the seller verifies UPI payments in the app. The seller cannot reserve a piece on a commenter's behalf.

### Walk-through: viewer comments "A01"

| Step | What the seller does in the app | Taps / input | Screens | Problems |
|---|---|---|---|---|
| 1. Find A01 | Products tab → search → type `A01` | 2 taps + 3 keys (+ pull to refresh for current status) | 1 | Status may be stale (no realtime, SA-RT-001); search box at the top of the screen; queued/failed pieces look "Available" (SA-INT-001) |
| 2. Tell the buyer how to buy | Dashboard → copy/share drop link, or Product details → Share (product link `#A01`) | 2–3 taps | 1–2 | Product anchor not honoured by buyer site (SA-DROP-006) |
| 3. Buyer reserves | (buyer on web; 15-min hold) | — | — | Seller is not told (no push, SA-NOT-001); Orders tab updates only if a single drop is selected |
| 4. Recognise buyer | Orders → (select drop) → Pending → find card by name/phone/code | 2–4 taps + search | 1 | Name typed at checkout may differ from the social handle; no "A01 → order" jump from the product |
| 5. Payment arrives | Seller checks bank/UPI app outside LiveDrop | app switch | — | — |
| 6. Verify UTR | Payments → pull to refresh → find card → copy UTR → compare in bank app → Verify → Confirm | 4–5 taps + 2 app switches | 1 | Card lacks garment, type label wrong, no time remaining (SA-PAY-009); late-claim consequences hidden (SA-PAY-004) |
| 7. Fulfil (later) | Orders → Paid → Dispatch → tracking → Confirm | 4 taps + typing | 2 | Dispatch shown for balance-due orders (SA-ORD-005) |

**Per-sale minimum during the live: ~10–14 taps, 3 tabs, 2 app switches, 2–3 manual refreshes.** The structural cost is not the tap count itself but the absence of a single place that shows "what changed and what needs me now".

## 2. Capability checklist (brief section 11)

| Capability | Present? | Notes |
|---|---|---|
| Flash-code search | Partial | Inside Products (code/title/status) and Orders (code/buyer/phone/items). No dedicated code pad |
| Global search | No | No search across products + orders + claims + UTRs |
| Order lookup | Yes (Orders search) | Filter by drop resets realtime |
| Product lookup | Yes (Products search) | Status not live |
| Quick reserve (seller on behalf of a commenter) | **No** | Buyers must self-checkout; consider "hold for buyer" link generation |
| Quick sold | Yes ("Mark Sold" in product details, 3 taps) | Offered on reserved pieces; irreversible (SA-INV-001) |
| Payment verification | Yes (Payments tab) | See SA-PAY-009/010/004/005 |
| Buyer lookup | Partial (Orders search by name/phone) | No buyer history |
| Live inventory | No live updates | SA-RT-001 |
| Recent activity | Dashboard list of 5 items | Static; mixes claims and orders; errors → empty list |
| Keyboard usage | Search needs the full keyboard | No numeric code keypad |
| Barcode / code input | No | Tag/QR scanning would help physical lookup |
| One-handed operation | Weak | Search/filters/refresh at the top; 38–44 dp buttons (SA-UX-004) |
| Confirmation dialogs | Present for verify, reject, release, mark sold, go live/close | Good; texts sometimes wrong (reopen) or missing consequences (release with claim) |
| Undo / reversal | None | No undo for mark sold, release, reject, ship |

## 3. Dashboard "at a glance" (brief section 18)

| Question | Answer from the current Home screen | Gap |
|---|---|---|
| Current live drop | Title + LIVE/DRAFT/CLOSED pill + "Started N min ago"; falls back to a draft or the latest closed drop | LIVE shown in green (principle: red = live) |
| Active viewers | Not available (no platform integration) | Out of scope |
| Products available | Not shown ("Items" = total) | Show available count |
| Products reserved | "On Hold" | Static until refresh |
| Products sold | "Sold" | Includes sold-offline |
| Pending payment claims | Badge on "Verify Payments" tile | Static; no oldest-claim age |
| Orders requiring attention | "View Orders" badge = **total** orders | Should be attention count |
| Shipping due | Not shown; "Shipping" tile opens a random order's label (SA-SHIP-001) | — |
| Revenue | Sum of list prices of sold pieces in the drop | Not cash received; excludes advances, includes offline sales |
| Today's sales | Not on Home (Analytics, UTC days — SA-ORD-001) | — |
| Unresolved exceptions | **None shown** (refunds owed, expiring claims, failed uploads, stuck holds) | Exception Center needed |

Information overload is not the problem — the Home screen is sparse; it is **static** and shows the wrong numbers for live decisions. Decorative elements (fixed "Good morning" greeting, animated pulse) are harmless but do not carry operational meaning.

## 4. Recommended workflow (summary; full design in [18](18-UI-UX-AUDIT.md#4-redesign-exercise))
1. **Live Command Center** replaces Home while a drop is live: top strip (LIVE red, elapsed, link copy/share), three counters that update live (Available / On hold / Paid), and an **Action queue** sorted by urgency: claims (with time left), late claims, refunds owed, expiring holds, failed uploads.
2. **Code pad**: large numeric/letter pad at thumb reach → shows the piece card with status, holder (buyer, minutes left), and one-tap actions (share link, mark sold if available, open order).
3. **Inline verification**: claim cards in the queue with garment thumbnail, amount type, UTR (copy), time remaining; Verify / Ask to fix / Reject at the bottom.
4. **Hold for buyer** (new, server-side): seller enters a phone number for a commenter → server creates the reservation and a WhatsApp message with the order link — removes the "go to link, find A01" step for buyers who struggle.
5. Push notifications for claims when the app is in the background (the stream app is in the foreground during a live).

## 5. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-RT-001 | HIGH | P0 | No live updates on Home/Products/Payments; Kanban only per selected drop |
| SA-NOT-001 | HIGH | P1 | No notifications at all; fake toggles |
| SA-PAY-007 | HIGH | P1 | Fake UTR locks a piece for 24 h |
| SA-UX-001 | MEDIUM | P1 | No live command view; no global search; red/green semantics inverted |
| SA-PAY-009 | MEDIUM | P1 | Verification card lacks decision context |
| SA-DROP-004 | MEDIUM | P1 | No pre-live readiness gate |
| SA-DROP-006 | LOW | P2 | Product `#CODE` links not honoured |
| SA-INV-001 | MEDIUM | P1 | Mark Sold on reserved; no undo |
