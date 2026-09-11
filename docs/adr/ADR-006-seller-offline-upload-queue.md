# ADR-006: Seller Local SQLite Offline Ingestion Queue

## Status
**Accepted**

## Context
Indian boutique sellers frequently stream or store inventory in basement shops, dense markets, or warehouse facilities with erratic Wi-Fi and fluctuating 3G/4G connectivity. If a seller is photographing 50 items before a live stream and network drops midway:
* A synchronous upload architecture would lock the UI, throw error dialogs, or discard un-uploaded photos.
* Forcing the seller to wait for an upload progress bar after every single photo makes batch ingestion of 50 items take 20+ minutes instead of 3 minutes.

## Decision
Implement a **Decoupled Local SQLite Ingestion Queue** within the Flutter seller application:

### 1. Local-First Capture Pipeline
* When the seller taps the camera shutter, the photo and product metadata (flash-code, price, size) are immediately saved to device storage and inserted into a local **SQLite** database (`sqflite`).
* The UI instantly unlocks and increments the flash-code counter (e.g., from `01` to `02`), allowing the seller to take the next photo immediately without network delay.

### 2. Queue Schema & State Lifecycle
```
[User Taps Shutter]
        │
        ▼
Insert into SQLite (status: 'pending')
        │
        ├── Worker Background Loop
        ▼
status: 'compressing' ──> Saves compressed WebP to cache
        │
        ▼
status: 'uploading'   ──> Uploads image to Supabase Storage
        │
        ▼
status: 'syncing_db'  ──> Inserts product row in PostgreSQL
        │
        ▼
status: 'synced'      ──> Deletes local cached file, retains metadata
```

* **Retry Strategy**: Failed uploads enter status `'failed'` with an exponential backoff retry counter (`retry_count`). The queue worker retries automatically upon network reconnection (monitored via `connectivity_plus`).

### 3. Clear Status Indicators in UI
* The seller app header displays a persistent sync badge:
  * Green check: `All items synced (50/50)`
  * Pulsing blue: `Syncing 12 items...`
  * Red warning: `Offline (8 items queued locally)`
* Drops cannot be transitioned to `Live` until all queued items reach `synced` status.

## Alternatives Considered
* **Hive Key-Value Store**: Lightweight, but lacks transactional schema migration and robust relational queries across drops and items. Rejected.
* **Full Offline Two-Way Sync (CouchDB / WatermelonDB)**: Over-engineered for an MVP where only seller-side one-way product creation needs offline resilience. Rejected.

## Consequences
* **Positive**: Sellers can photograph 50 products in under 3 minutes even in total airplane mode; zero data loss during network drops.
* **Negative**: Requires local storage permission and background worker lifecycle management in Flutter.

## Security Implications
Local SQLite database stores un-synced product metadata and temporary image paths. Cleaned up upon successful upload.
