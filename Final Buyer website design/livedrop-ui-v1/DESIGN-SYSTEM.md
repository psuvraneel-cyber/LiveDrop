# LiveDrop Buyer UI — Design System

## Visual Direction
Dark luxury commerce: obsidian surfaces, ivory copy, warm gold accents, red live indicators, emerald availability states. Avoid neon, heavy gradients, or clutter.

## Layout
- Mobile gutter: 16px.
- Desktop gutter: 22px at the content shell; max width 1440px.
- Card gap: 12px mobile, 18px desktop.
- Section spacing: 24px mobile, 32px desktop.
- Header: 64px.
- Mobile bottom nav: 64px + safe-area inset.
- Product grid: 2 columns mobile; 4 columns desktop.
- Cards: 18px radius, 1px low-contrast border, deep elevated surface.

## Typography
- Display: Playfair Display / Georgia, 36–60px.
- Heading: Playfair Display / Georgia, 25–32px.
- Section: Playfair Display / Georgia, 20–28px.
- Product: Inter, 14–16px, semibold.
- Body: Inter, 14–16px.
- Metadata: Inter, 11–13px.
- Price: Inter, 18–32px, heavy.
- Button: Inter, 12–14px, bold.

## Colors
- Background #070807
- Surface #0d0f0d
- Surface 2 #121512
- Gold #f3c653
- Gold soft #ffe6a3
- Ivory #f8f4ec
- Muted #b7b0a4
- Live #ff375f
- Success #32d296

## Components
Button, Chip, Badge, ProductCard, BoutiqueCard, Header, BottomNav, Input, Drawer, Modal, Tabs, Timeline/Order states are designed to share radii, spacing, borders, and status colors.

## Motion
- Tap: 120–180ms scale/opacity response.
- Hover: subtle lift 4–6px and photo scale 1.02–1.05.
- Drawer: spring/slide 220–320ms.
- Page/image transition: opacity + scale 250–650ms.
- Cart feedback: spring scale + state transition.
- Live indicator: restrained pulse; never continuous flashing.
- Drag: horizontal rails use Motion drag with elastic resistance.
