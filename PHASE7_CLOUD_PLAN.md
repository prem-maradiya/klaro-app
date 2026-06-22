# Klaro — Phase 7: "Klaro Cloud" (multi-tenant, production-grade)

**Status:** Code complete (2026-06-21) — activation steps (env/console) remain with the owner · **Owner:** Prem Maradiya · **Drafted:** 2026-06-20
**Goal:** Take Klaro from a polished single-user app to a professional product that
could safely serve thousands of users — real accounts, isolated data, support,
legal docs, and operations — without throwing away the existing codebase.

---

## 1. Vision & success criteria

Klaro becomes a product a stranger can sign up for, trust with their financial
data, get help with, and rely on. Concretely, Phase 7 is "done" when:

- A new user can **sign up, log in, and see only their own data** on both the app and the dashboard.
- Data isolation is **enforced by the database** (not just app code) — a bug can't leak one user's money to another.
- The app has a **compliant path to the Play Store** plus a power build with SMS.
- There is **transactional email**, a **support channel**, and a complete **legal/doc set**.
- We have **staging, error tracking, backups, and rate limits** — i.e. we'd notice and survive an incident.

**Non-goals for Phase 7:** payments/subscriptions billing, Account Aggregator
integration (reserved for Phase 8), iOS build, web sign-up funnel/marketing site.

---

## 2. Architecture decisions (locked)

### ADR-1 — Auth & tenancy: Supabase (Postgres + Auth + RLS) + existing FastAPI
- **Why:** We're already on Postgres, so Supabase is a natural migration and gives **Row-Level Security** — per-user isolation enforced by the DB. FastAPI is kept as the business/API layer (parsing, recurring detection, the 21 tests); it verifies the Supabase JWT and scopes by `user_id`. Minimal throwaway, strong portfolio signal.
- **Rejected:** Custom JWT (reinvents security primitives for money data), Clerk/Auth0 (tenancy still hand-rolled, split vendors), Firebase (NoSQL rewrite of SQL aggregates/detection).

### ADR-2 — Data source & distribution: compliant build now, Account Aggregator later
- **Why:** Google Play heavily restricts SMS permissions and the industry is being forced off them. We ship a **pluggable ingestion layer** so:
  - **Play build:** manual entry + UPI/receipt-email import (passes review).
  - **Direct-APK power build:** adds SMS auto-capture (a build flag).
  - **Phase 8:** Account Aggregator (Setu/Finvu) slots in as a new source with no rework.
- **Rejected:** SMS-only + risk Play review (building on a permission Google is killing); AA-first (stalls momentum, no shippable product); off-Play only (caps growth).

---

## 3. Current state → target state

| Concern | Today | Phase 7 target |
|---|---|---|
| Identity | none (one global API key) | Supabase Auth: sign-up, login, reset, account delete |
| Tenancy | one shared DB, no `user_id` | `user_id` on every row + RLS policies |
| API auth | static `X-API-Key` | Supabase JWT verified per request; key retired for end users |
| DB host | Neon | Supabase Postgres (migrated) |
| Ingestion | SMS only | Source abstraction: manual / email-UPI / SMS / (AA later) |
| Email | none | Resend transactional (welcome, reset, alerts) |
| Support | none | support@ inbox + in-app contact + help/FAQ page |
| Docs | privacy only | + ToS, data-deletion, security, refund/data-export |
| Ops | push-to-prod | staging env, Sentry, rate limits, scheduled backups |

---

## 4. Data model changes

Add ownership to every user-owned table and enforce it with RLS.

```sql
-- On expenses, budgets, merchant_categories, recurring_dismissals:
ALTER TABLE <t> ADD COLUMN user_id uuid NOT NULL
  REFERENCES auth.users(id) ON DELETE CASCADE;
CREATE INDEX ix_<t>_user ON <t>(user_id);

ALTER TABLE <t> ENABLE ROW LEVEL SECURITY;
CREATE POLICY "<t>_owner" ON <t>
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());
```

- Primary keys that were global (e.g. `merchant_categories.merchant_norm`) become
  **composite** `(user_id, merchant_norm)` so two users can label the same merchant differently.
- `budgets.category` PK → `(user_id, category)`. Same for `recurring_dismissals`.
- Defense-in-depth: FastAPI *also* filters by the authenticated `user_id`; RLS is the backstop.

---

## 5. Auth flow (target)

```
App / Dashboard  ──login──▶  Supabase Auth  ──issues──▶  JWT (access + refresh)
        │                                                     │
        └────────── request + Bearer JWT ───────────────▶  FastAPI
                                                              │ verify JWT (Supabase JWKS)
                                                              │ extract user_id (sub claim)
                                                              ▼
                                                          Postgres (RLS by auth.uid())
```

- App stores tokens in secure storage (`flutter_secure_storage`); refresh on expiry.
- Dashboard uses the Supabase JS client for the session; sends the access token to FastAPI.
- FastAPI: a `get_current_user` dependency replaces the API-key middleware for user routes; `/health` stays open. A service role key is used only for admin/cron tasks.

---

## 6. Ingestion abstraction (enables ADR-2 + Phase 8)

