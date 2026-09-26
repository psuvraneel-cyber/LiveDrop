## 2026-09-26T19:33:10Z

You are Worker M1 (Milestone 1 Implementation: Global Shared Primitives & Tokens - Phase B).
Your working directory is: c:\LiveDrop\.agents\teamwork\worker_m1
Your parent is orchestrator_1 (conversation ID: 4c705cbc-cf2b-425e-b111-d80dadaa5600).

MANDATORY INTEGRITY WARNING:
DO NOT CHEAT. All implementations must be genuine. DO NOT hardcode test results, create dummy/facade implementations, or circumvent the intended task. A auditor will independently verify your work. Integrity violations WILL be detected and your work WILL be rejected.

MANDATORY FIRST STEP:
Read the following authoritative specification files:
- c:\LiveDrop\.agents\teamwork\ORIGINAL_REQUEST.md
- c:\LiveDrop\AGENTS.md
- c:\LiveDrop\PROJECT.md
- c:\LiveDrop\docs\BUYER-REFERENCE-DESIGN-SPEC.md (Sections 1-8: Design Tokens, Typography, Colors, GlobalBuyerHeader, MobileBottomDock)
- c:\LiveDrop\.agents\teamwork\explorer_survey_1\survey_report.md
- c:\LiveDrop\.agents\teamwork\explorer_survey_1\handoff.md
- c:\LiveDrop\docs\35-engineering-conventions.md

YOUR EXCLUSIVE WRITE OWNERSHIP:
- buyer-web/src/app/globals.css
- buyer-web/src/components/navigation/GlobalBuyerHeader.tsx
- buyer-web/src/components/navigation/MobileBottomDock.tsx
You MUST NOT edit any other production or test files.

YOUR MISSION:
Implement Milestone 1 (Phase B) to establish luxury shared visual primitives:
1. In `buyer-web/src/app/globals.css`:
   - Under the Tailwind CSS v4 `@theme` directive, add font mappings:
     `--font-serif: var(--font-display);`
     `--font-sans: var(--font-sans);`
     This ensures standard utility classes like `font-serif` map to Cormorant Garamond.
   - Add missing luxury color tokens to `@theme`:
     `--color-ld-border-gold-strong: rgba(212, 175, 55, 0.4);`
     `--color-ld-sold: #4A4A52;`
     `--color-ld-gold-muted: #8A7B4C;`
     `--color-ld-burgundy: #2C1820;`
   - Ensure `.ld-has-bottom-dock` padding accommodates 60px visible bar:
     `padding-bottom: calc(60px + env(safe-area-inset-bottom, 0px) + 16px);`
2. In `buyer-web/src/components/navigation/GlobalBuyerHeader.tsx`:
   - Verify 56px sticky luxury header.
   - Ensure the sparkle icon next to the monogram is 18px (`w-[18px] h-[18px]`).
   - Ensure the shopping bag badge is circular 18×18px with centered counter text (`min-w-[18px] h-[18px] rounded-full text-[10px] font-bold`).
   - Ensure header action touch targets maintain at least 44-48px clickable padding.
   - Maintain all existing props, test IDs (`global-buyer-header`, `header-back-button`, `header-bag-button`, etc.), and route support.
3. In `buyer-web/src/components/navigation/MobileBottomDock.tsx`:
   - Set inner dock height to 60px (`h-[60px]`).
   - Set inactive tab text and icon color to `#AAA49A` (`text-[#AAA49A]`).
   - Maintain active tab indicator in champagne gold (`#D4AF37`).
   - Maintain existing props, test IDs, and route suppression on `/drop/*` for now (to preserve existing 474/474 tests).
4. Run all automated gates locally and report exact terminal outputs:
   - `npm --prefix buyer-web run typecheck`
   - `npm --prefix buyer-web run lint`
   - `npm --prefix buyer-web test`
   - `npm --prefix buyer-web run build`
5. Write your progress to `c:\LiveDrop\.agents\teamwork\worker_m1\progress.md` with timestamps.
6. Deliver a 5-component `handoff.md` (Observation, Logic Chain, Caveats, Conclusion, Verification Method) in `c:\LiveDrop\.agents\teamwork\worker_m1\handoff.md` and message orchestrator_1.
