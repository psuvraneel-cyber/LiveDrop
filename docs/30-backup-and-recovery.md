# 30 — Backup, Recovery & Data Retention Specification: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Technical Design:** [`docs/04-technical-design.md`](file:///c:/LiveDrop/docs/04-technical-design.md)  

---

## 1. Backup Strategy (MVP Scope)

LiveDrop utilizes Supabase Cloud’s built-in PostgreSQL backup capabilities supplemented by automated logical export scripts:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                             BACKUP STRATEGY                                 │
├────────────────────┬─────────────────────────────┬──────────────────────────┤
│ Backup Type        │ Frequency & Schedule        │ Retention Policy         │
├────────────────────┼─────────────────────────────┼──────────────────────────┤
│ **Physical WAL**   │ Continuous (Supabase Cloud) │ 7 Days (Point-in-Time)   │
│ **Logical Dump**   │ Weekly / Pre-Migration      │ 30 Days (Compressed SQL) │
│ (`pg_dump`)        │ via GitHub Actions / Local  │                          │
│ **Image Storage**  │ S3 Object Versioning        │ Lifetime of active drop  │
└────────────────────┴─────────────────────────────┴──────────────────────────┘
```

### 1.1 Automated Weekly Logical Backup Script
```bash
#!/bin/bash
# Backup LiveDrop Production Database
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_DIR="./backups"
mkdir -p $BACKUP_DIR

echo "Exporting schema and data for LiveDrop..."
pg_dump "$DATABASE_URL" \
  --format=custom \
  --no-owner \
  --no-privileges \
  --file="$BACKUP_DIR/livedrop_prod_$TIMESTAMP.dump"

echo "Backup completed: $BACKUP_DIR/livedrop_prod_$TIMESTAMP.dump"
```

---

## 2. Migration Safety & Rollback Playbook

1. **Transactional Migrations:** Every schema migration is wrapped inside a single atomic PostgreSQL transaction:
   ```sql
   BEGIN;
   -- Migration DDL operations
   COMMIT;
   ```
2. **Mandatory Down-Migration:** For every `XXX_migration.sql`, an inverted rollback script `XXX_migration.down.sql` must be committed and tested on staging.
3. **Zero-Downtime Column Addition:** New columns must be added as `NULL` or with explicit safe defaults to prevent table locking during live broadcasts.

---

## 3. Accidental Deletion Recovery Procedures

* **Accidental Drop Closure:** Drop can be duplicated into a new drop session with a single click in the seller app.
* **Accidental Order Cancellation:** Order can be transitioned from `cancelled` back to `pending` by the seller via authenticated administrative SQL or Flutter long-press override, provided the garments have not been bought by another customer.
* **Drop Deletion Guard:** The database schema enforces `ON DELETE RESTRICT` on products linked to orders, mathematically preventing the accidental deletion of fulfilled order histories.

---

## 4. Storage Lifecycle & Data Retention Policy

To preserve the 500 MB database and 1 GB image storage quotas on the free tier:

| Data Entity | Retention Period | Archival / Cleanup Routine |
|---|---|---|
| **Active Live Drops** | Permanent during broadcast | Retained in hot storage |
| **Closed Drops (> 6 Months)** | 180 Days | Products and images archived to offline cold dump; thumbnails removed |
| **Cancelled Orders** | 30 Days | Expired orders older than 30 days purged by monthly maintenance cron |
| **Fulfilled Orders (`shipped`)** | 365 Days | Retained for annual accounting and tax compliance; then exported to CSV |
