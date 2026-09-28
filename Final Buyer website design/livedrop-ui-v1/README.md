# LiveDrop Buyer UI v1

Standalone visual prototype for the LiveDrop buyer experience. It intentionally uses mock data and local SVG image assets so the UI can be evaluated before integration into the real buyer-web application.

## Core routes
- `/` — Homepage
- `/shop` — All sellers / products
- `/filters` — Filter screen
- `/live` — LiveDrop room
- `/product/a03` — Product details (dynamic route; any product id works)
- `/cart` — Cart with mock items
- `/cart/empty` — Empty cart

## Run

```bash
npm install
npm run dev
```

Open `http://localhost:3000`.

## Production check

```bash
npm run typecheck
npm run lint
npm run build
npm run start
```

## Notes
- The six uploaded reference images are kept under `reference/`.
- All product/boutique imagery is local and non-empty SVG artwork under `public/images`.
- Cart state is localStorage-backed for prototype continuity.
- No Supabase, payment gateway, Realtime, or production architecture is connected in this prototype.
