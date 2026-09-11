# LiveDrop — Engineering Conventions & Standards

## 1. Purpose & Scope
This document sets the authoritative code style, architectural patterns, naming conventions, and file structures for all LiveDrop codebases (Next.js Buyer Webfront, Flutter Seller Native App, and PostgreSQL Database Migrations). All human developers and AI coding agents MUST strictly follow these rules.

---

## 2. Global Principles
1. **Zero Implicit Any / Dynamic Typing**: Strict compilation mode MUST be enabled across TypeScript and Dart.
2. **Explicit Error Handling**: Do not swallow exceptions. Use structured Result/Either types or typed error domain unions.
3. **Repository/Service Separation**: UI components NEVER call Supabase client APIs directly. All data access must pass through typed Repository or Service classes.
4. **Defensive Database Boundaries**: Never trust client inputs. Always enforce constraints at the PostgreSQL level.
5. **No Dead Code / Speculative Abstractions**: Only build what is required by the PRD and current implementation phase.

---

## 3. Database & SQL Conventions (PostgreSQL)

### 3.1 Naming Rules
* **Tables & Views**: Plural, lowercase `snake_case` (e.g., `profiles`, `drops`, `products`, `orders`, `order_items`).
* **Columns**: Lowercase `snake_case` (e.g., `flash_code`, `order_token`, `reserved_at`).
* **Primary Keys**: Always named `id`, typed `UUID` with `DEFAULT gen_random_uuid()`.
* **Foreign Keys**: Target singular entity name followed by `_id` (e.g., `seller_id`, `drop_id`, `order_id`).
* **Indexes**: `idx_{table}_{column(s)}` (e.g., `idx_products_drop_status`, `idx_orders_token`).
* **Functions / RPCs**: Lowercase `snake_case` descriptive verb phrase (e.g., `create_order_with_reservation`, `mark_order_paid`).
* **Triggers**: `trg_{table}_{action}` (e.g., `trg_products_updated_at`).

### 3.2 SQL Coding Standards
```sql
-- 1. All custom functions MUST explicitly set search_path
CREATE OR REPLACE FUNCTION public.my_secure_function(...)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
    -- 2. Explicit transactions and deadlock prevention ordering
    -- 3. Explicit type casting
    -- 4. Standard error raising using ERRCODE
END;
$$;
```
* **Money / Currency**: Stored in **Paisa** (Integer), never floating point.
* **Timestamps**: Always `TIMESTAMPTZ` (`timestamp with time zone`) with default `NOW()`.

---

## 4. Buyer Webfront Conventions (Next.js 14+ / TypeScript)

### 4.1 Directory Structure
```
web/
├── app/                      # Next.js App Router
│   ├── [slug]/               # Public boutique catalog (/dresses-by-priya)
│   │   ├── page.tsx          # Server Component / Static Shell
│   │   └── ProductGrid.tsx   # Client Component (realtime listener)
│   ├── cart/                 # Cart & checkout bottom-sheet flow
│   ├── order/
│   │   └── [id]/             # Order summary page (?token=...)
│   ├── layout.tsx            # Root layout with fonts, meta tags
│   └── globals.css           # Vanilla CSS Design System tokens
├── components/               # Pure presentation UI components
│   ├── Badge.tsx             # Flash-code badge
│   ├── Button.tsx            # 48x48px touch-target button
│   ├── Modal.tsx
│   └── Toast.tsx
├── lib/                      # Core infrastructure
│   ├── supabase/             # Typed Supabase client factory
│   │   ├── client.ts         # Browser client (anon key)
│   │   └── server.ts         # Server client (cookies / SSR)
│   ├── api/                  # Repositories & RPC wrappers
│   │   ├── catalog.repository.ts
│   │   └── order.repository.ts
│   ├── validators/           # Zod schemas for checkout, phone, pincode
│   │   └── checkout.schema.ts
│   └── utils/                # Formatting (currency, date, phone)
└── types/                    # Database and Domain TypeScript definitions
    ├── database.types.ts     # Generated from Supabase CLI
    └── domain.types.ts
```

