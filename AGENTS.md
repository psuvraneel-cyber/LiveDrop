# LiveDrop — AI Coding Agent Operating Rules & Guardrails

## 1. Mandatory AI Agent Mandate
You are an autonomous or semi-autonomous AI coding assistant working in the LiveDrop repository. You MUST operate under the constraints and protocols defined herein.

**LiveDrop has completed its pre-implementation specification gate.**
All architecture, database schemas, security models, business rules, and API contracts are fully documented and frozen under `docs/`.

---

## 2. Core Execution Protocol (The 6-Step Loop)
For EVERY assigned task or modification, you MUST follow this loop:

```
[1. READ] ───> [2. PLAN] ───> [3. CHANGE] ───> [4. TEST] ───> [5. REVIEW] ───> [6. DOCUMENT]
```

1. **READ**: Read the authoritative specification documents governing your task in [docs/SOURCE-OF-TRUTH.md](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md). Read existing files and interfaces before touching them.
2. **PLAN**: Formulate a concise, atomic checklist of changes. Identify impacted files, tests, and security boundaries.
3. **CHANGE**: Write clean, idiomatic code adhering to [35-engineering-conventions.md](file:///c:/LiveDrop/docs/35-engineering-conventions.md).
4. **TEST**: Execute tests locally. Verify exit code 0. **NEVER assume tests pass without running them.**
5. **REVIEW**: Inspect your own `git diff`. Verify no unintended edits, secrets, or formatting regressions.
6. **DOCUMENT**: Update the [Requirements Traceability Matrix](file:///c:/LiveDrop/docs/06-requirements-traceability-matrix.md) and relevant API/schema docs.

---

## 3. Strict Absolute Rules (Guardrails)

1. **NO Requirement Invention**: Never invent features, fields, or workflows not documented in the PRD, Functional Spec, or an approved ADR.
2. **NO Weakening of RLS / Security**: Never disable Row-Level Security (`ALTER TABLE ... DISABLE ROW LEVEL SECURITY`), drop RLS policies, or grant public write permissions to bypass authorization errors.
3. **NO Service-Role Credential Leakage**: The Supabase Service-Role key MUST NEVER appear in client-facing environments (`NEXT_PUBLIC_*`, Flutter assets, or browser bundles).
4. **NO Client-Only Validation**: Never rely solely on client JavaScript or Dart for pricing, inventory counts, or order totals. Server/RPC validation is mandatory.
5. **NO Floating-Point Currency**: Money MUST always be represented as an integer in Paisa (`150000` = ₹1,500.00). Never use `float` or `double`.
6. **NO Direct UI Database Mutations**: UI components must never call raw `supabase.from('products').update(...)` for state transitions. Use defined RPCs.
7. **NO Unpinned PostgreSQL Search Path**: All `SECURITY DEFINER` functions must include `SET search_path = public, pg_temp`.
8. **NO Unchecked Claims**: Do not declare a feature complete or bug fixed without showing terminal command test outputs.

---

## 4. Architectural Authority Index
Refer to these authoritative specifications before coding:
* **Source of Authority**: [docs/SOURCE-OF-TRUTH.md](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)
* **Functional Spec**: [docs/07-functional-specification.md](file:///c:/LiveDrop/docs/07-functional-specification.md)
* **Database & DDL**: [docs/12-database-design.md](file:///c:/LiveDrop/docs/12-database-design.md)
* **API Contracts**: [docs/13-api-contract.md](file:///c:/LiveDrop/docs/13-api-contract.md)
* **Realtime Events**: [docs/14-realtime-contract.md](file:///c:/LiveDrop/docs/14-realtime-contract.md)
* **Concurrency & Locks**: [docs/15-concurrency-and-reservation-spec.md](file:///c:/LiveDrop/docs/15-concurrency-and-reservation-spec.md)
* **Security & RLS**: [docs/16-security-architecture.md](file:///c:/LiveDrop/docs/16-security-architecture.md)
* **Business Rules**: [docs/19-validation-and-business-rules.md](file:///c:/LiveDrop/docs/19-validation-and-business-rules.md)
* **Testing Strategy**: [docs/25-testing-strategy.md](file:///c:/LiveDrop/docs/25-testing-strategy.md)
* **Implementation Plan**: [docs/32-implementation-plan.md](file:///c:/LiveDrop/docs/32-implementation-plan.md)
* **Definition of Done**: [docs/34-definition-of-done.md](file:///c:/LiveDrop/docs/34-definition-of-done.md)
* **Engineering Conventions**: [docs/35-engineering-conventions.md](file:///c:/LiveDrop/docs/35-engineering-conventions.md)
* **Architecture Decision Records**: [docs/39-architecture-decision-records.md](file:///c:/LiveDrop/docs/39-architecture-decision-records.md)
