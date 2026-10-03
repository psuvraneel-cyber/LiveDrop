# ADR-011: Reservation Hold Expiry Inside the Database

## Status
**Accepted** — 2026-10-03. Approved by the project owner via the seller-app audit remediation request.

## Context
Seller-app audit findings:
* **SA-OPS-001:** expired holds were released only by a GitHub Actions cron (`reaper-cron.yml`, every 5 minutes on paper). GitHub runs scheduled workflows on a best-effort basis, so a piece could stay unbuyable long after its hold expired. ADR-009 called for `release_expired_holds()` at the start of checkout, but no migration implemented it.
* **SA-PAY-003:** the reaper cancelled orders and expired attempts even when the buyer had already submitted a payment claim (UTR), so money already sent dropped out of the seller's queue.
* **SA-PAY-005:** `force_release_hold` and `close_drop` could release a piece while a claim was waiting.
* **SA-INT-002:** verify and the reaper locked orders and attempts in opposite order and could deadlock.

## Decision
1. **pg_cron is the primary scheduler.** Migration 036 schedules `SELECT public.release_expired_holds();` every minute as job `livedrop-release-expired-holds` when pg_cron is available. Where it is not, the migration raises a NOTICE and does nothing.
2. **Lazy expiry at checkout.** `create_order_with_reservation` releases a cart piece whose hold belongs to a pending, expired, unclaimed order, through the internal helper `release_stale_hold(p_order_id)`. The helper never waits for a lock (SKIP LOCKED) and changes nothing if any lock is busy.
3. **The GitHub Actions reaper is demoted to a backup trigger.** It stays because the reaper is idempotent, and it is the only automatic trigger where pg_cron is missing.
4. **Claimed payments never auto-expire.** An order with an attempt in `buyer_claimed`, `awaiting_seller_verification` or `late_claim_pending_review` is never cancelled or expired by the reaper, lazy expiry, `force_release_hold` (returns `PAYMENT_CLAIM_PENDING`) or `close_drop`. Claimed attempts stay verifiable after their window; the seller app labels them "Overdue — verify or reject".
5. **Lock order** everywhere is `orders → payment_attempts → products` (products `ORDER BY id`). Background work uses SKIP LOCKED.

## Consequences
* **Positive:** expired holds are released within about a minute (or at once on checkout). A buyer who has paid cannot lose the piece to a timer. Verify and the reaper cannot deadlock.
* **Negative:** a buyer who submits a claim and a seller who never acts can hold a piece indefinitely. Overdue claims are surfaced to the seller, but resolution is manual. pg_cron must be enabled on the hosted project by the owner.
* **Verification:** SQL 13.8, 14.3, 14.4, 14.5, 16.1b, 16.1c, 16.2, 19.1, 19.2, 19.3, 19.10a–c, 19.11, 19.12, 19.15, 19.18; hosted H8, H17, H18, H19 (owner). The pg_cron path was exercised only against a stub `cron` schema; the local cluster has no pg_cron.
