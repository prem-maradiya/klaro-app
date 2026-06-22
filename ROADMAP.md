# Expense Tracker — Road to "Fully Ready"

What's left to take the app from working prototype to a finished product.
Status as of 2026-06-10.

## ✅ Already done

- Universal bank SMS parsing on-device (~99.9% measured accuracy) + AI fallback (Groq)
- Real-time background SMS capture with notifications
- Auto-categorization (brand → keyword → learned → AI) with rename-learning
- Contact matching → friend payments labeled "Personal" with real names
- FastAPI + PostgreSQL backend with full CRUD + learning endpoints
- Flutter app: live capture, inbox import, labeling, card-vs-UPI visuals
- Web dashboard (Linear theme) on live data: month selector, KPIs, payment
  method split, charts, full searchable month transactions

---

## ✅ Phase 1 — Make it a real app on the phone (DONE 2026-06-10)

1. ~~**App identity**~~ — app is now **Klaro** (full brand handoff in
   `design/klaro/`): adaptive launcher icon + monochrome layer rendered from
   the icon spec, Android-12 native splash + in-app animated splash, Klaro
   dark theme (tokens in `lib/theme/klaro.dart`), Poppins/Inter/JetBrains
   Mono bundled.
2. ~~**Signed release APK**~~ — keystore `android/klaro-release.jks`
   (credentials in `android/key.properties` — back these up!), new app id
   `com.premm.klaro`, installed on the Vivo.
3. ~~**Vivo battery whitelist**~~ — granted via adb (`dumpsys deviceidle
   whitelist`); in-app one-time prompt remains as fallback. NOTE: re-enable
   Auto-start for the new "Klaro" app in Vivo i Manager (old grant was for
   the uninstalled debug app).

## ✅ Phase 2 — Never lose a transaction (DONE 2026-06-10)

4. ~~**Retry-sync hardening**~~ — sync engine in `ExpenseProvider`:
   exponential backoff (5s→15s→1m→5m→15m), connectivity_plus listener
   (auto-sync on reconnect), offline edit (dirty flag) + delete (tombstone
   queue) retries, per-expense sync icon + "Syncing N changes…" /
   "tap to retry" banner. Verified on phone: offline delete queued, drained
   on reconnect.
5. ~~**Backend-side dedupe**~~ — `raw_sms_hash` (SHA-256, indexed) + amount
   + ±5 min window on POST; returns the existing row (200) instead of
   creating. Verified: double-POST → same id; full re-import from cleared
   app data onto a populated backend → 0 duplicates (127 rows = 127 hashes).

## ✅ Phase 3 — Works anywhere (DONE 2026-06-11, one user step left)

