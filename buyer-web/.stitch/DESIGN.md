# Design System: LiveDrop Haute Couture

## 1. Visual Theme & Atmosphere
An ultra-luxury, high-contrast Indian couture atmosphere blending ancestral royal heritage with cutting-edge live commerce. The environment is dark and atmospheric ("Obsidian Velvet"), punctuated by warm metallic Champagne Gold accents and deep Burgundy undertones. Density is balanced (Art Gallery Airy, level 4), variance is asymmetric and intentional (level 7), and motion uses weighted spring physics (damping 20, stiffness 100) for a tactile, regal experience.

## 2. Color Palette & Roles
- **Obsidian Canvas** (`#08080A`) — Deepest neutral background, zero pure black glare.
- **Elevated Noir Card** (`#0E0E12`) — Primary card container surface with 1px hairline border.
- **Noir Surface Hover** (`#15151B`) — Interactive container state for cards and list items.
- **Burgundy Velvet Glow** (`#2A0811` / `rgba(78, 18, 32, 0.25)`) — Atmospheric backlights, story rings, and hero vignettes.
- **Champagne Gold Primary** (`#D4AF37`) — Authoritative brand accent, icons, borders, and verification crests.
- **Champagne Gold Light** (`#F5D78E`) — Highlight stop for metallic pill gradients and active tabs.
- **Champagne Gold Deep** (`#C88A24`) — Shadow stop for metallic gradients.
- **Ivory Display Text** (`#FBFBFB`) — High-contrast display typography and headers.
- **Muted Ivory** (`rgba(251, 251, 251, 0.65)`) — Editorial descriptions, subtitles, and metadata.
- **Whisper Border** (`rgba(255, 255, 255, 0.08)`) — Structural dividers and non-accented container outlines.
- **Live Crimson** (`#EF4444`) — Realtime broadcast badges with pulsing ivory indicator.

## 3. Typography Rules
- **Display / Headlines**: `Cormorant Garamond` (or high-contrast serif), `font-serif`, track-tight, controlled scale (`text-3xl` to `text-5xl`), tight leading (`leading-[1.1]`).
- **Body & Controls**: `Plus Jakarta Sans`, `font-sans`, relaxed leading, weights 400 to 700. Maximum line length 60ch.
- **Labels & Overlays**: Clean Title Case for buttons (`Explore Live Shows →`), NEVER harsh, yelling all-caps.
- **Banned Typography**: Inter font is banned. Generic system fonts without serif pairing are banned.

## 4. Component Stylings
- **Buttons**: Rounded-full metallic champagne gold gradient pill (`linear-gradient(135deg, #F5D78E 0%, #D4AF37 50%, #C88A24 100%)`). Obsidian text (`#08080A`), weight 700. Tactile spring scale on hover (`hover:scale-[1.02]`) and active (`active:scale-[0.97]`). No neon or outer glow.
- **Story Circles**: 72px diameter on mobile, 84px on desktop. Ultra-thin 2px champagne gold gradient ring with smooth scale-up on hover. Curated, high-contrast Indian luxury imagery with centered Title Case labels below.
- **Live Stream Cards**: Generous 24px corner radius (`rounded-3xl`). 1px champagne hairline border (`border-[#D4AF37]/25`). Left badges: Red pill `● LIVE` + `👁 2.4K` view count pill. Right badge: Glassmorphic bookmark button. Bottom: Title, designer avatar, blue verified badge, and circular gold arrow button (`→`).
- **Atelier Showcase Cards**: Elevated obsidian cards with royal monogram avatars in burgundy/gold gradient rings, clean serif titles, verified badges, and gold `Visit Boutique →` links.
- **Bottom Navigation Dock**: Translucent obsidian glass (`backdrop-blur-2xl bg-[#0E0E12]/90 border-t border-white/[0.08]`), compact 60px height, Title Case labels (`Home`, `Live`, `Shop`, `Designers`, `Profile`), thin gold active indicator.

## 5. Layout & Spacing Principles
- **Mobile-First Priority**: Target viewports 360px–430px. Ensure `pb-32` bottom clearance so content and buttons are never covered by the dock.
- **Desktop Elevation**: On wide viewports (`≥ 1024px`), expand into an asymmetric split hero (text left, framed bridal portrait right) and 2-to-3 column grid for ateliers.
- **Breathing Room**: Vertical section gaps scale gracefully (`space-y-12 sm:space-y-16`). No cluttered or overlapping elements.

## 6. Anti-Patterns (Banned)
- No emojis anywhere in the UI.
- No pure black (`#000000`).
- No neon or oversaturated button glows.
- No harsh all-caps CTAs (`EXPLORE LIVE SHOWS →` replaced with `Explore Live Shows →`).
- No washed-out or culturally mismatched stock photography (e.g. western business suits or cold pine forests).
- No unconstrained image overflow.
