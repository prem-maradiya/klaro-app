# Klaro — Production & Store Readiness Audit

> **Audited:** 2026-06-22 · **App version:** v1.11.0+13 · **Verdict:** 🟠 NEEDS MAJOR IMPROVEMENTS · **Score:** 62/100
> **Scope:** full source review of all three repos (app / backend / dashboard), Android manifests, store listing, live device screenshots.
> Findings tagged `Verified` (seen in code/materials), `Inferred` (likely from stack/pattern), or `Needs testing` (requires a real device / live profiling).
> Severity weighted for a **1M-user** public launch.

---

## ✅ Knock-down tracker

Tick these as the app is finished. Ordered by priority. Detail for each is in the sections below.

### 🔴 Must fix before any store launch
- [ ] **1. Privacy/data-safety honesty** — SMS bodies are sent to Groq, but the policy says "on-device, not shared." Disclose Groq processing in `privacy.html` + Play data-safety, **or** redact PII before the call. *(legal/policy blocker)*
- [ ] **2. In-app account deletion** — add `DELETE /account` (wipes expenses, budgets, dismissals, learned categories) + a Settings action with typed-confirm. *(Play policy blocker)*
- [ ] **3. Turn on monitoring** — set the 3 Sentry DSNs; stop swallowing non-offline errors in `api_service.dart`.
- [ ] **4. Effective rate limiting** — `memory://` is per-instance on serverless → ineffective. Move to Upstash Redis `storage_uri`.
- [ ] **5. Build & verify the `play` AAB** — confirm zero SMS perms via `aapt`; create the Play Console account.
- [ ] **6. Input caps** — `max_length` on `IngestTextIn.text` / `ParseSmsIn.body`; bound `list_expenses` `limit`.
- [ ] **7. Cleartext traffic** — restrict via network-security-config (RFC1918 only); disable for the `play` flavor.

### 🟡 Recommended (quality / scale)
- [ ] **8. Fix "Other 90%" categorization** — verify `GROQ_API_KEY` is set in prod; ensure the AI fallback actually runs on import; expand brand DB. *(highest-leverage UX fix)*
- [ ] **9. Remove dead "API key" field** + stale Render copy in Settings.
- [ ] **10. Window/cache `/recurring`** (loads all rows in memory); add a `(user_id, date)` composite index.
- [ ] **11. Right-size the AI model** — `llama-3.1-8b-instant` for categorize, 70B only for SMS extraction; cache normalized-SMS → result.
- [ ] **12. Add CI** to the app and dashboard repos (backend already has `tests.yml`).
- [ ] **13. Lower DB pool defaults** in code (25/50 → 2/3) so a missing env var can't exhaust connections.
- [ ] **14. Permission-priming screen** before the first SMS request.
- [ ] **15. Fix `categorizer.py` docstring** ("Gemini" → Groq).

### 🟢 Future
- [ ] iOS build · Account Aggregator integration · investment tracking · tablet layouts · accessibility pass (Semantics + contrast).

---

## 30-Second Executive Summary

**🟠 NEEDS MAJOR IMPROVEMENTS · 62/100** — one notch above 🟡. The core is genuinely strong (auth and architecture are better than most production apps); the score is dragged down by store-policy and scale gaps, **not** by a broken app. For **personal/portfolio use it's effectively 🟡**; for a **public Play launch at 1M-user weighting it's 🟠**. The gap is a focused weekend, not a rewrite.

**Top 3 blockers**
1. **🔴 Privacy misrepresentation.** Store copy says *"SMS content is processed on-device and is not shared with third parties"* — but `ai_parse_sms` / `ai_classify` send raw SMS bodies + merchant names to **Groq**. False data-safety declaration → Play rejection/removal. `Verified`
2. **🔴 No in-app account deletion.** Play requires in-app deletion + a web route; you have only a "Delete your data" web link and no `DELETE /account`. `Verified`
3. **🟠 Flying blind at scale.** Sentry wired but **no DSNs set → monitoring OFF**; the API client swallows every error; rate-limiting is ineffective on serverless. `Verified`

---

## 1. Functional Testing