6. ~~**Deploy backend to the cloud**~~ — live at
   **https://klaro-api.vercel.app** (Vercel serverless, project `klaro-api`,
   auto-deploys from github.com/prem-maradiya/klaro-backend). Groq key +
   API key live in Vercel env vars. `render.yaml` kept as an alternative.
   ⚠️ ONE STEP LEFT: create a free **Neon** Postgres (https://neon.tech) and
   set `DATABASE_URL` on the Vercel project — until then data endpoints 500
   and the phone keeps everything stored locally (by design). See the
   backend README "Cloud deployment" for the 3 commands.
7. ~~**Point app + dashboard at the cloud URL**~~ — dashboard defaults to the
   cloud API (VITE_API_URL) with a gear-icon override; app keeps localhost
   default for dev, cloud URL goes in Settings (with API-key field).
8. ~~**API security**~~ — X-API-Key header required on everything except
   /health (env `API_KEY` on Vercel; local dev stays open when unset).
   CORS locked to https://klaro-dashboard.vercel.app.
9. ~~**Deploy the dashboard**~~ — live at **https://klaro-dashboard.vercel.app**
   (auto-deploys from github.com/prem-maradiya/klaro-dashboard). API key is
   entered once in the gear icon and stays in the browser's localStorage —
   never in the JS bundle.
10. ~~**Month-aware /expenses endpoint**~~ — `?month=YYYY-MM` (IST bucketing)
    + skip/limit + X-Total-Count, new `/months`, SQL-aggregated
    `/summary?month=`. Dashboard fetches only selected + previous month +
    unlabeled rows.

## ✅ Phase 4 — Power features (DONE 2026-06-14)

10b. ~~**Inbox catch-up scan**~~ — DONE 2026-06-12. On every app open/resume
    the app scans inbox SMS newer than the last scan (date-filtered query) and
    adds anything the background receiver missed (Vivo kills it sometimes) —
    self-heals the "missed ₹30 payment" failure from 2026-06-11.
11. ~~**Budgets & alerts**~~ — DONE 2026-06-12 (v1.3.0+4). Backend `budgets`
    table + GET/PUT/DELETE `/budgets` + `/budgets/status?month=` (spent/pct,
    dashboard-ready). App: Budgets screen (wallet icon in app bar — overall +
    per-category limits with month progress), budget bar on the home summary
    card, notifications at 80% and 100% (once per level per month, fired from
    foreground adds, imports, catch-up, labeling, budget edits AND the
    background SMS isolate via a prefs cache). Offline-first: budgets cached
    locally, offline edits re-pushed on next sync. Verified end-to-end on the
    phone against the live cloud (Vercel + Neon).
12. ~~**Edit from the dashboard**~~ — DONE 2026-06-14. Click any transaction to
    edit merchant/category/amount or delete it (EditExpenseModal), wired to the
    existing PATCH/DELETE endpoints with optimistic updates + rename-learning
    (a relabel teaches merchant→display-name + category). Budgets ride along via
    `/budgets/status` (BudgetsCard). App-side pull-reconcile propagates those
    edits to the phone on next resume (`_pullReconcile` in ExpenseProvider).
13. ~~**CSV / Excel export**~~ — DONE 2026-06-14. `GET /export?month=YYYY-MM |
    ?year=YYYY | (all)` returns Excel-friendly CSV (UTF-8 BOM, IST dates,
    Content-Disposition filename, Direction column). Dashboard Export menu in
    the top bar (This month / This year / All time) downloads via an authed
    fetch + blob. Live on klaro-api + klaro-dashboard.
14. ~~**Income tracking**~~ — DONE 2026-06-14 (app v1.5.0+7). New `direction`
    column (debit = spend, credit = income; self-migrated on Neon at startup).
    The SMS parser now captures credit SMS (salary/refunds/transfers in) as
    income instead of discarding them — filed under an "Income" bucket, excluded
    from spending totals + budgets. Backend `/summary` returns
    income_total/expense_total/net; dashboard shows a Cash flow card (money in /
    out / net) and green income rows; the app home shows a net-flow line and
    green income tiles. Parser changes covered by unit tests (all 33 pass).
15. ~~**Recurring-payment detection**~~ — DONE 2026-06-14. Backend `GET
    /recurring` detects subscriptions/EMIs/regular bills three ways — a stable
    amount on a regular cadence (≥2 charges, excluding people/transfers/food), a
    known subscription brand from a single charge, or an EMI/SIP/NACH/mandate/
    autopay keyword in the SMS — and predicts each next due date (rolled forward;
    dead-for-2-cycles dropped), plus the monthly-equivalent total. Surfaced on
    BOTH the dashboard ("Upcoming payments" card, RecurringCard) and the phone
    (Upcoming-payments screen, autorenew icon in the app bar — `/recurring` via
    ApiService, soonest-due-first, pull-to-refresh) so the two never drift. Live;
    verified on synthetic subs and surfaced a real Netflix AutoPay mandate in the
    live data.
    - **Parser fix (2026-06-19, v1.6.0+8):** IDBI UPI-AutoPay/mandate debits
      ("...debited ... towards <MERCHANT> for Create Mandate AutoPay...") now
      extract the real merchant (NETFLIX), not the trailing "-IDBI Bank" or a
      mis-matched contact. New `_merchantPatterns` "towards X for/on" rule + test
      (bank_formats_test.dart). The one mislabeled live row (id 812, "M Somnath
      Roy (IDBI BANK)"/Personal) was corrected to Netflix/Entertainment.

## Phase 5 — Polish (DONE 2026-06-20)

16. ~~**On-phone spending-trend chart**~~ — DONE 2026-06-19 (v1.7.0+9). Home
    screen now shows a "Daily spending · <month>" card under the summary: a
    bespoke `CustomPainter` bar chart (no chart dependency) with one rounded bar
    per day of the month so far, the peak day highlighted in the brand gradient
    (rest dimmed violet), an "Avg ₹X/day" + "Top day ₹Y · Mon N" header, and
    "Mon 1 … Today" axis labels. Fed by `ExpenseProvider.dailySpendThisMonth`
    (same filter set as `totalThisMonth`, so the bars sum to the headline total).
    Shown only when there's spend this month. Verified on the Vivo (Jun 12 peak
    ₹2054, avg ₹369/day vs ₹7018 total). `lib/widgets/spending_chart.dart`.

17. ~~**On-phone category donut**~~ — DONE 2026-06-20 (v1.8.0+10). Replaced the
    summary card's category chips with a "Spending by category" card: a bespoke
    `CustomPainter` donut (segment per category, gap-separated, coloured via
    `Klaro.categoryColor`) with the top category + its share in the hole, and a
    legend (top 6 + "+N more") showing colour dot, name, share % and amount.
    Fed by `ExpenseProvider.categoryTotals` — fully offline.
    `lib/widgets/category_donut.dart`. Verified on the Vivo (Food 29% ₹2161).

18. ~~**Recurring snooze / dismiss with undo**~~ — DONE 2026-06-20 (v1.8.0+10).
    Swipe-left to dismiss a detected recurring payment ("I cancelled this");
    optimistic removal, the header monthly total decrements by the row's
    cadence-normalised monthly-equivalent, and a SnackBar offers Undo. Backed by
    a new `recurring_dismissals` table and `POST /recurring/dismiss` +
    `DELETE /recurring/dismiss/{merchant}` (keyed on `normalize(merchant)`);
    `/recurring` now excludes dismissed and returns the `dismissed` list. Mirror
    action on the dashboard's `RecurringCard` (hover × + inline Undo). Verified
    end-to-end on the Vivo: swiped Netflix → ₹0/0 active → restored via API →
    pull-to-refresh brought it back (₹199, 1 active). `recurring_screen.dart`,
    `api_service.dart`, backend `main.py`/`models.py`, dashboard `RecurringCard.jsx`.

19. ~~**Income detail view (by source)**~~ — DONE 2026-06-20 (v1.8.0+10). The home
    net-flow line ("₹X in · Net ±₹Y") is now tappable (chevron hint) and opens an
    `IncomeSheet` bottom sheet: this month's credits grouped by source (largest
    first), each with its total, share %, deposit count and latest date, under a
    "+₹total" green header. Fed by `ExpenseProvider.incomeThisMonthEntries`.
    `lib/widgets/income_sheet.dart`. Verified on the Vivo (Income · June, +₹130).

