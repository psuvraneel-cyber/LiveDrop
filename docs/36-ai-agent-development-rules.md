# LiveDrop — AI Agent Development Rules & Operational Protocol

## 1. Scope & Authority
This document defines the binding operational protocol for any autonomous or semi-autonomous AI coding assistant (including Antigravity, Claude Code, Gemini CLI, or Cursor) working within the LiveDrop repository.

Violating these rules violates the architectural integrity of the system and invalidates implementation readiness.

---

## 2. Core Execution Protocol: The 6-Step Loop
Every AI agent MUST follow this loop for every assigned task:

```
┌─────────┐     ┌──────────┐     ┌──────────┐
│ 1. READ │ ──> │ 2. PLAN  │ ──> │ 3. CHANGE│
└─────────┘     └──────────┘     └──────────┘
                                      │
┌──────────────┐     ┌──────────┐     │
│ 6. DOCUMENT  │ <── │ 5. REVIEW│ <───┘ (4. TEST)
└──────────────┘     └──────────┘
```

### Step 1: READ
* Read the authoritative documents governing the target area as specified in [SOURCE-OF-TRUTH.md](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md).
* Read existing code, interfaces, and test files before attempting any edit.
* Never assume the state of a file based on memory or filenames alone.

### Step 2: PLAN
* Formulate an atomic implementation plan.
* Identify impacted files, contracts, tests, and security boundaries.
* If a task introduces architectural ambiguity or conflicts with an existing spec, STOP and notify the human operator. Do not guess.

### Step 3: CHANGE
* Make focused, minimal, and correct modifications.
* Follow [Engineering Conventions](file:///c:/LiveDrop/docs/35-engineering-conventions.md) strictly.
* Do not introduce unrelated refactorings or cosmetic changes to untouched modules.

### Step 4: TEST
* Write unit, integration, or E2E tests verifying the new behavior.
* Execute the tests locally using terminal tools.
* **NEVER** claim tests passed without running them and verifying stdout.

### Step 5: REVIEW
* Run `git diff` or inspect changes to ensure no secrets, unintended edits, or broken formatting were introduced.
* Run linters (`npm run lint`, `flutter analyze`).

### Step 6: DOCUMENT
* Update relevant documentation artifacts, API contracts, or the Traceability Matrix if requirements or signatures were expanded.
* Write clean conventional commit messages.

---

## 3. Strict Prohibitions (Absolute Guardrails)

1. **NO Requirement Invention**: Never invent new business logic, fields, or user flows not defined in the PRD, Functional Spec, or an approved ADR.
2. **NO Weakening of Security / RLS**: Never disable Row-Level Security (`ALTER TABLE ... DISABLE ROW LEVEL SECURITY`), drop RLS policies, or grant public write permissions to circumvent authorization errors.
3. **NO Service-Role Credential Leakage**: The Supabase Service-Role key MUST NEVER be placed in `NEXT_PUBLIC_*` environment variables, client bundles, or Flutter app assets.
4. **NO Client-Only Validation for Critical Rules**: Never rely exclusively on JavaScript or Dart validation for pricing, inventory counts, or phone verification. Server/RPC validation is mandatory.
5. **NO Floating Point Currency**: Never store or calculate money using floating point types (`double`, `float`). Currency must always be integer Paisa.
6. **NO Direct Database Mutation from UI**: UI components must never issue raw `supabase.from('products').update(...)` for state transitions. Use defined RPCs.
7. **NO Unpinned Search Path in PostgreSQL Functions**: All `SECURITY DEFINER` functions must include `SET search_path = public, pg_temp`.
8. **NO Silent Error Swallowing**: Catch blocks must either handle and return a typed error or rethrow. Empty catch blocks (`catch (e) {}`) are forbidden.

---

## 4. Verification Checklist for Coding Agents
Before declaring any task or phase complete, the agent must check off the following:
* [ ] Code conforms to [35-engineering-conventions.md](file:///c:/LiveDrop/docs/35-engineering-conventions.md).
* [ ] All new functions and public APIs are typed (no `any`).
* [ ] All database changes have an accompanying migration script.
* [ ] Automated tests were executed and passed.
* [ ] No secrets or test keys were hardcoded into application source files.
* [ ] Traceability matrix in [06-requirements-traceability-matrix.md](file:///c:/LiveDrop/docs/06-requirements-traceability-matrix.md) was updated.
