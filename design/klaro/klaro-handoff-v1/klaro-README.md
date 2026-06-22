# Klaro — Build Handoff Package

**Klaro** is a premium, dark-first personal expense tracker (mobile app + web companion). This package contains everything needed to start building: the brand, the final logo and icon set, design tokens, an interactive reference prototype, and developer specs.

---

## What's in this package

| File | What it is | Use it for |
|------|------------|-----------|
| `klaro-expense-tracker-prototype.html` | **Interactive reference prototype** — open in any browser. Splash → onboarding → 7 screens, working add-expense flow, filters, live totals. | The visual + interaction source of truth. Click through it; build to match. |
| `klaro-brand.html` | **Brand guidelines** (one page) — logo treatments, palette, type, do/don't. | Brand reference for any surface. |
| `klaro-tokens.css` | **Design tokens** as CSS custom properties (colors, gradient, type, radius, spacing, motion). | Import at app root; reference `var(--klaro-*)` instead of hardcoding. |
| `klaro-icon-handoff.md` | **Icon/logo dev spec** — geometry, gradient stops, export sizes, clear-space, animation, a11y. | Implementing the app icon, favicon, and splash. |
| `klaro-k-enhanced.svg` | **Final logo** (layered K) — vector source. | Master logo asset. |
| `klaro-k-mark.svg` / `klaro-k-flat.svg` | Transparent mark — layered (dark UI) / flat (light UI). | In-app logo placement. |
| `klaro-k-enh-{1024,512,192,180,32,16}.png` | Rendered app-icon set. | Store upload, PWA, favicon. |

> Other explorations (`klaro-set-*.svg`, Canva deck, earlier concepts) are kept for reference but are **not** part of the final spec.

---

## Getting started (developer)

1. **Pick a stack.** The prototype is plain HTML/CSS/JS so it's framework-agnostic. Recommended: **React (or React Native / Expo for mobile) + the tokens file**. Tailwind users: map the tokens to `theme.extend.colors`.
2. **Wire up tokens.** Import `klaro-tokens.css` once at the root. Everything in the prototype already maps to these values (e.g. `--klaro-violet`, `--klaro-gradient`).
3. **Fonts & icons.** Poppins (wordmark/headings), Inter (UI/body), JetBrains Mono (figures) — load from Google Fonts. Icons in the prototype use **Tabler Icons** (webfont via CDN); swap for your icon library if preferred.
4. **Build screen-by-screen** against the prototype. Each screen is a `<section class="screen" id="screen-NAME">`.
5. **Logo/icon:** follow `klaro-icon-handoff.md`. Favicon is embedded in the prototype `<head>` as a data-URI you can reuse.

---

## Screens & flow

`splash` (auto, 1.8s) → `onboarding` → **`home`**

Bottom tab bar: **Home · Insights · ➕ Add · Cards · Profile**

| Screen | Contents |
|--------|----------|
| Splash | Animated K (scale+fade) + wordmark, then routes to onboarding |
| Onboarding | Logo, "See every cent.", Get started / sign-in |
| Home | Glass balance card, income/spent chips, budget progress, recent transactions |
| Insights | Category donut + breakdown (Food 32%, Shopping 24%, Transport 18%, Bills 16%, Other 10%) |
| Transactions | Filter chips (All / Expenses / Income) + list |
| Add expense | Bottom sheet: amount keypad, type toggle, category grid, save → updates Home |
| Cards | Card visual, available/spent, freeze + alerts toggles |
| Budgets | Per-category budget progress bars |
| Profile | User, account/notifications/security/theme, log out |

---

## Data model (starter)

```ts
type Category = 'Food'|'Transport'|'Shopping'|'Bills'|'Health'|'Fun'|'Income'|'Other';
interface Transaction { id: string; name: string; category: Category; amount: number; /* +income / -expense */ date: string; }
interface Budget { category: Category; limit: number; spent: number; }
interface Account { balance: number; monthlyIncome: number; monthlySpent: number; budgetTotal: number; }
```

The prototype computes `spent`, `budgetLeft`, and `%` live from the transactions array — mirror that logic server-side or in app state.

---

## Motion (key animations)
- **Splash:** K scale `0.86→1` + fade, `500ms`, `cubic-bezier(.2,.8,.25,1)`; wordmark fades up after `~280ms`.
- **Add sheet:** slide up `320ms`; scrim fade `250ms`.
- **Primary buttons / FAB:** violet glow (`--klaro-glow-accent`).
- Honor `prefers-reduced-motion` (tokens already collapse durations).

## Accessibility
- Maintain ≥ 4.5:1 text contrast (palette is built for it on `--klaro-ink`).
- App/logo `aria-label="Klaro"`; decorative marks `aria-hidden`.
- Provide a monochrome logo variant for forced-colors mode.

---

## Not yet built (next milestones)
- Real **auth** (passkeys recommended) + accounts/sync.
- **Backend / data**: transactions, budgets, bank-link or manual entry.
- **Web companion** dashboard (concept exists in the brand deck) — reuse the same tokens.
- Empty/loading/error states for each screen (specs to be added as screens are built).

---
*Klaro brand v1.0 — see `klaro-brand.html` and `klaro-icon-handoff.md` for full detail.*
