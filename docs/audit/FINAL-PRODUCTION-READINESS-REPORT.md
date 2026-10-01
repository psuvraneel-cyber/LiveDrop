# Final production-readiness report

## Decision: NOT READY

This is an evidence-first, read-only audit of commit `f814161fd55ae3f505e7384183b0e2ad12ca41ac`. The architecture is coherent in static code—Flutter seller client + Next buyer client + Supabase/RLS/RPC/Realtime + GitHub Actions reaper—but live correctness is not established. Two credential-handling defects and four release/operations blockers prevent safe production launch.

## Current status

| Area | Status | Confidence |
|---|---|---|
| Buyer web | routes, catalog, cart, checkout and token receipt implemented | PARTIALLY VERIFIED |
| Seller app | auth, approval UI, product/drop/order/payment/shipping surfaces implemented | PARTIALLY VERIFIED |
| Database | 32 migrations, RLS, public views, reservation/payment/fulfilment RPCs present | PARTIALLY VERIFIED |
| Auth/onboarding | self-registration + approval trigger present; review operation incomplete | PARTIALLY VERIFIED |
| Seller/buyer integration | shared data contract and Realtime implementations present | PARTIALLY VERIFIED |
| Payments | manual UPI claim/review design present; no bank verification/reconciliation proof | PARTIALLY VERIFIED |
| Security | static defenses present, but credential defects and no live RLS proof | NOT READY |
| Reliability / concurrency | code and scripts exist; no executed concurrency/reaper proof | UNVERIFIED / BLOCKED |
| Accessibility/performance | targeted tests/specs exist; no full automated or device audit executed | UNVERIFIED / BLOCKED |
| CI/CD | workflows exist but deploy defects found | NOT READY |
| Observability | application error logging only; no production monitoring integration found | NOT READY |

## Production blockers

### P0

1. **AUD-001 CRITICAL:** Revoke the committed staging seller credential, purge it from history, and replace seeded authentication with injected ephemeral test credentials. Do not consider staging safe until completed.
2. **AUD-002 HIGH:** Stop logging any service-role-key material in the reaper; review access to prior logs and rotate the key if it was used with that path.
3. **AUD-003 HIGH:** Repair the Vercel workflow’s nested install command and prove a preview deployment.
4. **AUD-004 HIGH:** Restrict production deployment to protected main/ref and a protected production environment.
5. **AUD-005 HIGH:** Establish a protected staging migration/apply/schema-verification promotion gate with backup/rollback instructions.
6. **AUD-006 HIGH:** Implement or formally operationalize a least-privilege seller approval/onboarding-payment review flow with durable evidence and auditability.

### P1

7. Make deployment health checks fail on unhealthy responses (AUD-007), and make keepalive failures observable (AUD-008).
8. Make web/Flutter test execution reproducible from a clean checkout (AUD-009); run all migration/RLS/lock/payment E2E scenarios on isolated staging.
9. Add privacy-reviewed error tracking, release correlation, reaper metrics, and payment/inventory alerting (AUD-010).

### P2 / defer after safety gates

Physical Android/thermal-printer testing, performance load modelling, enhanced storefront UI, and non-critical analytics can follow launch only after P0/P1 controls and staging proof are complete.

## Critical workflow assessment

Reservation ordering is intended to be database-authoritative through `create_order_with_reservation`; client code does not calculate authoritative totals. Payment is deliberately manual UPI: the seller can falsely affirm a payment because there is no provider/bank proof; buyers are intended to be prevented from direct verification by RPC grants/triggers. This makes seller trust, reconciliation, and audit records launch-critical. Token-order privacy, cross-seller RLS, duplicate UTR handling, late-payment behavior, reaper behavior, and concurrent-winner determinism remain unverified without a running database.

The buyer uses public projection views and the seller uses direct authenticated PostgREST/RPC calls. Latest public view migration 031 filters approved sellers and exposes public support phone/UPI configuration by design. It has no dedicated server API boundary or rate-limit implementation visible in this repository.

## Remaining engineering effort

**Large.** The effort is concrete rather than a percentage: credential incident cleanup; CI/deployment repair; migration promotion design; admin approval flow; hermetic tests; isolated staging data; 24-scenario E2E suite; concurrency/RLS/payment negative tests; telemetry/alerts; performance and accessibility/device validation. This is a production-safety program, not a cosmetic polish pass.

## Evidence appendix

See `audit/FINDINGS.json`, `audit/COMMAND-LOG.md`, and reports 01–11. Key source evidence: committed credential (`scripts/seed-legitimate-staging-drop.mjs:14`), reaper secret-prefix log (`scripts/run-reaper.mjs:32`), nested deployment install (`.github/workflows/deploy-buyer-web-vercel.yml:89`), manual production dispatch (`:106`), non-failing health warning (`:133`), onboarding registration (`seller_registration_screen.dart:116-146`), approval gate (migration 021), public views (migration 031), and buyer RPC boundary (`buyer-catalog.ts:694-828`).
