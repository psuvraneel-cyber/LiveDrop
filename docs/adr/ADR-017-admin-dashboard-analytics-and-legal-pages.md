# ADR-017: Admin Dashboard, Anonymous Visit Analytics and Legal Pages

## Status
**Accepted**, 2026-10-06. Owner request: the admin should see live visitors (and how many have bought before), live drops, sales, payments needing attention and traffic history, with the legal side handled.

## Context
* The `/admin` console (ADR-016) only approved sellers and recorded refunds.
* LiveDrop had no visitor analytics apart from Vercel's aggregate page statistics.
* LiveDrop had no privacy policy, terms of use, refund policy or grievance contact. The DPDP Act 2023 and the Consumer Protection (E-Commerce) Rules 2020 expect these.

## Decision
1. **Live visitors through Realtime presence, not stored.**
   * Every website tab joins the public presence channel `livedrop-site-presence`, keyed by a random per-browser visitor id. It shares the page kind, drop slug, source, device, whether this browser has ordered before, and whether an order is still unpaid.
   * `/admin` listens and counts. Presence is not persisted.
   * A public channel means anyone could read or spoof these anonymous counts. That was accepted because the payload holds no personal data.
2. **Traffic history in `site_page_views` (migration 045).**
   * Rows are written only through `log_page_view` (validated, with a 30-second de-duplication).
   * No IP address, user agent, name, phone or order id is stored.
   * Rows are deleted after 180 days (pg_cron `livedrop-purge-page-views`).
3. **"Buyer" means this browser placed an order.** That comes from the orders the website already remembers locally. There is no cross-device identification and no phone matching (owner choice).
4. **Dashboard reports** are admin-only, read-only RPCs: `admin_live_drops`, `admin_sales_overview(days)`, `admin_payment_attention`, `admin_traffic(days)`.
   * Revenue is money **verified by sellers** (payment attempts `verified`), in integer paisa.
   * No buyer contact details are returned.
5. **Consent and choice.**
   * A one-time notice explains anonymous counting, with "Don't count my visits".
   * `/privacy` has an on/off switch.
   * Do Not Track and Global Privacy Control turn counting off.
   * Seller and admin pages are never counted.
6. **Legal pages:** `/privacy`, `/terms`, `/refund-policy` and `/grievance`, linked from the footer and from a notice at checkout.
   * Business facts are owner inputs in `buyer-web/src/lib/legal/legal-config.ts`: operator name and address, contact details, Grievance Officer, jurisdiction, refund and damage-report windows.
   * Missing values render as visible placeholders, and `/admin` lists them.
   * The texts describe LiveDrop's actual flows (direct UPI to sellers, seller-made refunds). They are a draft for legal review, not legal advice.

## Consequences
* The owner sees live and historical activity without collecting personal data for analytics.
* Counts are approximate: opt-outs, Do Not Track and blocked storage are not counted, and a person on two devices counts twice.
* The owner must fill in the legal config and have the texts reviewed before real customers use the site.
* Verification: SQL suite 26; post-check H30; `analytics-and-legal.test.tsx`; `admin-console.test.tsx`.
