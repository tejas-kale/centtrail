# Capture-first Centtrail design

This design implements the [product scope](product-scope.md) and [capture-first EUR/INR spec](../.scratch/capture-first-two-currencies/spec.md), replacing the earlier v1 reporting design. Terms follow the [glossary](../GLOSSARY.md). Centtrail targets iPhone Air and M-series MacBook Pro on iOS/macOS 26+, with offline local storage and iCloud sync.

## Module responsibilities

| Module | Responsibility |
| --- | --- |
| Ledger | Money and classification rules, payee memory, account currencies, migration, transfers, review inbox, completed capture drafts, month totals and budgets, import/trash, and read-only analysis. Its public API is the single test seam. |
| Interpreter | Capture parsing only: amount, payee text and date. Apple Foundation Models runs on-device with a keyword fallback. Report operations, question periods and report follow-ups are removed. |
| CenttrailShell | Native capture card, listening overlay, Home, inbox and Settings. Thin presentation over Ledger; no Ask destination on either platform. |
| App Intents | Open capture listening for Action button/control; parse, complete and save a spoken entry without UI for Siri. |
| centtrail-mcp | Stdio transport mapping `describe_schema` and `query` to a read-only Ledger. Resolve the Mac app's ledger path by default and accept an explicit override. |

## Capture and entry points

The shared card places Expense · Income · Transfer at the top, then a large centred amount, payee and prefilled category/account/date chips, then Save. Frequent-payee chips and suggestions match both names and aliases. Editing opens the same card with the existing values. Missing fields produce a plain message without closing it.

In-app + and Mac Cmd-N open the card for typing. The Action button and Lock Screen / Control Center control open it with the listening overlay active, including on cold launch. The overlay shows the transcript and dismisses on end of speech or tapping outside, leaving the card available for typing. The mic can reopen it. Dynamic Type and dark mode are part of manual device verification.

Interpreter extracts only amount, payee text and date, including “yesterday.” Ledger completes a draft by resolving the payee's name or alias, its default category and its last-used account, with the most recently used account as fallback. It reports unresolved fields. Applying a partial voice result preserves fields the owner did not mention. The date initially defaults to today. Voice failure leaves a clear message and the editable card.

The Siri intent uses this same parse → complete → save flow and never opens the app. A fully classified draft saves normally; a missing category saves for review. Siri confirms amount, currency, payee and category or “to review.” If no amount can be parsed, it saves nothing.

## Domain records and money

| Record | Meaning |
| --- | --- |
| Account | Stable identity, name and one currency, EUR or INR. |
| Payee and alias | Identity, name and optional default category; aliases retained from explicit merges resolve to that identity. |
| Category | Editable classification, including whether it counts as spending. The reserved Uncategorised category is for review. |
| Entry | Expense, income or transfer; exact amount, selected reporting date, account references, classification provenance, edit/trash and review state. Transfers also carry a received amount. |
| Budget | At most one per spending category, holding a currency and fixed monthly amount in minor units. |
| Import provenance | Batch/source identities that distinguish repeat imports from legitimate identical purchases. |

An expense or income's currency comes from its account. Integer minor units represent cents or paise; presentation uses € or ₹. An internal transfer stores sent amount in its source currency and received amount in its destination currency. Both are required for new cross-currency transfers; same-currency transfers store equal amounts from one input. Historical transfers may lack a received amount. No path converts currencies or combines them into one total ([ADR 0005](adr/0005-account-currencies-and-transfer-amounts.md)).

Refunds are ordinary income, without an original-purchase link, and do not reduce spending ([ADR 0003](adr/0003-refund-is-income.md)). Spending includes active expenses in spending categories, including Uncategorised review entries, and excludes transfers, trash and non-spending categories. Preserve the owner-selected reporting date rather than shifting it with time zones.

## Payee memory and review

Saving a classified expense or income for a payee without a default learns its first default and records inherited provenance. Choosing a category different from an existing default records an entry override. Changing a default in Settings recategorises inherited entries while preserving overrides ([ADR 0002](adr/0002-retroactive-vendor-categories.md)). New import payees get defaults directly; no new proposals are created.

