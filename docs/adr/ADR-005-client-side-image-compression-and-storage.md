# ADR-005: Client-Side Image Compression & CDN Storage Architecture

## Status
**Accepted**

## Context
During live sales, sellers photograph 50 to 100 products in rapid succession (1 photo every 3-5 seconds). Modern smartphone cameras capture images at 12-48 megapixels, producing raw files between 3 MB and 12 MB each.

Uploading raw camera files causes catastrophic failures:
1. **Network Saturation**: Ingesting 50 uncompressed photos (250 MB total) over spotty warehouse 4G takes over 15 minutes, exhausting battery and failing frequently.
2. **Supabase Free-Tier Egress Blowout**: Supabase free tier provides **2 GB/month** of egress bandwidth. If 200 buyers browse a catalog containing 50 uncompressed 5 MB images, 50 GB of egress is consumed in a single live stream, instantly hitting quota limits.
3. **Slow Buyer Web Load**: Downloading 5 MB images on mobile 4G balloons First Contentful Paint (FCP) past 10 seconds.

## Decision
Implement a mandatory **Three-Stage Client-Side Image Pipeline**:

### 1. In-App Compression in Background Isolate
* Before persisting or uploading, the Flutter app downscales and compresses raw camera captures using the `flutter_image_compress` package.
* **Resolution**: Maximum 1200px on the longest edge (aspect ratio preserved).
* **Format**: WebP (fallback to high-efficiency JPEG).
* **Quality**: 80%.
* **Target File Size**: **< 150 KB - 200 KB** (a 95%+ size reduction).
* **Concurrency**: Compression runs inside a background worker thread (`compute()`), preventing UI frame drops during continuous camera shutter clicks.

### 2. Standardized Object Storage Structure
* Compressed files are uploaded to the public Supabase storage bucket `products`:
  ```
  products/{seller_id}/{drop_id}/{product_id}_{timestamp}.webp
  ```

### 3. Edge CDN Caching via Cloudflare
* All image URLs delivered to the buyer webfront are routed through Cloudflare edge proxy with aggressive cache headers:
  ```http
  Cache-Control: public, max-age=31536000, immutable
  ```
* Once an image is requested by the first buyer, Cloudflare caches it at the edge POP in Mumbai/Delhi/Chennai, offloading 95%+ of subsequent image downloads from Supabase egress.

## Alternatives Considered
* **Server-Side Image Resizing (Supabase Image Transformation)**: Requires Supabase Pro tier ($25/mo). Rejected to maintain ₹0 base operation.
* **Third-Party Image CDN (Cloudinary, Imgix)**: Free tiers have low bandwidth limits and introduce third-party API dependencies. Rejected.

## Consequences
* **Positive**: 50 items upload in under 45 seconds total; catalog pages load in < 1.2s on 4G; Supabase egress stays well within the 2 GB monthly free allowance.
* **Negative**: Low-end Android devices spend ~300-500ms of CPU time per photo compressing images in background isolates.

## Security Implications
* Storage bucket enforces RLS: only authenticated sellers can upload to their own folder (`products/{auth.uid()}/*`). Public read access is permitted for catalog display.
