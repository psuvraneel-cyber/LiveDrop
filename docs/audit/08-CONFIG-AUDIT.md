# 08 — Configuration and secret audit

**Confidence: PARTIALLY VERIFIED.** Client configuration correctly intends to use only a Supabase anon key: buyer `env.ts` validates public variables and seller `EnvConfig.validate()` rejects obvious service-role markers. `seller-app/.env.example` exists. No committed `.env` file was identified.

Critical exceptions and risks:

1. **AUD-001:** a tracked staging seed script contains a seller password. Value omitted. Rotate and purge history.
2. **AUD-002:** `run-reaper.mjs:32` prints the first eight characters of the service-role key in dry-run output. GitHub Actions invokes this script with the service-role secret.
3. The root script defaults to a specific hosted Supabase URL in some validation helpers. Environment separation is therefore not consistently enforced.
4. No evidence was available that Vercel/GitHub secrets, production project IDs, or environment scopes are configured correctly.

The anon/publishable key is expected in browser and APK output; it is not itself a secret. No conclusion about deployed bundle leakage can be made without producing and inspecting a clean build.
