# Klaro — Google Play Store listing

Reference copy for the Play Console listing + review forms. App id: `com.premm.klaro`.

---

## App name
**Klaro — Expense Tracker**

## Short description (≤ 80 chars)
Auto-logs your spending from bank SMS. No manual entry. Budgets, trends, privacy.

## Full description (≤ 4000 chars)

Klaro turns the transaction SMS your bank already sends into an effortless expense
tracker. No receipts, no spreadsheets, no typing in every coffee — the moment a
debit or credit alert arrives, it's parsed and logged automatically.

**Automatic, accurate logging**
Klaro reads bank and UPI transaction alerts and pulls out the amount, merchant,
date and direction (money in or out). It recognises the major Indian banks and
payment apps, dedupes repeat alerts so nothing is double-counted, and learns the
categories and names you prefer.

**See where your money goes**
• A clean monthly summary with a spending-by-category donut
• A daily spending chart for the current month
• A 6-month trends view so you can see if you're spending more or less over time
• Income vs spending net-flow, broken down by source

**Stay on budget**
Set an overall monthly limit or per-category budgets and get a heads-up
notification as you approach or cross them.

**Never miss a subscription**
Klaro detects recurring payments — subscriptions, EMIs and regular bills — and
predicts when each is next due. Cancelled something? Swipe to dismiss it.

**Built for privacy**
Your financial data stays on your device (and, if you choose, on a backend you
control). Klaro has no ads, no third-party trackers, and never sells your data.
Read the full policy: https://klaro-dashboard.vercel.app/privacy.html

**Optional companion dashboard**
Connect Klaro to your own sync server to view, search, edit and export your
transactions from a web dashboard.

Klaro was built to be the simplest possible way to actually know what you spend —
because the best expense tracker is the one you never have to think about.

---

## Category & rating
- **Category:** Finance
- **Content rating:** Everyone
- **Ads:** No
- **In-app purchases:** No

## Required URLs (hosted on the dashboard, static, no scripts)
- **Privacy policy:** https://klaro-dashboard.vercel.app/privacy.html
- **Data deletion** (Play data-safety requires this): https://klaro-dashboard.vercel.app/data-deletion.html
- **Terms of Service:** https://klaro-dashboard.vercel.app/terms.html
- **Security overview:** https://klaro-dashboard.vercel.app/security.html
- **Help / FAQ:** https://klaro-dashboard.vercel.app/help.html

## Contact
- **Email / support:** premmaradiya333@gmail.com

---

## Permissions — declarations for review

Google restricts SMS permissions; the **Permissions Declaration Form** in Play
Console must justify each. Klaro's core function *is* reading transaction SMS, so
it qualifies under the "financial management / transaction-based" use of SMS.

| Permission | Why Klaro needs it |
|---|---|
| `READ_SMS`, `RECEIVE_SMS` | **Core feature.** Detect and parse bank/UPI transaction alerts in real time and during a manual catch-up scan. This is the only way the app logs spending automatically — its primary advertised purpose. |
| `BROADCAST_SMS` | Receive the incoming-SMS broadcast that triggers parsing. |
| `READ_CONTACTS` | Optional. Show a friendly name when a payment is to/from a saved contact. Names read locally; contacts never leave the device. |
| `POST_NOTIFICATIONS` | Alert the user on a new captured transaction or a budget threshold. |
| `RECEIVE_BOOT_COMPLETED` | Re-arm the SMS listener after a reboot so transactions aren't missed. |
| `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | Keep the SMS listener alive so alerts aren't dropped by aggressive battery management. |
| `INTERNET` | Optional sync to the user-configured backend + optional AI category lookup (merchant name only). |

**SMS justification statement (for the form):**
> Klaro is a personal finance manager whose core feature is automatically recording
> the user's own bank transactions. It reads incoming SMS to identify bank/UPI
> transaction alerts and extract the amount, merchant and date. SMS access is
> essential and central to this functionality; no alternative API provides bank
> transaction data on the device. SMS content is processed on-device and is not
> shared with third parties.

---

## Data safety form answers

- **Does the app collect or share user data?** Collects; does not share with third parties.
- **Data types collected:** Financial info (transaction amounts, merchant, dates) and the transaction SMS text used to parse them.
- **Collected or only processed on device?** Processed on device; transmitted only to the user's own backend if they configure one.
- **Is data sold?** No.
- **Used for advertising?** No.
- **Encrypted in transit?** Yes (HTTPS to the backend).
- **Can the user request deletion?** Yes — delete in-app, revoke permissions, or uninstall to remove on-device data.

---

## Assets still needed before publishing (portfolio-polish step)
- App icon 512×512 (export from the existing adaptive icon source).
- Feature graphic 1024×500.
- Phone screenshots (≥ 2): home summary + donut, spending trends, upcoming payments.
