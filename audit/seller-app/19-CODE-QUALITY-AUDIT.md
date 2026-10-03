# 19 — Code Quality and Crash/Bug Investigation

| | |
|---|---|
| Audited commit | `94ccfc9` |
| Date | 2026-10-03 |
| Scope | Brief sections 28 (crash/bug hunt) and 29 (code quality) for `seller-app/lib` (14,764 lines) |
| Executed | `flutter analyze` (strict casts/inference/raw types) → **No issues found**; pattern searches; audit tests T01 (crash), T16–T19, T25 (queue races) |
| Not executed | Device crash collection (no crash reporting exists) |

## 1. Crash / bug hunt (section 28)

| Pattern | Count / location | Assessment |
|---|---|---|
| TODO / FIXME / `assert(false)` | 0 in `lib/` (1 TODO in `android/app/build.gradle.kts:35` about release signing) | The one TODO is a P0 (SA-AND-001) |
| Empty / swallowing catch blocks | **33 `catch (_)`** (dashboard ×5, main ×4, url helper ×5, haptics ×5, intake ×3, realtime ×2, repository ×1, queue ×1, registration ×2, others) | Hides real failures (SA-OBS-001); haptics/url ones are acceptable |
| Force unwraps (`!.`) | 29 | Mostly guarded (`_cameraController!` after null checks, `_formKey.currentState!`); no crash found from these |
| Null assumptions | `fromJson` hard casts (`as String`, `as int`) on nullable DB columns, e.g. `products.title`/`size` are nullable in 003 but cast non-null (`models.dart:322-324`) | Crash only if rows are written outside the app; Realtime parse errors swallowed |
| String indexing | `_getInitials` `parts[1][0]` with empty parts | **Crash** on double spaces (T01, SA-ORD-003) |
| `late` initialisation | 20 `late` fields, all assigned in `initState`/constructors | No hazard found |
| Async races | Shared intake queue re-initialised by the camera screen while a sync runs → progress lost, duplicate insert, permanent failure (**T25**); items enqueued during a run wait (T18); unsequenced realtime refetches (SA-RT-002) | SA-OFF-003 |
| setState after dispose | `product_details_screen.dart:263` (after `await markProductSoldOffline`, no `mounted` check); `camera_intake_screen.dart:145` (`setState` after `await availableCameras()` without `mounted`) | Logged error, not a crash; fix with `mounted` checks |
| Stream subscription leaks | Auth subscription cancelled; realtime channel removed in `dispose` | OK |
| Controller disposal | Remarks fallback `TextEditingController()` created per build when missing (`pending_verifications_screen.dart:369`) and the reject dialog's `customReasonController` are never disposed | Minor leaks |
| Duplicate listeners | None found | OK |
| Unawaited futures | 2 explicit `unawaited`; fire-and-forget `initialize()` in `SellerHomeScreen.initState` and `processQueue` from the queue badge | Contributes to T25 |
| Unsafe navigation | `screenNavigator.pop(true)` after sheet pop in intake; guarded by `context.mounted` | OK |
| Context across async gaps | Analyzer clean (`use_build_context_synchronously`) | OK |
| JSON parsing assumptions | RPC results cast to `Map<String,dynamic>` without type checks in several wrappers; `close_drop` result ignored | SA-DROP-005 |
| Currency | Integer paisa everywhere; rupee inputs converted with `* 100`; no floats for money | **PASS** (AGENTS rule 5) |
| Timestamps / timezone | UTC formatted as local in cards, labels, analytics | SA-ORD-001 |
| Camera controller lifecycle | Disposed on `inactive`, field not cleared | SA-AND-004 |
| Image picker lifecycle | No `retrieveLostData` | SA-AND-006 |
| Isolates | `compute` for image processing | OK |

## 2. Code quality (section 29)

| Dimension | Observation | Recommendation (only where it solves a problem) |
|---|---|---|
| Architecture consistency | One repository + StatefulWidgets everywhere — consistent but stateless across screens | Add **one** app-level live store (ChangeNotifier or Riverpod) for live state; do not introduce layers elsewhere (SA-CQ-001) |
| Duplication | Free-shipping rule (4 copies), WhatsApp phone normalisation (2 copies, same bug), order-action rules re-derived per widget, two dispatch/label implementations | Single helpers: `PhoneNumber.toWhatsApp()`, `OrderActions.from(order)`, server quote RPC |
| Dead code | `getOrders`, `markOrderPaid` stub, Kanban placeholder profile, unused toggles | Delete (SA-CQ-002) |
| Naming | Clear and consistent; some UI copy misleading ("Mark as Ready", "Generate & Share Label") | Copy fixes |
| Error handling | `LiveDropException(code)` is a good base, but codes are not mapped to messages and many paths swallow | Typed error mapping + visible error states |
| Dependency direction | UI → services/repository → Supabase; models free of Flutter | OK |
| Separation of concerns | Business rules mostly server-side (good); UI derives order actions itself (risky) | Derive from one function mirroring RPC preconditions |
| Testability | Repository is mockable (`Fake`), queue takes a `storageDir` — audit tests were easy to write | Keep; add tests per finding |
| Type safety | Strict analyzer settings; enums for statuses with permissive defaults | Make unknown statuses explicit (`unknown`) rather than `pending` |
| Maintainability | Large files (intake 1,203 lines, settings 1,037, repository 1,031) | Split intake sheet and settings sheets into widgets when touched |
| Technical debt | Placeholder features (screenshots, toggles, cache clear, auto AWB), config constants in code | Remove or implement (SA-UX-002, SA-CQ-003) |

## 3. Findings
| ID | Sev | Pri | Summary |
|---|---|---|---|
| SA-OBS-001 | HIGH | P1 | No crash reporting/telemetry; 33 swallowed errors |
| SA-CQ-001 | MEDIUM | P1 | No shared state; tabs never refresh; stale data after actions |
| SA-OFF-003 | MEDIUM | P1 | Queue race (T25) and non-idempotent replays |
| SA-ORD-003 | MEDIUM | P1 | RangeError crash in order details |
| SA-CQ-002 | LOW | P3 | Dead/placeholder code; missing `mounted` checks |
| SA-CQ-003 | LOW | P3 | Admin contact/UPI/fee compiled into the app |
