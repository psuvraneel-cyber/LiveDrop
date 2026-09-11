# 31 — Release Engineering, Versioning & Deployment Checklist: LiveDrop

**Document Version:** 1.0.0  
**Effective Date:** 2026-09-11  
**Status:** Authoritative Baseline  
**Governing Document:** [`docs/SOURCE-OF-TRUTH.md`](file:///c:/LiveDrop/docs/SOURCE-OF-TRUTH.md)  
**Parent Deployment Spec:** [`docs/28-deployment-architecture.md`](file:///c:/LiveDrop/docs/28-deployment-architecture.md)  

---

## 1. Semantic Versioning Standards

All LiveDrop components follow strict **Semantic Versioning 2.0.0** (`MAJOR.MINOR.PATCH`):
* **MAJOR:** Breaking schema migrations, breaking changes to WhatsApp deep-link contracts, or incompatible RPC updates.
* **MINOR:** New backward-compatible features (e.g. adding code search filter, Bluetooth printer brand support).
* **PATCH:** Bug fixes, performance optimizations, or UI styling patches.

### Component Version Alignment
* **Buyer Webfront:** Managed in `buyer-web/package.json`.
* **Seller Mobile App:** Managed in `seller-app/pubspec.yaml` (`version: 1.0.0+1`).
* **Database Schema:** Managed in `supabase/migrations/` sequentially numbered (`001_...`, `002_...`).

---

## 2. Release Workflows

### 2.1 Webfront Release Process (Next.js)
```
Git Tag (v1.0.0) ──► GitHub Actions CI ──► Build & Bundle Checks ──► Deploy to Cloudflare Pages Production
```
1. Merge pull request to `main` branch.
2. Automated GitHub Actions workflow runs:
   * `npm run lint`
   * `npm run test`
   * `npm run build`
3. If passing, deploys to Cloudflare Pages edge network in < 2 minutes.

### 2.2 Android APK Release Process (Flutter)
1. Bump version and build number in `pubspec.yaml`.
2. Run automated validation:
   * `flutter analyze`
   * `flutter test`
3. Compile signed release binary:
   ```bash
   flutter build apk --release --split-per-abi
   ```
4. Output binary: `build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`.
5. Upload to boutique Google Drive folder for one-tap seller download.

---

## 3. Production Release Checklist

Before releasing any new version to production, verify:
- [ ] All database migrations tested on local and staging environments.
- [ ] RLS policies verified with pgTAP security test suite.
- [ ] No hardcoded secrets or service role keys present in build artifacts.
- [ ] Web bundle size verified `< 300 KB` gzipped.
- [ ] Image compression verified `< 250 KB` per photo.
- [ ] WhatsApp deep-link generation tested on Facebook In-App Browser.
- [ ] Bluetooth thermal PDF label renders legibly at 4×6 inches.

---

## 4. Post-Deployment Smoke Test Checklist

Execute immediately following deployment:
1. **Catalog Load:** Open `/drop/[slug]` in mobile browser. Verify loads in < 1.5s.
2. **Cart Flow:** Add 2 garments to bag. Verify subtotal and shipping calculate correctly.
3. **Reservation Test:** Tap `Confirm & Order via WhatsApp`. Verify items transition to `reserved` on catalog.
4. **WhatsApp Launch:** Verify WhatsApp opens with pre-filled message formatted properly.
5. **Seller App Push:** Verify new order appears under "Pending" in seller Kanban board within 2 seconds.
6. **Payment Confirmation:** Tap `✓ Mark as Paid`. Verify order moves to "Paid" and items show `Sold Out` on web.
7. **Label Render:** Tap `Courier Slip`. Verify 4×6 PDF generates in < 1s with valid barcode.
