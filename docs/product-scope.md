# Centtrail: product scope

Centtrail is a capture-first personal expense tracker for the owner, using an iPhone Air and an M-series MacBook Pro on iOS/macOS 26 or later. Both devices record and edit local data offline, then sync through the owner's iCloud account using SQLiteData and CloudKit ([ADR 0004](adr/0004-sync-first-with-sqlitedata.md)). Analysis happens on the laptop with a local model through a read-only MCP server.

The current implementation contract is the [capture-first EUR/INR spec](../.scratch/capture-first-two-currencies/spec.md); the [design](design.md) describes its module boundaries. This scope supersedes the earlier EUR-only and on-device natural-language reporting decisions.

## Capture

- One card on iPhone and Mac: Expense · Income · Transfer at the top, a large amount, payee, prefilled category/account/date chips, frequent-payee chips, suggestions matching names and aliases, and one Save button. Editing uses the same card. Save identifies missing required fields and keeps the card open.
- In-app + and Mac Cmd-N open the card for typing. The Action button and Lock Screen / Control Center control open it already listening, including from a cold start.
- A mic opens an overlay with a live transcript; it closes when speech ends or the owner taps outside, leaving the card open. On-device parsing extracts only amount, payee and date, including relative dates. Fields not mentioned retain their values. Apple's on-device model has a keyword-parser fallback.
- The date defaults to today. A known payee fills its category and last-used account; otherwise the account defaults to the most recently used account.
- A Siri phrase such as “Centtrail 12.50 Lidl” parses and saves without opening the app. A complete draft saves fully classified; an unresolved category saves to the review inbox. Siri confirms amount, currency, payee and category or “to review.” An unparseable amount saves nothing.

## Classification and review

- An expense or income saved for a payee without a default category establishes its first default. Choosing a different category when a default exists changes that entry only. Changing the default in Settings recategorises inherited history while preserving explicit overrides ([ADR 0002](adr/0002-retroactive-vendor-categories.md)).
- CSV import applies new payees' category defaults directly. Existing outstanding proposals are applied by migration; there is no proposal-acceptance step. Merging payees retains names as aliases rather than silently merging different businesses.
- Entries awaiting classification use the reserved Uncategorised category and count in spending. It never becomes a payee default and is excluded from payee suggestions and budgets.
- Home shows “N to review” only when needed. The inbox lists entries newest first and opens the capture card for correction. Correcting the category clears review status and establishes a missing payee default.

## Money, currencies and migration

- Every account has exactly one currency, EUR or INR. Entries use their account's currency and exact minor units; amounts show € or ₹. There is no conversion or combined EUR/INR total ([ADR 0005](adr/0005-account-currencies-and-transfer-amounts.md)).
- Transfers name source and destination accounts. Cross-currency transfers require both sent and received amounts; same-currency transfers ask for one and store equal amounts. Transfers are instant and never count as spending.
- The existing ledger migrates in place: accounts become EUR, amounts stay unchanged, and historical transfers retain only their sent amount without review flags. A one-time migration allowance lets the owner mark the India account INR. Otherwise an account with entries cannot change currency.
- Refunds are ordinary income and do not reduce spending ([ADR 0003](adr/0003-refund-is-income.md)). Transfers, trashed entries and non-spending categories such as savings do not contribute to spending.
- The owner selects the reporting date; CSV import maps it explicitly. Repeat imports skip definite duplicates and present uncertain matches for review. Imported amounts follow the target account's currency.
- Deleted entries remain in synced, recoverable trash for 30 days. Categories, payees and accounts are editable in Settings. There are no account balances or credit-card repayments.

## Home and budgets

Home shows spending from the first day of this calendar month through today, with separate EUR and INR totals and recent entries. A currency with no spending is hidden. There is no previous-month comparison.

Any spending category may have one optional fixed monthly budget, with amount and currency set, changed or removed in Settings. Budgets sync across devices, reset each calendar month and have no rollover. Home shows a small gauge only for budgeted categories, counting spending in that budget's currency: amber at 80%, red at 100%.

## Local laptop analysis

The Ask tab and on-device report interpretation are removed ([ADR 0006](adr/0006-local-read-only-analysis.md)). The on-device Interpreter remains only for capture. A local 9B–27B model can analyse the ledger through any MCP-capable client without sending financial data to an online model.

The client launches `centtrail-mcp` over stdio on demand. It opens the Mac app's synced ledger read-only, even while the app is closed; freshness depends on the last Mac sync. It supports a path override, explains the schema through `describe_schema`, and accepts one read-only SQL statement through `query`, with capped results and an explicit truncation flag. SQLite enforces read-only access. Spending, transfer-rate and current-month budget views expose minor units, decimal amounts and currency codes. macOS may prompt the client for container access.

## Validation and boundaries

New behaviour is tested through Ledger's public API, using in-memory ledgers and temporary on-disk ledgers for read-only analysis. Migration uses a pre-migration ledger fixture. Capture, voice, system entry points, Siri and MCP client integration require manual verification on the target devices; two-device sync must also be verified.

Out of scope: currencies beyond EUR and INR, exchange-rate feeds or conversion, account balances, savings tracking, custom charts, budget rollover or non-monthly budgets, write tools for MCP, on-phone reporting beyond Home, automatic bank-triggered capture, and backfilling historical received amounts.
