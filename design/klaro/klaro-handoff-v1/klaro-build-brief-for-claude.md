# Klaro — Build Brief for Claude

> **How to use this:** Put the `klaro-handoff-v1` files (this brief, `klaro-tokens.css`, `klaro-expense-tracker-prototype.html`, `klaro-brand.html`, `klaro-icon-handoff.md`, and the logo assets) in one folder. Open Claude Code in that folder and paste the prompt below (or say: *"Read klaro-build-brief-for-claude.md and start building."*). Pick your stack in **Section 2** before you start.

---

## THE PROMPT (everything below is for Claude)

You are building **Klaro**, a premium dark-mode personal expense tracker. A complete design system and an interactive HTML prototype already exist in this folder. **Build a working app that matches the prototype exactly.** Do not redesign — implement.

### 1. Source of truth (read these first)
- `klaro-expense-tracker-prototype.html` — the **visual + interaction spec**. Open it; every screen, layout, color, and animation should match this.
- `klaro-tokens.css` — the design tokens. Use these values; never hardcode colors.
- `klaro-brand.html` — brand rules (logo, palette, type, do/don't).
- `klaro-icon-handoff.md` — app icon / favicon / splash spec.
- Logo assets: `klaro-k-enhanced.svg` (master), `klaro-k-mark.svg` (dark UI), `klaro-k-flat.svg` (light UI), `klaro-k-enh-*.png` (icon sizes).

### 2. Tech stack — **DEFAULT: React + TypeScript + Vite (installable PWA)**
This ports 1:1 from the prototype, uses the CSS tokens directly, and installs on phones. Use:
- Vite + React 18 + TypeScript, React Router, CSS Modules (or plain CSS) importing `klaro-tokens.css`.
- Framer Motion for animation; a charting lib or hand-built SVG for the donut; `vite-plugin-pwa` for installability + the icon set.
- State: React context + a `useStore` hook (in-memory now; structure it so a backend can drop in later).

*(Alternative — native app for the App Store: **Expo + React Native + TypeScript + Expo Router + NativeWind**. If chosen, translate `klaro-tokens.css` into a typed theme object / NativeWind config and use React Native primitives. Keep the same components, screens, data model, and acceptance criteria below.)*

### 3. Design rules (non-negotiable)
- **Dark-first.** Background `--klaro-ink`; build surfaces with `--klaro-surface` / `--klaro-raised` / `--klaro-overlay`, not shadows.
- **Use tokens** for every color, radius, space, and motion value.
- **Gradient** (`--klaro-gradient`) only on: primary buttons, the FAB, the logo, progress bars, and the active income/accent — never behind body text or data tables.
- **Type:** Poppins (wordmark/headings), Inter (UI/body), JetBrains Mono (figures).
- **Icons:** Tabler Icons (match the prototype's `ti-*` names).
- **Motion:** subtle, `--klaro-ease`; honor `prefers-reduced-motion`.
- **Accessibility:** ≥ 4.5:1 text contrast, semantic roles, keyboard/focus support, `aria-label="Klaro"` on the logo.

### 4. Screens to build (match the prototype)
Flow: **splash (auto 1.8s) → onboarding → home**. Bottom tab bar: Home · Insights · ➕ Add · Cards · Profile.

| Screen | Build acceptance criteria |
|--------|---------------------------|
| **Splash** | Animated K (scale 0.86→1 + fade, 500ms) then wordmark fades up; auto-routes to onboarding. |
| **Onboarding** | Logo, "See every cent.", "Get started" + "I already have an account" → home. |
| **Home** | Glass balance card; income/spent chips; budget progress bar; recent transactions (live from store). |
| **Insights** | Category donut + breakdown list; month selector. |
| **Transactions** | Filter chips (All/Expenses/Income) that filter the list. |
| **Add expense** | Bottom sheet: amount keypad (works), Expense/Income toggle, category grid, Save → prepends a transaction, updates Home totals + budget, closes. |
| **Cards** | Card visual, available/spent, Freeze + Spend-alerts toggles. |
| **Budgets** | Per-category budget progress bars. |
| **Profile** | User row, settings list, dark-theme toggle, log out → onboarding. |

### 5. Data model + logic
```ts
type Category = 'Food'|'Transport'|'Shopping'|'Bills'|'Health'|'Fun'|'Income'|'Other';
interface Transaction { id: string; name: string; category: Category; amount: number; date: string; } // + income, − expense
interface Budget { category: Category; limit: number; spent: number; }
```
- Seed with the prototype's sample transactions.
- Compute `spent`, `budgetLeft`, and `%` live from transactions (mirror the prototype's JS). Round currency for display.
- Persist to `localStorage` for now; isolate data access behind a `store` module so a real API can replace it.

### 6. Assets / icon
- App icon, PWA icons, and favicon from `klaro-k-enh-*.png` / the SVGs — follow `klaro-icon-handoff.md` (favicon ≤32px uses the flat mark).
- Reuse the splash design from the prototype.

### 7. Build order
1. Scaffold the project; wire fonts, Tabler icons, and `klaro-tokens.css`.
2. Build primitives: `Button`, `Card`, `GlassCard`, `Pill`, `ProgressBar`, `Sheet`, `TabBar`, `Icon`, `Donut`, `TransactionRow`.
3. Set up the `store` (transactions, budgets, derived totals) + routing + tab bar.
4. Build screens in the table order; verify each against the prototype.
5. Add the splash + add-expense animations; wire `prefers-reduced-motion`.
6. Configure PWA + icons; test install + favicon.

### 8. Definition of done
- Every screen visually matches the prototype (spacing, color, type, radii) using tokens.
- Add-expense end-to-end works and updates Home/Budgets live.
- Filters work; tab navigation works; splash plays once.
- Installable (PWA) with the correct icon + splash; favicon renders crisp.
- No console errors; TypeScript strict passes; basic a11y (focus, labels, contrast) holds.
- A short `README` documents how to run, and where to plug in a real backend + auth (passkeys recommended).

### 9. Guardrails
- Match the prototype; don't invent new screens, colors, or layouts.
- Don't hardcode hex — reference tokens.
- Keep it framework-idiomatic and componentized; no giant single file.
- Flag anything ambiguous instead of guessing, and keep the data layer swappable.

**Start by reading `klaro-expense-tracker-prototype.html` and `klaro-tokens.css`, then scaffold the project and confirm the plan.**
