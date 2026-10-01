# 09 — CI/CD and deployment audit

| Control | Static result | Assessment |
|---|---|---|
| Buyer CI | lint, typecheck, Vitest, build on relevant changes | Good intent; test reproducibility blocked locally |
| Seller CI | analyze, Flutter test, staging debug APK | Good intent; no release signing/distribution process evidenced |
| Vercel deploy | quality gate then preview/prod | AUD-003 invalid nested install path; AUD-004 manual prod dispatch and AUD-007 non-blocking health check |
| Database migrations | 32 files tracked | No CI/staging migration apply, drift check, backup, or rollback gate |
| Reaper | GitHub Actions every 5 minutes | secret-prefix logging defect; schedule execution and secret configuration unverified |
| Keepalive | daily Action | network errors intentionally exit 0, providing no operational signal |

The deployment workflow has a job-level `buyer-web` working directory yet executes `npm --prefix buyer-web ci` at line 89. That resolves to a nested directory and should fail before Vercel deployment. Production dispatch can be selected manually without a ref condition and no `environment: production` protection is declared. A failed health probe emits only a warning. These are release blockers.
