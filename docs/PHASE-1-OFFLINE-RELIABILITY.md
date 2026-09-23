# LiveDrop — Phase 1 Seller Offline Intake Architecture & Reliability

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-22  
**Governing Roles:** Mobile Systems Architect & Flutter Tech Lead  
**Authoritative Index:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Operating Guardrails:** [`AGENTS.md`](file:///c:/LiveDrop/AGENTS.md)  
**Related ADRs:** ADR-006 (Seller Offline Upload Queue)

---

## 1. Context & Mobile Operational Constraints

Independent fashion sellers in India frequently host live broadcasts in high-density wholesale markets or home studios where cellular bandwidth is heavily consumed by upstream video (Instagram Live, WhatsApp video calls).

Under the baseline implementation:
- Capturing a garment photo made an immediate synchronous HTTP upload to Supabase Storage.
- If cellular connectivity dropped or degraded, the upload failed with an unhandled exception.
- The image data and metadata (title, price in Paisa, size) were completely lost from memory.
- The seller had to stop the live stream and retake the photo.

---

## 2. Disk-First Queue Architecture (`offline_intake_queue.dart`)

To achieve zero data loss under intermittent network conditions, the mobile intake system was re-architected into a **disk-first, asynchronous background queue**:

```
[Camera Shutter Click]
        │
        ▼
[ImageService: 1:1 Crop & WebP Compression]
        │
        ▼
[Write Raw Image File to App Storage Disk] ───► Persistent Local Flash Storage
        │
        ▼
[Enqueue Metadata Record in Offline Queue]
        │
        ▼
[Optimistic UI Update: Render in Intake Feed] ───► Instant Seller Feedback (<100ms)
        │
        ▼ (Background Worker Loop)
[Check Network & Storage Connectivity]
        ├─── Connected ────► Upload Image ──► Insert Product RPC ──► Mark Completed
        └─── Disconnected ─► Backoff (2s..60s) ──► Retain on Disk ──► Re-attempt
```

### 2.1 Queue Item Data Structure
```dart
class OfflineQueueItem {
  final String id;              // UUID
  final String dropId;          // Active drop UUID
  final String localImagePath;   // Absolute file URI on device flash
  final String title;           // Item description
  final int pricePaisa;         // Integer Paisa (e.g. 150000 = ₹1,500.00)
  final String size;            // S, M, L, XL, Free Size
  final int retryCount;         // Sequential failure counter
  final QueueItemStatus status; // pending, uploading, completed, failed
  final DateTime createdAt;     // Timestamp
}
```

### 2.2 Exponential Backoff & Fault Tolerance
The background queue processor executes with bounded exponential backoff:
- Initial retry delay: 2,000ms.
- Multiplier: `2^(retryCount)` with jitter.
- Max delay clamp: 60,000ms.
- Max retry threshold: 10 attempts before flagging for manual review.

---

## 3. UI/UX Ergonomics (`camera_intake_screen.dart`)

1. **Queue Pill Indicator:**
   The camera viewfinder and product list headers feature a persistent badge displaying the queue state:
   - When all uploads are finished: Badge indicates `All Synced` or hides.
   - When items are queued: Amber pill badge displays `Queue: N` (e.g., `Queue: 3`).
   - Tapping the badge opens the queue status sheet with manual retry controls.
2. **Local vs Remote Image Rendering:**
   The product thumbnail renderer checks if the image URL is a remote Supabase Storage path (`http...`) or a local file path (`/data/user/...`). If the remote upload is pending, it instantly renders the local disk file using `Image.file()`, providing zero-latency visual confirmation to the seller.

---

## 4. Verification Suite

The offline queue is verified via automated unit and widget tests:
- `seller-app/test/offline_intake_queue_test.dart`:
  - `enqueues item with pending status and persists metadata`: PASSED.
  - `processes queue sequentially and updates status to completed`: PASSED.
  - `applies exponential backoff on simulated upload failure`: PASSED.
  - `retries failed items when network is restored`: PASSED.
  - `preserves integer Paisa price without precision loss`: PASSED.
- Total Flutter test suite: 41 / 41 passing (`flutter test`).