| Finding | Confidence |
|---|---|
| Core pipeline (SMS parse → dedupe → categorize → learn → store) is coherent and correctly wired. Dedupe via `raw_sms_hash`; 200-vs-201 on duplicates prevents double-counting. | `Verified` |
| **All API errors are silently swallowed** — every method in `api_service.dart` ends in `catch (_) {}` returning `null`/`false`. Intentional for offline-first, but a backend **500 is indistinguishable from "offline"** and never reaches Sentry. | `Verified` |
| `list_expenses` `limit` has **no upper bound** (`app/main.py` ~L156) — a client can request `limit=10000000`. | `Verified` |
| Recurring detection, budgets, trends, CSV export have correct server-side logic and edge handling (dead-sub pruning, cadence bands, income/spend separation). | `Verified` |
| Sync reconciliation treats "unreachable" as *not* "empty" to avoid wiping local data (`api_service.dart` ~L221). Good defensive design. | `Verified` |
| OAuth deep-link return, push notifications, background SMS capture on OEM battery-killers (Vivo) need real-device runs. | `Needs testing` |

## 2. UI/UX Review

| Finding | Confidence |
|---|---|
| **Vestigial "API key" field** in Settings (`settings_screen.dart` ~L105). Cloud backend dropped `X-API-Key` for Supabase JWT — field does nothing in prod and confuses users. | `Verified` |
| **Stale copy** — Settings hint shows `https://klaro-api.onrender.com` and references Render/`API_KEY` env; you're on Vercel. | `Verified` |
| **"Other — 90%"** dominates the home donut (live screenshot). Undercuts the "see where your money goes" promise on day one. Product defect, not cosmetic — see §11. | `Verified` |
| Visual design is genuinely polished — consistent dark theme, gradient brand, good type hierarchy. | `Verified` |
| Overflow-menu navigation flaky under automation; item touch targets may be tight. | `Needs testing` |

## 3. Mobile Responsiveness

| Finding | Confidence |
|---|---|
| Flutter scales by default; the one device captured (1080×2400) renders cleanly, no clipping. | `Verified` (single device) |
| Small phones (<360dp), foldables, tablets — the large ₹ hero number and chart axes are the likely overflow risks. No tablet breakpoints in code. | `Needs testing` |

## 4. Performance Audit — Rating 6/10

| Finding | Confidence |
|---|---|
| **`/recurring` loads every debit row into memory** and groups in Python per call (`app/main.py` ~L704) — no pagination/caching. Multi-year users scan thousands of rows per open. | `Verified` |
| **DB pool defaults serverless-hostile** — code default `pool_size=25, max_overflow=50` = up to 75 conns/instance (`database.py` ~L27). Works today only because `DB_POOL_SIZE=2` env exists; one missed env on a new environment = outage. | `Verified` |
| **AI calls run synchronously inside the request while holding a DB connection** (up to 15s Groq timeout). Under load this exhausts the pool. | `Verified` |
| No composite `(user_id, date)` index — month-range queries narrow by `user_id` (indexed) then sort `date` unindexed. Fine per-user, suboptimal at scale. | `Verified` |
| Good: summaries/months aggregate in SQL, not Python. | `Verified` |
| Vercel cold-start latency, real query timings. | `Needs testing` |

## 5. Security Audit — strong core, scale & disclosure gaps

| Risk | Severity | Confidence | Fix |
|---|---|---|---|
| **Auth** — ES256 verified vs Supabase JWKS with `audience`+`issuer`+`require[sub,exp]`; no shared secret. | ✅ Exemplary | `Verified` | — |
| **Authorization** — every query scoped by `user_id`; ownership returns **404 not 403** (no foreign-ID disclosure). | ✅ Strong | `Verified` | — |
| **Third-party SMS exposure undisclosed** — SMS bodies → Groq; policy claims on-device-only. | 🔴 High | `Verified` | Disclose in policy + data-safety, or redact PII pre-send. |
| **Rate limiting ineffective on serverless** — `memory://` is per-instance; real cap ≈ limit × instance-count. | 🟠 High | `Verified`/`Inferred` | Upstash Redis `storage_uri`. |
| **No input size caps** — `IngestTextIn.text`/`ParseSmsIn.body` unbounded → large payload forwarded to Groq (cost) + stored. | 🟡 Medium | `Verified` | `Field(max_length=2000)`. |
| **Cleartext traffic enabled app-wide** (`usesCleartextTraffic="true"`) for local HTTP backends. | 🟡 Medium | `Verified` | network-security-config (RFC1918 only); off for `play`. |
| **CORS defaults to `*`** if `CORS_ORIGINS` unset (`main.py` ~L47). | 🟡 Medium | `Inferred` (prod env unverified) | Confirm set in Vercel; fail closed if missing. |
| Passwords delegated to Supabase; anon key in repo is the publishable key (safe by design). | ✅ Low | `Verified` | — |