Ledger can save an incompletely classified entry under reserved Uncategorised with a needs-review flag. That category never becomes a payee default and is excluded from payee suggestions and budgets. The review inbox orders flagged entries newest first. Editing a review entry to a classified category clears its flag and learns a default if its payee still lacks one.

## Home and budget calculations

The month summary spans the first day of the current calendar month through the selected day. It returns spending totals keyed by currency, recent entries, total review count and a gauge per budget. Home hides currencies with no spending, shows no previous-month comparison and links “N to review” to the inbox only when the count is positive.

A budget gauge contains category, currency, monthly budget, spending in that category and currency this month, and fraction used. Budgets reset monthly without rollover and sync across devices. Settings supports setting, changing and removing them. Home colours gauges amber at ≥80% and red at ≥100%.

## Persistence, sync and migration

SQLiteData and CloudKit remain the storage/sync choice ([ADR 0004](adr/0004-sync-first-with-sqlitedata.md)); all new records and columns participate in sync under its schema rules. Offline captures and edits do not wait for iCloud. The library handles ordinary conflicts without a bespoke conflict workflow, and the UI indicates pending sync.

Migration upgrades the existing ledger in place. It assigns EUR to existing accounts without altering amounts, preserves old transfers' sent amounts with nullable received amounts and no review flag, and applies outstanding proposed payee defaults without changing explicit overrides. It adds the review category/state and budget records. A one-time allowance lets the owner mark the India account INR after migration; otherwise accounts holding entries cannot change currency. This in-place upgrade supersedes the earlier v2 clean-reimport choice for this release.

CSV import keeps explicit date-column mapping, category validation, reliable duplicate identities and review of uncertain matches. Amounts use the target account's currency. Trash remains recoverable and synced for 30 days.

## Read-only analysis

The owner configures a local MCP-capable client to launch `centtrail-mcp` over stdio with a local 9B–27B model. The executable opens the synced Mac ledger through `Ledger.openReadOnly(at:)`, using read-only SQLite open and query-only mode. The Mac app need not run; results reflect its last completed sync. A path override supports explicit selection. A macOS container-access prompt may appear for the client.

`describe_schema` explains tables, views, columns, minor units, decimal amounts, currency codes and spending rules. `query` accepts exactly one read-only SQL statement, returns columns and rows, caps result size and signals truncation; writes, schema changes and multiple statements fail clearly. SQLite enforces the write barrier, rather than relying on SQL text inspection.

Views maintained by migrations provide:

- `spending`: active spending expenses with amount in minor and decimal units and their account currency; income refunds never subtract from it.
- `transfers_with_rate`: date, source/destination accounts, sent/received amounts and currencies, plus the effective rate when both amounts exist.
- `budgets`: category, currency, budget amount and current-month spending in that currency.

This replaces on-device natural-language reporting and the Ask UI ([ADR 0006](adr/0006-local-read-only-analysis.md), superseding ADR 0001).

## Verification

New automated tests drive Ledger's public interface with observable entries, defaults, month totals, gauges, inbox state and analysis results. Use in-memory ledgers except temporary files for read-only and migration behaviour; build the pre-migration shape for migration coverage. Do not test private SQL or internal helpers. Existing tests for removed Ask/report interpretation and Home comparisons are retired; retained capture tests are adjusted where necessary.

Manual verification covers iPhone/Mac card editing, Dynamic Type and dark mode, overlay completion/dismissal, Action button and control cold starts, Siri confirmation/no-UI saves, two-device currency/budget sync and MCP queries while the Mac app writes in WAL mode. Record observed container-access behaviour in README when verified; do not infer it from a package test.

## Architectural decisions

- [ADR 0001: model-selected report operations](adr/0001-app-builds-reporting-sql.md), superseded by ADR 0006.
- [ADR 0002: retroactive payee category changes](adr/0002-retroactive-vendor-categories.md).
- [ADR 0003: refunds are income](adr/0003-refund-is-income.md).
- [ADR 0004: SQLiteData and CloudKit sync](adr/0004-sync-first-with-sqlitedata.md).
- [ADR 0005: account currencies and transfer amounts](adr/0005-account-currencies-and-transfer-amounts.md).
- [ADR 0006: local read-only analysis](adr/0006-local-read-only-analysis.md).
