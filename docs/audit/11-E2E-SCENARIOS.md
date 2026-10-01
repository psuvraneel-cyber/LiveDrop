# 11 — E2E scenario matrix

All scenarios below are **UNVERIFIED / BLOCKED**, not failures of implementation. Preconditions missing: isolated staging project, disposable approved sellers/buyers, service-role maintenance runner, browser/device target, and explicit permission to create test data.

| # | Scenario | Expected invariant | Required evidence |
|---|---|---|---|
| 1–4 | valid/invalid auth, persistence, onboarding | session/approval behavior matches policy | Flutter device + staging logs |
| 5–8 | product/drop/public consistency | exact code/image/price/status propagate | seller write plus anonymous browser read |
| 9 | 2 and 10 buyers, one item | exactly one reservation/order | concurrent authenticated/anon SQL trace |
| 10–11 | cart and checkout reload | cart contract; no duplicate order | browser storage and DB counts |
| 12–15 | UTR claim, verify, sync, reject | only owner verifies; buyer sees final state | payment attempt/ledger/order records |
| 16–17 | expiry and late payment | release/recovery preserves no double allocation | controlled clock and reaper logs |
| 18–19 | fulfilment/shipping | only paid ready order ships; receipt updates | RPC responses and token receipt |
| 20 | token security | foreign/malformed token reveals nothing | negative request capture |
| 21–24 | network, retry, Realtime, RPC faults | actionable errors, preserved state, safe retry | browser/device fault injection |

Run these only against staging with cleanup identifiers and snapshot before/after counts. Do not use a production merchant or real payment.