**OWASP Top 10:** A01 ✅ · A02 ✅ · A03 ✅ (ORM-parameterized, no raw SQL w/ user input) · A04 — rate-limit + input-cap gaps · A09 🔴 (monitoring off, errors swallowed).

## 6. User Journey Testing

| Step | Finding | Confidence |
|---|---|---|
| New: Sign Up → Onboarding | No value-explainer before the SMS request — a finance app asking for SMS cold is a trust/drop-off risk. | `Inferred` |
| New: First Action | Empty-state CTA exists; brand-new user sees empty charts until the SMS scan completes. | `Verified` |
| Existing: Login → Daily → Logout | Clean; sign-out has a reassuring confirm. **No account-deletion path.** | `Verified` |
| Upgrade/Purchase | N/A — no monetization. | `Verified` |

## 7. Data Validation

- **Backend (good):** month `YYYY-MM` validated, year range-checked, budget category whitelisted, amounts via Pydantic, AI output validated (`amount>0`, category ∈ `CATEGORIES`). `Verified`
- **Gaps:** no max length on free-text inputs; `limit`/`skip` unbounded. `Verified`
- **Client:** URL normalized; minimal form validation elsewhere. `Verified`

## 8. Accessibility Audit (WCAG 2.1 AA)

| Finding | Confidence |
|---|---|
| `textMuted`/`textFaint` at 11.5–12.5px on dark surfaces likely **below 4.5:1 contrast** — needs a check. | `Inferred` |
| Screen-reader labels (Semantics) on icon-only buttons (donut, charts, FAB) not evident in code. | `Needs testing` |
| Touch targets, dynamic font scaling, focus order. | `Needs testing` |

## 9. Production Readiness

| Item | Status | Confidence |
|---|---|---|
| Error monitoring | 🔴 Wired but **OFF** (no DSNs) | `Verified` |
| Error logging | 🟡 Backend logs startup; **client swallows all errors** | `Verified` |
| Analytics | 🔴 None | `Verified` |
| Backups | ✅ `backup_db.py` + Supabase daily | `Verified` |
| DR / runbook | ✅ `RUNBOOK.md` | `Verified` |
| Privacy / ToS | ✅ Hosted (but content inaccurate — §1/§5) | `Verified` |
| Support channel | ✅ mailto | `Verified` |
| CI | 🟡 Backend only; **app & dashboard none** | `Verified` |

## 10. Store Readiness — not ready

| Probable rejection reason | Severity | Confidence |
|---|---|---|
| **Data-safety form will mislead** — declares no third-party sharing while SMS goes to Groq. | 🔴 Blocker | `Verified` |
| **No in-app account deletion** (Play "Delete account" policy). | 🔴 Blocker | `Verified` |
| `full` (SMS) build **cannot** go on Play under SMS policy; only the `play` AAB can, and it **isn't built yet**. | 🟠 Major | `Verified` |
| Cleartext traffic flag set in shipping manifest. | 🟡 Medium | `Verified` |
| READ_CONTACTS ships in **both** flavors (incl. Play) — needs accurate data-safety + in-context rationale. | 🟡 Medium | `Verified` |
| Apple App Store: no iOS build exists. | ➖ N/A today | `Verified` |

## 11. AI Product Review

| Finding | Confidence |
|---|---|
| **Prompt quality good** — constrained categories, `temperature=0`, `response_format=json_object`, output validated. Merchant name can still be fabricated. | `Verified` |
| **"Other 90%" is an AI/coverage problem.** Either `GROQ_API_KEY` isn't set in prod (fallback silently no-ops) or the fallback isn't invoked on import. **Highest-leverage fix for perceived quality.** | `Verified` (observed) + `Inferred` (cause) |
| **Cost/scale:** one **shared** `GROQ_API_KEY` = a single global rate-limit bucket for all users; no caching of identical SMS bodies (only merchant→category cached); 70B model for an 8-token classification. | `Verified` |
| **Right-sizing:** `llama-3.1-8b-instant` for categorize, reserve 70B for extraction; cache normalized SMS-body → result. | `Verified` |