A single internal contract every source produces:

```python
# A normalized transaction candidate, regardless of where it came from.
class TxnCandidate(BaseModel):
    merchant: str; amount: float; date: datetime
    direction: str          # debit | credit
    source: str             # manual | sms | email | upi | aa
    raw_ref: str | None     # original text/id for dedupe
```

Sources implemented in Phase 7: `manual`, `sms` (power build), `email/upi import`.
Phase 8 adds `aa`. The dedupe, categorize, learn, and store pipeline stays
source-agnostic — so adding Account Aggregator later is "just another source."

---

## 7. Email & support

- **Transactional email:** Resend (free tier ~3k/mo). Templates: welcome, email-verify, password-reset, budget-alert (optional digest later). Sent via a small FastAPI worker/endpoint or Supabase's built-in auth emails for verify/reset.
- **Support:**
  - `support@klaro.app` (or a Gmail alias initially) — reachable from the app's Settings ("Contact support") and the dashboard footer.
  - In-app "Contact us" composes a prefilled email with app version + device.
  - A **Help / FAQ page** hosted on the dashboard (`/help`), same static-page pattern as `/privacy.html`.

---

## 8. Document & template set (the "professional docs")

Produced in Phase 7.4, hosted on the dashboard and linked in-app + on Play:

| Document | Purpose | Status |
|---|---|---|
| Privacy Policy | data handling (legal requirement) | ✅ exists (`/privacy.html`) — will update for accounts |
| Terms of Service | usage terms, liability, account rules | ⬜ to write |
| Data Deletion Policy | how users delete their account/data (Play requirement) | ⬜ to write |
| Security Overview | encryption, RLS, secrets — trust page | ⬜ to write |
| Data Export note | user's right to export (CSV already exists) | ⬜ to write |
| Support / FAQ | self-serve help | ⬜ to write |
| Store listing | Play copy + declarations | ✅ exists (`STORE_LISTING.md`) — will update |
| Internal: Runbook | deploy, rotate secrets, restore backup, incident steps | ⬜ to write |
| Internal: Architecture (ADR) | this document + diagram | ✅ this file |

Compliance note: India's **DPDP Act 2023** applies — these cover consent, purpose
limitation, deletion rights, and a grievance contact.

---

## 9. Observability & ops

- **Error tracking:** Sentry (free tier) in FastAPI + Flutter + dashboard.
- **Staging:** a second Supabase project + Vercel preview + a `staging` API deploy, so changes are tested before prod.
- **Rate limiting:** per-user/IP limits on FastAPI (e.g. SlowAPI) to stop abuse and protect the DB.
- **Backups:** Supabase daily backups (verify retention on free tier; add a scheduled `pg_dump` to object storage if needed).
- **Health/uptime:** keep `/health`; add an uptime monitor (e.g. UptimeRobot).

---

## 10. Phased execution breakdown

Each sub-phase is independently shippable and ordered by dependency.

