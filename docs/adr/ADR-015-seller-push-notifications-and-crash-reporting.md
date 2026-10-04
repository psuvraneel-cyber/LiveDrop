# ADR-015: Seller Push Notifications and Crash Reporting (Firebase)

## Status
**Accepted**, 2026-10-04. The project owner created the Firebase project `livedrop-eaf3d` for SA-OBS-001 and SA-NOT-001.

## Context
* **SA-OBS-001:** the seller app had no crash reporting, and 33 error handlers discarded errors silently.
* **SA-NOT-001:** the seller app had no notifications. A buyer's payment claim could sit unseen during a live.

## Decision
1. **Firebase Crashlytics in the app** (`AppLog`):
   * Uncaught Flutter and platform errors are reported as fatal.
   * Handled errors are reported through `AppLog.error`.
   * Debug builds never report.
   * Reports are tagged with the seller's account id only.
2. **Push via Firebase Cloud Messaging HTTP v1:**
   * The app registers its token with `register_push_token` and removes it on sign-out.
   * The database queues messages in `push_outbox`. Triggers queue them for a new order and for a buyer's UTR (on time or late), and respect the seller's preferences (`notify_new_orders`, `notify_payment_claims`).
   * Messages carry the order code and amount, never buyer contact details.
3. **Delivery:**
   * The Edge Function `push-dispatch` claims due messages (`claim_push_batch`, service_role only), sends them to every device of the seller, records the result (`complete_push`) and forgets unregistered tokens.
   * pg_net wakes it right after a message is queued; a pg_cron job every minute is the backstop.
   * Retries: up to 5 attempts, with growing delays.
4. **Configuration and secrets:**
   * `google-services.json` stays gitignored. CI writes it from the `GOOGLE_SERVICES_JSON` secret; without it, the app builds without Firebase.
   * The FCM service-account key exists only as the Supabase Edge Function secret `FCM_SERVICE_ACCOUNT`.

## Consequences
* Sellers are alerted within seconds while the app is closed, and taps open Payments or Orders.
* The owner must create the service-account key, store it as a Supabase secret, and deploy the function.
* Verification:
  * SQL suite 23;
  * `supabase/functions/push-dispatch/index.test.ts`;
  * Flutter `crash_reporting_push_test.dart`;
  * post-check H26.