### 4.2 TypeScript Rules
* `strict: true`, `noImplicitAny: true`, `exactOptionalPropertyTypes: true`.
* **Validation**: All user input MUST be validated using **Zod** before calling API/RPC.
* **Component Props**: Use explicit interfaces named `{ComponentName}Props`.
```typescript
// Good
interface FlashBadgeProps {
  code: string;
  isAvailable: boolean;
}
export function FlashBadge({ code, isAvailable }: FlashBadgeProps) { ... }
```

### 4.3 Styling Conventions
* Vanilla CSS with CSS custom properties defined in `globals.css` matching [UI/UX Specification](file:///c:/LiveDrop/docs/03-ui-ux-specification.md).
* Utility classes MUST use CSS modules or standard class naming: `.ld-button`, `.ld-card`, `.ld-badge`.
* Strict adherence to minimum **48×48px** touch targets on all interactive elements.

---

## 5. Seller Mobile Conventions (Flutter / Dart)

### 5.1 Directory Structure (Clean Architecture)
```
mobile/
├── lib/
│   ├── core/                 # Shared utilities, theme, constants
│   │   ├── theme/            # AppTheme, Colors, Typography
│   │   ├── utils/            # Image compressor, phone formatter, UPI launcher
│   │   └── errors/           # Failure models and exceptions
│   ├── data/                 # Data Layer: Models, Datasources, Repositories
│   │   ├── datasources/
│   │   │   ├── local/        # SQLite/Hive upload queue datasource
│   │   │   └── remote/       # Supabase remote datasource
│   │   ├── models/           # DTOs with fromJson / toJson
│   │   └── repositories/     # Repository implementations
│   ├── domain/               # Domain Layer: Entities, Interfaces, UseCases
│   │   ├── entities/         # Immutable Product, Drop, Order models
│   │   └── repositories/     # Abstract repository contracts
│   └── presentation/         # UI Layer: Screens, Widgets, Providers
│       ├── controllers/      # Riverpod Notifiers / StateNotifier
│       ├── screens/          # IngestionScreen, LiveDashboardScreen, OrdersScreen
│       └── widgets/          # CameraOverlay, OrderCard, StatusBadge
└── test/                     # Unit, Widget, and Mock tests
```

### 5.2 Dart Rules
* Linter: Follow `package:flutter_lints` with strict-raw-types and strict-inference.
* State Management: **Riverpod 2.x** with code-generation (`@riverpod`).
* Immutability: Use `@freezed` or immutable classes with `const` constructors.
* Error Handling: Methods return `Future<Either<Failure, T>>` (or custom `Result<T, Failure>`). No raw unhandled exceptions in UI controllers.

---

## 6. Git & Version Control Conventions

### 6.1 Branch Naming
* `feat/{phase-number}-{feature-name}` (e.g., `feat/02-buyer-catalog`, `feat/03-atomic-checkout`)
* `fix/{issue-id}-{description}` (e.g., `fix/AUD-001-order-lock-deadlock`)
* `docs/{topic}` (e.g., `docs/adr-009`)

### 6.2 Commit Messages (Conventional Commits)
Format: `<type>(<scope>): <subject>`
* `feat`: New feature or capability
* `fix`: Bug fix
* `docs`: Documentation changes only
* `test`: Adding or correcting tests
* `refactor`: Code change that neither fixes a bug nor adds a feature
* `chore`: Build tasks, dependency updates, configs

*Examples:*
* `feat(checkout): implement atomic create_order_with_reservation RPC`
* `fix(security): pin search_path on all SECURITY DEFINER functions`
* `test(concurrency): add 20-client simultaneous reservation test`

---

## 7. Review & Verification Gate
Before committing or marking any task done:
1. Linters must pass (`npm run lint` / `flutter analyze`).
2. Tests must pass (`npm test` / `flutter test`).
3. Type checks must pass (`tsc --noEmit`).
4. Traceability matrix in [Requirements Traceability Matrix](file:///c:/LiveDrop/docs/06-requirements-traceability-matrix.md) must be referenced.