**7.1 — Identity & tenancy (foundation)**
- Create Supabase project; migrate schema from Neon to Supabase Postgres.
- Add `user_id` + composite PKs + RLS to all user tables.
- FastAPI: JWT verification dependency; scope every query by `user_id`; retire end-user API key.
- Migrate *your* existing rows under your new account (no data loss).
- Tests: extend the pytest suite for per-user isolation (user A can't read user B).

**7.2 — App & dashboard login**
- App: auth screens (sign-up/login/reset), secure token storage, session refresh, sign-out; gate the app behind auth; offline cache stays per-user.
- Dashboard: Supabase login, send token to FastAPI, per-user views.

**7.3 — Ingestion abstraction + compliant build** — *backend foundation DONE 2026-06-21*
- ✅ Introduce `TxnCandidate` + source pipeline; refactor SMS path onto it.
  - NEW `app/ingestion.py`: `TxnCandidate` contract + `ingest()` (source-agnostic
    dedupe → categorize → learn → store) + the merchant-learning helpers + a
    `candidate_from_expense_create` adapter (infers `source` from `raw_sms` for
    older app builds). `create_expense` is now a thin adapter over it.
  - NEW `source` column on `expenses` (manual|sms|email|upi|aa), self-migrated on
    startup; surfaced in `ExpenseOut`. NEW `app/config.py` holds `APP_TZ` (shared,
    no import cycle). 9 new tests (`tests/test_ingestion.py`); suite 29 → **38 pass**.
- ✅ UPI/receipt-email import source adapter — `POST /ingest/text` (AI-parse →
  TxnCandidate → ingest); app `ApiService.ingestText` + `ImportTextSheet` (paste a
  bank/UPI message), surfaced in the home menu + empty state.
- ✅ Build flag splitting Play (no SMS) vs power (SMS) — Gradle `full`/`play`
  flavors + `src/full` (SMS perms + receiver) / `src/play` manifests +
  `kSmsEnabled` (`--dart-define=KLARO_SMS`) gating every SMS code path.
  **Verified:** the `play` APK declares no SMS/location perms + no receiver; the
  `full` APK keeps them. Build: `flutter build apk --release --flavor full
  --dart-define=KLARO_SMS=true` / `appbundle ... --flavor play --dart-define=KLARO_SMS=false`.

**7.4 — Email, support & document set** — *DONE 2026-06-21 (Resend deferred to owner)*
- ✅ Doc set (ToS, Data-Deletion, Security, FAQ, updated Privacy) hosted on the
  dashboard; ✅ in-app "Help & support" in Settings (Contact support mailto + links
  to Help/Privacy/Terms/Delete-data via `url_launcher`); ✅ Supabase sends auth
  (verify/reset) emails.
- ⬜ Custom transactional email (Resend) — needs the owner's Resend account.

**7.5 — Ops hardening** — *backend code/config DONE 2026-06-21 (activation = user env)*
- Sentry (3 surfaces), staging env, rate limits, backups, uptime monitor.
- ✅ **Rate limiting** — SlowAPI in `app/observability.py`: global per-user/IP cap
  (`RATELIMIT_DEFAULT`=600/min — sized to clear a full import burst of ~200 POSTs)
  via `SlowAPIMiddleware` + tighter `RATELIMIT_PARSE` (30/min, just above the app's
  25/import AI cap) on the AI `/parse-sms` route; `/` and `/health` exempt; 429
  handler wired inside CORS. Keyed by JWT `sub` (unverified, bucket-only) → client IP fallback.
  In-memory by default; `RATELIMIT_STORAGE_URI` → Redis for cross-instance limits.
- ✅ **Sentry (all 3 surfaces)** — backend `init_sentry()` (`SENTRY_DSN`), Flutter
  `SentryFlutter.init` in `main.dart` (`--dart-define=SENTRY_DSN`, `sentry_flutter`
  9.x — 8.x's Kotlin lang-version 1.6 was rejected by the project's Kotlin 2.2),
  dashboard `@sentry/react` in `main.jsx` (`VITE_SENTRY_DSN`). All no-op without a
  DSN, all `sendDefaultPii=false`.
- ✅ **Backups** — `scripts/backup_db.py` (gzipped `pg_dump` → `backups/`, `--keep N`
  prune) + restore procedure in the new `RUNBOOK.md`.
- ✅ **Runbook** — `expense_tracker_backend/RUNBOOK.md`: deploy, env, rate-limit/Sentry
  config, backup/restore, secret rotation, incident response, monitoring, staging.
- ✅ **Tests** — `tests/test_ops.py` (5): 429-after-threshold, /health exempt, Sentry
  no-op/enabled-config/bad-DSN. Full suite 24 → **29 pass**.
- ⬜ **User activation** (env only, no code): set `SENTRY_DSN` on Vercel; add an
  UptimeRobot monitor on `/health`; (optional) Upstash Redis → `RATELIMIT_STORAGE_URI`;
  (optional) a staging Supabase project + Vercel preview. Deps `slowapi`,
  `sentry-sdk` added to `requirements.txt` — a redeploy picks them up.
  **Not yet committed/deployed** (backend is a git repo; awaiting your go-ahead).

**7.6 — Release**
- Re-verify on device; submit the compliant Play build; publish power APK.

*(Phase 8, later: Account Aggregator integration; billing/subscriptions; iOS.)*

---

## 11. Risks & mitigations

| Risk | Mitigation |
|---|---|
| Play rejects SMS even on power build | Power build is **direct-APK only**; Play build has no SMS — decoupled. |
| Data migration loses/mislabels rows | Migrate to staging first; row-count + checksum verification; keep Neon as backup until verified. |
| RLS misconfig leaks data | App-layer `user_id` filter as belt-and-suspenders; explicit isolation tests in CI. |
| Free-tier limits hit at scale | Monitor Supabase DB size / MAU + Resend volume; documented upgrade path. |
| Secret leakage | Secrets in Vercel/Supabase env only, never in repos; rotation steps in the runbook. |
| Solo-dev bandwidth | Sub-phases are independently shippable; can pause between any of them. |

---

## 12. Cost model (start = ₹0)

| Service | Free tier (verify current) | Upgrade trigger |
|---|---|---|
| Supabase | ~500MB DB, ~50k MAU, daily backups | DB size / MAU growth |
| Vercel | hobby (dashboard + API) | bandwidth / commercial use |
| Resend | ~3k emails/mo, 100/day | email volume |
| Sentry | ~5k events/mo | error volume |
| **Total** | **₹0 to launch** | scales with real usage |

---

## 13. Decisions (resolved 2026-06-20)

1. **Brand domain:** ✅ Deferred — register a domain *before publishing*. Until then, Gmail alias + Vercel URLs for `support@`/hosted docs.
2. **Neon vs Supabase Postgres:** ✅ **Move fully to Supabase** and retire Neon once the migration is verified (one platform, RLS native).
3. **Email verification at sign-up:** ✅ **Required.**
4. **Google sign-in:** ✅ **Yes** — include Google OAuth in 7.2 (most users prefer it). Email/password + Google both supported.

---

*This document is the source of truth for Phase 7. It will be updated as
sub-phases complete (mirroring the ROADMAP.md convention).*