Phase 5 closed 2026-06-20 — app shipped as v1.8.0+10, dashboard + backend
deployed to Vercel.

## Phase 6 — Ship, features, reliability (DONE 2026-06-20, app v1.9.0+11)

20. ~~**Backend reliability — pytest + CI**~~ — DONE. 21 tests against in-memory
    SQLite (FastAPI `TestClient`, `get_db` override, lifespan skipped so the real
    Postgres engine is never touched): `normalize`, API-key auth, dedupe incl.
    whitespace-immunity, manual-entry-never-dedupe, income vs spending separation
    in `/summary`, budgets CRUD + status, recurring detection, dismiss/restore
    round-trip + idempotency, and learned-rename persistence. `requirements-dev.txt`
    pins pytest; `.github/workflows/tests.yml` runs it on every push. No runtime
    code changed. `expense_tracker_backend/tests/`.

21. ~~**Multi-month Spending Trends screen**~~ — DONE (v1.9.0+11). New menu entry
    "Spending trends" → `lib/screens/trends_screen.dart`: a gradient header (this
    month + MoM delta, coloured alert-up / positive-down since a rise in spend is
    bad, + avg/mo), a 6-month bar chart (current month highlighted in the brand
    gradient, value labels), and a per-month list with mini share-bars and MoM %.
    Fed by NEW `ExpenseProvider.monthlySpend({count})` returning a `MonthSpend`
    record list (all local data, offline). Verified on the Vivo (Jun ₹7,460, −58%
    vs May ₹17,673; Apr ₹14,424).

