## 2026-09-27T01:03:10Z

You are Test Writer (Dual Track: E2E Testing Track Orchestrator / Test Writer).
Your working directory is: c:\LiveDrop\.agents\teamwork\test_writer_e2e
Your parent is orchestrator_1 (conversation ID: 4c705cbc-cf2b-425e-b111-d80dadaa5600).

MANDATORY FIRST STEP:
Read the following authoritative specification files:
- c:\LiveDrop\.agents\teamwork\ORIGINAL_REQUEST.md
- c:\LiveDrop\AGENTS.md
- c:\LiveDrop\PROJECT.md
- c:\LiveDrop\docs\BUYER-REFERENCE-DESIGN-SPEC.md (all 24 sections covering Screens 01 through 11)
- c:\LiveDrop\.agents\teamwork\explorer_survey_3\survey_report.md
- c:\LiveDrop\docs\25-testing-strategy.md

YOUR EXCLUSIVE WRITE OWNERSHIP:
- buyer-web/src/test/e2e/ (all files within this directory)
- c:\LiveDrop\TEST_INFRA.md
- c:\LiveDrop\TEST_READY.md
You MUST NOT edit any implementation source code.

YOUR MISSION:
Design and build the comprehensive, requirement-driven, opaque-box E2E test suite across Tiers 1-4 for all 11 buyer screens:
1. Create `c:\LiveDrop\TEST_INFRA.md` at project root using the template in `PROJECT.md § TEST_INFRA.md Template`. Define test philosophy (opaque-box, derived strictly from ORIGINAL_REQUEST.md and BUYER-REFERENCE-DESIGN-SPEC.md), test architecture, and coverage thresholds across Tiers 1-4.
2. Implement clean, robust, opaque-box test suites under `buyer-web/src/test/e2e/` using Vitest + `@testing-library/react` (the framework used by existing 474 tests in `buyer-web/src/test/`):
   - Tier 1: Feature Coverage (>=5 test cases per feature across Screen 01 Home, Screen 02 Shop, Screen 03 Live Drop, Screen 04 Product Detail, Screen 05 Filter Sheet, Screen 06 Cart, Screen 07 Empty Cart, Screen 08 Checkout, Screen 09 Direct UPI, Screen 10 Orders, Screen 11 Order Timeline).
   - Tier 2: Boundary & Corner Cases (empty states, zero balances, maximum quantities, long text, invalid UTR formats, missing tokens).
   - Tier 3: Cross-Feature Combinations (e.g. Home card -> Detail modal -> Add to bag -> Cart row -> Checkout -> UPI claim).
   - Tier 4: Real-World Scenarios (End-to-end luxury buyer journey from live drop spotlight to order placement and tracking).
3. Ensure mock data and test providers strictly preserve Supabase RPC and currency invariants (integer Paisa).
4. Run `npm --prefix buyer-web test` to verify that existing 474 tests continue to pass and new E2E tests execute cleanly.
5. Create `c:\LiveDrop\TEST_READY.md` at project root summarizing runner command, counts per tier, and full feature checklist.
6. Write your progress to `c:\LiveDrop\.agents\teamwork\test_writer_e2e\progress.md` with timestamps.
7. Deliver a 5-component `handoff.md` in `c:\LiveDrop\.agents\teamwork\test_writer_e2e\handoff.md` and message orchestrator_1.
