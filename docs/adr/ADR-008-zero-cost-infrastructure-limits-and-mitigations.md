# ADR-008: Zero-Cost Infrastructure Limits, Free-Tier Realities & Mitigations

## Status
**Accepted**

## Context
The LiveDrop Product Brief and PRD propose a **₹0 bootstrap operating model** to enable single-boutique sellers to run live drops with zero monthly software overhead.

While modern cloud free tiers enable zero-cost hosting during MVP development and initial validation, unmonitored free-tier usage carries significant operational risks if limits are exceeded or terms change:
1. **Supabase Inactivity Pausing**: Free projects automatically pause after 7 consecutive days of zero database queries. Unpausing requires manual dashboard intervention and takes 2-5 minutes, which would destroy an active weekend live drop.
2. **Supabase Storage & Egress Caps**:
   * Storage: 1 GB cap.
   * Egress Bandwidth: 2 GB / month cap.
   * Database Disk Space: 500 MB cap.
3. **Cloudflare Pages / Vercel Web Hosting**: Generous static request quotas, but subject to fair-use policies.

## Decision
Establish an **Authoritative Free-Tier Governance & Mitigation Strategy**:

### 1. Inactivity Pause Mitigation (Automated Daily Keepalive)
* Deploy a lightweight, automated GitHub Action workflow scheduled daily via cron:
  ```yaml
  name: Supabase Health Keepalive
  on:
    schedule:
      - cron: '0 4 * * *' # Runs daily at 04:00 UTC
  jobs:
    ping:
      runs-on: ubuntu-latest
      steps:
        - name: Keep Database Active
          run: |
            curl -s -f -X GET "${{ secrets.SUPABASE_URL }}/rest/v1/drops?select=id&limit=1" \
              -H "apikey: ${{ secrets.SUPABASE_ANON_KEY }}" \
              -H "Authorization: Bearer ${{ secrets.SUPABASE_ANON_KEY }}" > /dev/null
  ```
* This ensures the database instance is touched daily, permanently preventing 7-day inactivity pauses.

### 2. Egress Bandwidth Mitigation (Edge CDN Caching)
* Egress is capped at 2 GB/month. With un-cached traffic, 10 drops could exceed this quota.
* **Mitigation**: Route all image asset traffic through Cloudflare CDN with `Cache-Control: public, max-age=31536000, immutable`. Cloudflare serves 95%+ of photo requests from edge caches, keeping Supabase origin egress under 100 MB/month.

### 3. Storage Cleanup & Retention Policy
* Total storage is capped at 1 GB. At 150 KB per compressed photo, 1 GB accommodates ~6,500 active products.
* **Mitigation**: Implement a scheduled database purge routine (`purge_archived_drops`) that archives product records older than 180 days and deletes their associated images from the storage bucket.

### 4. Proactive Upgrade Triggers
Define explicit thresholds where the system must transition from Free Tier to paid Supabase Pro ($25/mo / ~₹2,100/mo):
* **Database Size**: Exceeds 400 MB (80% of 500 MB limit).
* **Monthly Egress**: Exceeds 1.6 GB (80% of 2 GB limit).
* **Active Boutiques**: System expands beyond 5 concurrent active boutique sellers.

## Alternatives Considered
* **Self-Hosting on AWS/Hetzner VPS**: Requires Linux sysadmin maintenance, manual SSL management, Postgres backups, and Docker setups, incurring ₹500 - ₹1,500/mo minimum costs immediately. Rejected.
* **Firebase Free Tier**: Cloud Firestore pricing scales with document reads/writes, making flash live drops with 500 concurrent buyers polling catalog state expensive and unpredictable. Rejected.

## Consequences
* **Positive**: 100% free operations during bootstrap and pilot drops; automated keepalive protects against unexpected project dormancy; hard guardrails prevent surprise billing.
* **Negative**: Scaling beyond ~5 active boutiques requires upgrading to Supabase Pro ($25/mo).