22. ~~**Play Store ship readiness**~~ — DONE. Hosted privacy policy (mandatory for
    SMS apps) at https://klaro-dashboard.vercel.app/privacy.html
    (`dashboard public/privacy.html`, static, no scripts). Release signing was
    already wired (`android/key.properties` → `klaro-release.jks`, Gradle
    `signingConfigs.release`), so the APK is upload-signed. Store listing copy +
    permission declarations + data-safety answers in `STORE_LISTING.md`.
    Remaining before an actual submission (portfolio-polish step): 512×512 icon,
    1024×500 feature graphic, phone screenshots.

Phase 6 closed 2026-06-20. Next up (deferred by the user): **portfolio polish** —
repo READMEs with screenshots + architecture diagram, store graphic assets.

## Phase 7 — "Klaro Cloud" multi-tenant (code complete 2026-06-21)

Full plan + ADRs in `PHASE7_CLOUD_PLAN.md`. Turned Klaro from a single-user app
into a multi-tenant product.

- ~~**7.1 Identity & tenancy**~~ — Supabase Auth + Postgres; `user_id` + composite
  PKs + RLS on every table; FastAPI verifies the Supabase JWT and scopes by user.
  Data migrated Neon → Supabase.
- ~~**7.2 App + dashboard login**~~ — auth screens, session storage, gated UI.
- ~~**7.3 Ingestion abstraction + build split**~~ — source-agnostic `TxnCandidate`
  pipeline (`app/ingestion.py`); `source` column; non-SMS `POST /ingest/text`
  import (paste/forward) for the compliant build; Gradle `full`/`play` flavors +
  `kSmsEnabled` so the **Play build ships with no SMS permission** (verified) while
  the direct-APK **power build** keeps SMS auto-capture.
- ~~**7.4 Email, support & docs**~~ — hosted ToS/Privacy/Data-Deletion/Security/FAQ;
  in-app Help & support (contact + links). Resend transactional email deferred.
- ~~**7.5 Ops hardening**~~ — rate limiting (SlowAPI), Sentry on all 3 surfaces
  (backend/app/dashboard, opt-in via DSN), `pg_dump` backup script, `RUNBOOK.md`.
  Staging + UptimeRobot + Redis-backed limits documented as optional env steps.

**Owner activation (env/console, no code):** set the three Sentry DSNs; add an
UptimeRobot monitor; rotate Supabase DB + account passwords; enable Google OAuth;
decommission Neon; (for Play) build the signed `play` AAB + create a Play account.
App shipped as **v1.11.0+13** (`full` release APK built + signed).

---

## Suggested order

Phase 1 → 2 → 3 → 4 → 5 → 6. Phases 1–2 make the phone experience solid, Phase 3
makes it a real product you can use away from home, Phase 4 makes it
best-in-class, Phase 5 is polish, Phase 6 adds reliability tests, trends, and
Play Store readiness. Remaining: portfolio polish (READMEs, screenshots, assets).
