# Handoff Spec: Klaro App Icon & Logo Mark

## Overview
The Klaro mark is a bold geometric **K** drawn as a layered ribbon: a violet→blue gradient front face, a shaded 3D side-fold, a soft grounding shadow, and a top sheen, sitting on a deep-ink squircle tile with an ambient glow. It serves four jobs — store/app icon, web favicon, in-app brand mark, and splash logo. Built dark-first; a flat variant is provided for light surfaces and tiny sizes.

## Construction (geometry)
Canvas **512×512**, tile corner radius **112** (squircle ratio ≈ 0.22 of width).

The K is built on a **64-unit grid**, centered, scaled ×8 to the canvas. Stroke uses round caps and joins, width **12 units** (96 px @512).

| Part | Path (64-unit grid) |
|------|---------------------|
| Stem | `M22 16 V48` |
| Upper arm | `M22 32 L45 17` |
| Lower arm | `M22 32 L45 49` |

Layer order, back to front: soft shadow → side-fold → front face → sheen.

| Layer | Spec |
|-------|------|
| Soft shadow | same K, Gaussian blur 11, y-offset +10, `#03030F` @ 60% |
| Side-fold | same K offset **+9, +12 px**, filled `grad/fold` |
| Front face | same K, filled `grad/face` |
| Sheen | 2.1-unit strokes on the upper-left edges, `#E6E1FF` @ 60% |

## Design Tokens

| Token | Value | Usage |
|-------|-------|-------|
| `icon/tile` | `#0C0B14` | Tile background |
| `icon/glow` | radial `#352C8F` → transparent, center 50% / 36% | Ambient top glow |
| `grad/face` | `#C2B6FF` 0% · `#7C66FF` 52% · `#3F6BFF` 100%, ≈132° | K front face |
| `grad/fold` | `#3C429A` → `#171B4A` | 3D side-fold |
| `icon/sheen` | `#E6E1FF` @ 60% | Bevel highlight |
| `icon/vignette` | radial black 0→45% from 62% | Corner depth |
| `brand/violet` | `#7C5CFF` | System accent |
| `brand/blue` | `#4B7BFF` | System secondary |
| `brand/ink` | `#0A0A12` | App background |
| `brand/text` | `#ECEAF7` | Text on dark |
| `brand/muted` | `#8D8AA8` | Secondary text |

## Export Sizes

| Asset | Size | Format | Notes |
|-------|------|--------|-------|
| App Store / Play | 1024 | PNG, **no alpha, square** | OS masks the corners — don't pre-round |
| iOS app icon | 180, 120 | PNG | From the squircle source |
| Android adaptive | 512 | SVG/PNG | foreground = mark, background = `icon/tile` |
| Web / PWA (maskable) | 512, 192 | PNG | Safe zone = central 80% |
| Favicon | 32, 16 | PNG/ICO | Use the **flat mark** (drop shadow/vignette/glow off) for clarity |
| In-app mark | SVG | transparent | `klaro-k-mark.svg` on dark · `klaro-k-flat.svg` on light |

## Clear Space & Minimum Size
- **Clear space:** keep ≥ 1× the stem width clear on all sides of the mark.
- **Minimum size:** full enhanced icon ≥ **48 px**. Below 48 px, switch to the flat mark; at favicon sizes (16–32 px) use the simplified flat K with no shadow or glow.

## States & Treatments

| Context | Treatment |
|---------|-----------|
| Dark UI | Gradient mark with fold + optional glow (`klaro-k-mark`) |
| Light UI | Flat gradient mark, **no dark fold** (`klaro-k-flat`) |
| Monochrome | Single color — `#ECEAF7` on dark, `#1A1726` on light |
| Pressed (in-app button) | Scale 0.96, glow opacity +15% |
| Disabled / placeholder | Mark @ 40% opacity, no glow |

## Animation / Motion

| Element | Trigger | Animation | Duration | Easing |
|---------|---------|-----------|----------|--------|
| Mark | App launch / splash | scale 0.86→1, fade 0→1, side-fold settles (offset 0→full) | 500 ms | `cubic-bezier(.2,.8,.25,1)` |
| Glow | On appear | opacity 0→1 | 400 ms | ease-out |
| Gradient | Idle loop | slow position shimmer across the face | 3 s | ease-in-out, infinite |
| Wordmark | After mark | fade + translateY 8→0 px | 300 ms (+150 ms delay) | ease-out |

**Reduced motion:** honor `prefers-reduced-motion` — skip scale + shimmer, fade only.

## Edge Cases
- **Tiny sizes (≤32 px):** shadow/glow/vignette muddy the form — swap to flat mark.
- **Light/photographic backgrounds:** never place the dark-fold version; use flat, and add a 1px `brand/ink` keyline only if contrast is poor.
- **Monochrome print / fax:** single-color K, no gradient.
- **Android theming:** supply a monochrome layer for themed icons (Android 13+).

## Accessibility
- App name and `aria-label` / `alt`: **"Klaro"**. Decorative in-app instances: `aria-hidden="true"`.
- Gradient is decorative; any text paired with the mark must hold ≥ 4.5:1 (`#ECEAF7` on `#0C0B14` passes at ~17:1).
- Provide the monochrome variant for Windows High Contrast / forced-colors mode.

## Implementation Notes (web)
- Prefer inline **SVG** (`klaro-k-mark.svg`) for crispness; its gradient uses `userSpaceOnUse`, so it scales without breaking.
- Squircle in CSS: `border-radius: 22.4%` as an approximation, or apply an SVG squircle mask for the true Apple shape.
- Ambient glow: a `::before` radial-gradient at low opacity behind the mark.
- Drop shadow in CSS (instead of the SVG filter): `filter: drop-shadow(0 8px 14px rgba(3,3,15,.55))`.

---
*Assets: `klaro-k-enhanced.svg` (source) · `klaro-k-enh-{1024,512,192,180,32,16}.png` · `klaro-k-mark.svg` (transparent, dark) · `klaro-k-flat.svg` (transparent, light).*
