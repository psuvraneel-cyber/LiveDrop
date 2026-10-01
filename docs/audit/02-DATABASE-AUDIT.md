# 02 — Database and data-model audit

**Confidence: PARTIALLY VERIFIED.** Migrations `001` through `032` have lexically contiguous ordering. Applying them from zero, inspecting effective grants/RLS, and executing races are **UNVERIFIED / BLOCKED** because no local Supabase/Docker runtime or safe staging credentials were available.

| Area | Expected | Static actual | Evidence | Risk |
|---|---|---|---|---|
| Atomic reservation | locked, server-calculated order creation | `create_order_with_reservation` is repeatedly replaced, latest in migration 022 | buyer-catalog.ts:694; 022 | Runtime race outcome unverified |
| Payment claims | distinct attempt and verified ledger | migrations 013–015/023 create attempt, claim, verify/reject and ledger routines | buyer-catalog.ts:784,828; seller repository:391,487 | Manual seller verification remains fraud/ops-sensitive |
| Token receipt | non-enumerable token-gated access | `get_order_by_token` final overloads in migration 030 | buyer-catalog.ts:739 | Token/RLS runtime test blocked |
| Seller authorization | ownership plus approval gate | profile approval and drop trigger in migration 021; public views filter approved sellers in 031 | 021, 031 | Admin execution absent from repository |
| Public catalog | projection only | views hide order linkage and include approved live/closed catalog projection | 031 | View grants/RLS runtime test blocked |
| Storage | seller image upload | bucket migration 018 and seller repository storage upload | migration 018; seller repository:742 | MIME/size and cross-tenant runtime checks blocked |

Static contract scan found all RPC names called by the buyer and seller repository defined in migrations. The apparent three unpinned `SECURITY DEFINER` hits were comment text after definitions; inspected function terminators use `SET search_path = public, pg_temp`. No client-side money calculation was found; money fields use integer `*_paisa`.

The migration chain is difficult to roll back: it relies on many `CREATE OR REPLACE`, `DROP VIEW ... CASCADE`, policy replacement, and data updates. No down migrations or automated migration deployment/rollback workflow exists. Treat forward migrations as one-way until a staging rehearsal proves otherwise.