## 12. Competitive Review

| Competitor | Klaro's edge | Klaro's gap |
|---|---|---|
| **Axio (ex-Walnut)** | Privacy-first, no ads, self-host, no lending push | No Account Aggregator integration; no credit/lending |
| **Cred** | Far simpler, SMS-automatic, no rewards gimmicks | No bill-pay, card management, rewards |
| **ET Money / Money Manager** | Zero manual entry; automatic capture | No investment/MF tracking, goals; Android-only |

**Genuine advantage:** truly automatic, on-device, privacy-respecting capture. **Biggest weaknesses:** Android-only; no Account Aggregator (the regulated future of the category); categorization coverage.

## 13. Bug / Issue Report

| Severity | Confidence | Screen/Module | Issue | Impact | Fix |
|---|---|---|---|---|---|
| Critical | Verified | Privacy/AI | SMS sent to Groq but declared on-device-only | Store removal, legal | Disclose or redact pre-send |
| Critical | Verified | Account/Settings | No in-app account deletion | Play rejection | `DELETE /account` + Settings action |
| High | Verified | Observability | Sentry DSNs unset → no monitoring | Blind to prod failures | Set 3 DSNs |
| High | Verified | Rate limiting | `memory://` per-instance on serverless | Limits ineffective; cost/abuse | Upstash Redis |
| High | Verified | api_service.dart | All errors swallowed (`catch(_){}`) | Silent failures, no telemetry | Log to Sentry; surface non-offline errors |
| Medium | Verified | database.py | Pool default 25/50 on serverless | Connection exhaustion if env missing | Lower defaults + assert env |
| Medium | Verified | main.py `/recurring` | Loads all rows in memory | CPU/mem at scale | Window query + cache |
| Medium | Verified | Pydantic models | No input length caps | Cost/DoS via large text | `max_length` |
| Medium | Verified | Manifest | Cleartext traffic enabled | Insecure transport | network-security-config |
| Low | Verified | Settings | Dead "API key" field + stale Render copy | User confusion | Remove/relabel |
| Low | Verified | categorizer.py | Docstring says "Gemini" but uses Groq | Maintainer confusion | Fix comment |

## 14. Final Readiness Score

| Category | Score /10 | Weight | Justification |
|---|---|---|---|
| Functionality | 8 | 20% | Solid core; error-swallowing & unbounded limit dock it |
| Security | 7 | 20% | Exemplary auth; rate-limit/cleartext/disclosure gaps |
| UI/UX | 7 | 15% | Polished, but dead field + "Other 90%" |
| Performance | 6 | 15% | SQL aggregation good; recurring/pool/sync-AI risks |
| Reliability | 5 | 10% | Monitoring off, no app CI, silent errors |
| Accessibility | 5 | 10% | Largely untested; likely contrast/target issues |
| Store Readiness | 3 | 10% | Two hard blockers |

**Weighted total = 1.60 + 1.40 + 1.05 + 0.90 + 0.50 + 0.50 + 0.30 = 6.25 → 62.5/100**

## 15. Publish Decision

### 🟠 NEEDS MAJOR IMPROVEMENTS

Not because the app is weak — the architecture and auth are better than most production apps — but because publishing to a store at scale has two non-negotiable blockers (privacy disclosure, account deletion) plus monitoring being off and rate-limiting being ineffective on serverless. Personal/portfolio use ≈ 🟡; public Play launch at 1M weighting = 🟠. The gap is a focused weekend.

## 16. Launch Checklist

See the **Knock-down tracker** at the top of this document — it is the actionable, ordered version of §15's checklist.

---

### What I (Claude) can implement in-code now, when you say go
- **#2 account deletion** — backend `DELETE /account` + Settings UI with typed-confirm (full).
- **#6 input caps + bounded limit** (full).
- **#9 remove dead API-key field + stale copy** (full).
- **#10 `/recurring` windowing + composite index** (full).
- **#11 AI right-sizing + cache** (full).
- **#13 pool defaults**, **#15 docstring** (trivial).
- **#8 "Other 90%"** — I can investigate the root cause directly.

### What needs your console/account access (I can guide)
- **#1** privacy-policy edit + Play data-safety form · **#3** Sentry DSNs · **#4** Upstash Redis · **#5** Play account + signed AAB · **#7** verify in prod env.
