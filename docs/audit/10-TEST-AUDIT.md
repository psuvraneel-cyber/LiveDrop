# 10 — Test-suite audit

| Workflow | Code | Test exists | Depth / confidence |
|---|---|---|---|
| Buyer catalog/cart/checkout UI | `buyer-web/src` | many Vitest/RTL tests | PARTIALLY VERIFIED; full runner blocked |
| Buyer E2E screens | `buyer-web/src/test/e2e` | fixture/component tests | mock/DOM tests, not deployed seller/buyer lifecycle |
| Browser lifecycle | `buyer-web/e2e/buyer-seller-lifecycle.spec.ts` | Playwright spec | present, runtime target not exercised |
| Seller auth/operations | `seller-app/test` | widget/repository tests | present, Flutter test not run |
| DB/RLS/RPC | migrations | `buyer-web/src/test/rpcs.test.ts`, `rls.test.ts` | client/static simulation; no pgTAP test tree found |
| Concurrency | reservations | `scripts/test-concurrency-10-trials.mjs` | script exists, no safe DB execution |
| Failure/reaper | scripts | failure-injection scripts | unexecuted; some need privileged DB credentials |
| Accessibility | buyer UI | `home-accessibility.test.tsx` | automated unit coverage only; no full axe/physical-device evidence |

Existing tests indicate meaningful intent, but passing mocks cannot establish RLS, grants, migrations, locks, Realtime, or manual payment integrity. The full web runner and Flutter analyzer did not complete in this shared workspace; therefore no suite-wide pass is claimed. Required pre-launch work is a clean CI-equivalent run, fresh database migration test, two-seller RLS test, and true browser/mobile staging journey.
