# Spec: capture-first Centtrail with EUR and INR

Status: ready-for-agent. Supersedes the "EUR only" and natural-language reporting decisions in [product scope](../product-scope.md) and the reporting parts of [design](../design.md). Terms follow the [glossary](../../GLOSSARY.md).

## Problem Statement

The owner moved off Budget Flow for three reasons: recording an expense was not convenient (no good voice path), the data could not be handed to a local coding agent for analysis without giving personal finance data to an online model, and Budget Flow cannot handle money that lives in both EUR and INR, with regular transfers from EUR to INR.

Centtrail copied Budget Flow's shape and inherited its weaknesses. Recording an expense still takes too many steps: getting to the form is slow, the form asks for too many fields, voice sometimes fills the wrong fields, and the capture screen is not elegant. Payees do not remember their category: payees that arrived through CSV import only carry an unaccepted proposed default, and saving an entry for an existing payee never sets one, so prefill rarely works. The Ask tab duplicates analysis the owner prefers to do on the laptop with a local 9B–27B model. And the ledger is EUR only, so INR spending and EUR→INR transfers cannot be recorded faithfully.

## Solution

Centtrail becomes a capture-first app. The phone records entries with as little effort as possible; analysis happens on the laptop through a local, read-only MCP server that lets the owner's local model query the ledger. Nothing leaves the owner's devices except iCloud sync.

- Capture is one redesigned card. Expense · Income · Transfer sit at the top; below them a large amount, the payee, and category, account and date as prefilled chips that are tapped only to change. Save is one tap. A mic button opens a listening overlay that transcribes, fills amount, payee and date, and disappears.
- The Action button and a Lock Screen/Control Center control open the card with the listening overlay already up. A Siri phrase records an entry with no UI at all.
- Payees remember their category: an empty default is filled by the first saved entry for that payee, and CSV import proposals are accepted automatically. The account defaults to the payee's last-used account.
- Every account has one currency (EUR or INR). Entries are in their account's currency. A transfer records the amount sent and the amount received, so the effective rate is in the data.
- Home shows this month's spending only, with separate EUR and INR totals, plus small gauges for categories with a monthly budget.
- Entries that could not be fully classified (from the no-UI Siri path) land in a review inbox shown on Home.
- The Ask tab and on-device report interpretation are removed.

## User Stories

### Capture: getting to the card

1. As the owner, I want pressing the Action button to open the capture card with the listening overlay already active, so that I can speak an expense with zero taps.
2. As the owner, I want a Lock Screen / Control Center control that opens the same listening card, so that I can capture without unlocking into the app first.
3. As the owner, I want the in-app + button to open the capture card without listening, so that I can type when speaking is awkward.
4. As the owner, I want to dismiss the listening overlay by tapping outside it, so that I can fall back to typing on the same card.
5. As the owner, I want Cmd-N on the Mac to open the capture card, so that capture works the same on the laptop.

### Capture: the card

6. As the owner, I want Expense · Income · Transfer at the top of the card, so that I choose the kind before anything else.
7. As the owner, I want the amount displayed large and centred, so that I can verify it at a glance.
8. As the owner, I want the amount shown with its account's currency symbol (€ or ₹), so that I can see which currency I am recording.
9. As the owner, I want category, account and date shown as prefilled chips, so that I only touch the fields that differ from usual.
10. As the owner, I want the date chip to default to today, so that I never set the date for an ordinary purchase.
11. As the owner, I want the account chip to default to the account I last used with this payee, so that I rarely pick an account.
12. As the owner, I want a new payee's account to default to my most recently used account, so that a first entry still needs few taps.
13. As the owner, I want the category chip to fill from the payee's default category as soon as the payee is known, so that I rarely pick a category.
14. As the owner, I want payee suggestions as I type, matching my existing payees and their aliases, so that I do not create near-duplicate payees.
15. As the owner, I want frequent-payee chips on the card, so that a repeat purchase is one tap plus an amount.
16. As the owner, I want a single Save button that saves and closes the card, so that recording ends in one tap.
17. As the owner, I want Save to tell me plainly which required field is missing, so that I can fix it without guessing.
18. As the owner, I want to edit an existing entry in the same card, so that I learn one interface.

### Capture: voice

19. As the owner, I want a mic button on the card that opens a listening overlay, transcribes what I say, and closes when I stop, so that voice is a quick, contained action.
20. As the owner, I want to see the transcript in the overlay while I speak, so that I know I was heard correctly.
21. As the owner, I want voice to fill only the amount, payee and date, so that there are fewer things for speech recognition to get wrong.
22. As the owner, I want the spoken payee matched against my known payees and aliases, so that "lidl" fills my existing Lidl payee.
23. As the owner, I want category and account filled from the matched payee's memory after voice fills the payee, so that a spoken "12.50 Lidl" produces a complete entry.
24. As the owner, I want relative dates like "yesterday" understood, so that I can record late.
25. As the owner, I want fields I did not mention to keep their current values, so that voice never wipes what I already set.
26. As the owner, I want voice parsing to work on-device, falling back to the keyword parser when Apple Intelligence is unavailable, so that no speech leaves my phone.
27. As the owner, I want a clear message when voice could not fill the card, so that I can type instead.

### Capture: Siri with no UI

28. As the owner, I want to say a Siri phrase such as "Centtrail 12.50 Lidl" and have the entry saved without opening the app, so that I can record hands-free.
29. As the owner, I want Siri to confirm what it saved (amount, payee, category), so that I know it worked.
30. As the owner, I want a Siri entry for a payee with a known default to be saved fully classified, so that it needs no follow-up.
31. As the owner, I want a Siri entry for a new payee or a payee with no default to be saved anyway and put in the review inbox, so that Siri never blocks me.

### Review inbox

32. As the owner, I want Home to show "N to review" when entries need attention, so that I do not forget them.
33. As the owner, I want to open each review entry in the capture card and fix it in one step, so that cleanup is quick.
34. As the owner, I want fixing the category of a review entry for a payee with no default to set that payee's default, so that the same payee never needs review again.
35. As the owner, I want review entries counted in totals in their recorded currency, so that this month's numbers stay honest even before I review.

### Payee memory

36. As the owner, I want a payee with no default category to adopt the category of the first entry I save for it, so that it prefills next time.
37. As the owner, I want CSV import's proposed payee defaults accepted automatically, so that every imported payee prefills.
38. As the owner, I want existing payees whose proposals were never accepted to get their proposed default when the app updates, so that my existing ledger benefits at once.
39. As the owner, I want choosing a different category on one entry to change only that entry, so that a one-off purchase does not change the payee's default.
40. As the owner, I want changing a payee's default in Settings to recategorise past entries that inherited it, so that history stays consistent (ADR 0002 stays in force).
41. As the owner, I want merged payees' aliases to resolve to the merged payee during capture, so that bank-style names still prefill.

### Currency

42. As the owner, I want every account to have one currency, EUR or INR, so that each entry's currency follows from where the money came from.
43. As the owner, I want to set an account's currency in Settings, so that I can mark my Indian bank account and INR cash as INR.
44. As the owner, I want expenses and income stored in their account's currency in minor units, so that amounts are exact.
45. As the owner, I want a transfer to record the amount sent from the source account and the amount received in the destination account, so that EUR→INR transfers are faithful.
46. As the owner, I want both transfer amounts required, because transfers are instant, so that no transfer is left half-recorded.
47. As the owner, I want a same-currency transfer to record one amount, so that moving EUR between N26 and Revolut stays simple.
48. As the owner, I want transfer mode on the card to show "Sent" and "Received" amounts in their accounts' currencies, so that I enter what my banking app shows.
49. As the owner, I want transfers excluded from spending in both currencies, so that sending money home is not counted as an expense.

### Migration

50. As the owner, I want my existing ledger migrated in place, so that I keep my history.
51. As the owner, I want all existing accounts to become EUR on migration, so that existing amounts keep their meaning.
52. As the owner, I want to mark the India account as INR after migration, so that future entries to it are in rupees.
53. As the owner, I want existing transfers to keep only their EUR sent amount, with the received amount left blank and not flagged for review, so that I am not asked to backfill history.
54. As the owner, I want changing an account's currency to be refused once it holds entries in its old currency, except for the migration case above, so that stored amounts never change meaning.

### Home

55. As the owner, I want Home to show this month's spending total only, with no comparison to last month, so that the number is calm and simple.
56. As the owner, I want separate EUR and INR spending totals on Home, never mixed or converted, so that the numbers are exact.
57. As the owner, I want a currency's total hidden when I have no spending in it this month, so that Home stays uncluttered.
58. As the owner, I want small gauges for each category that has a budget, showing spending against the budget this month, so that I can see where I stand.
59. As the owner, I want a gauge to turn amber at 80% and red at 100% of its budget, so that I notice overspending early.
60. As the owner, I want categories without a budget to have no gauge, so that Home shows only what I chose to track.
61. As the owner, I want recent entries listed on Home, so that I can spot a mistake right after recording.

### Budgets

62. As the owner, I want to set an optional fixed monthly budget on any spending category in Settings, so that I can track the categories I care about.
63. As the owner, I want each budget to name its currency, so that "Groceries €400" counts only EUR spending.
64. As the owner, I want budgets to reset every calendar month with no rollover, so that each month starts fresh.
65. As the owner, I want to remove a budget, so that its gauge disappears.
66. As the owner, I want budgets synced across my devices, so that the phone and Mac agree.

### Laptop analysis via MCP

67. As the owner, I want a local MCP server for my ledger, so that a local 9B–27B model can answer questions about my finances without any online model.
68. As the owner, I want the MCP server started by my MCP client on demand, so that I do not have to run anything by hand.
69. As the owner, I want the server to open the Mac app's synced ledger read-only, so that a weak model can never damage my data.
70. As the owner, I want a `describe_schema` tool that explains the tables, views, columns, currency handling and spending rules in plain words, so that the model writes correct SQL.
71. As the owner, I want a `query` tool that runs a single read-only SQL statement and returns rows, so that the model can answer arbitrary questions.
72. As the owner, I want a `spending` view that already excludes transfers, refunds-as-reductions, trashed entries and non-spending categories, so that the model gets spending right without knowing the rules.
73. As the owner, I want a `transfers_with_rate` view showing sent amount, received amount and the effective rate, so that I can analyse my remittances.
74. As the owner, I want a `budgets` view with each budget and its current-month spending, so that the model can report budget status.
75. As the owner, I want amounts in views exposed both as minor units and as decimal amounts with a currency code, so that the model does not mis-scale money.
76. As the owner, I want query results capped in size, with a note when they were truncated, so that a careless query cannot flood the model's context.
77. As the owner, I want any write, schema change or multi-statement attempt refused with a clear error, so that the model learns to stay read-only.
78. As the owner, I want the server to work while the Centtrail app is closed, so that analysis does not depend on the app being open.

### Removal of Ask

79. As the owner, I want the Ask tab removed, so that the app is focused on capture.
80. As the owner, I want the on-device report interpreter removed while voice capture parsing stays, so that unused code does not linger.

## Implementation Decisions

### Modules

- **Ledger** (deepened; the single test seam). Owns all new behaviour: payee-memory learning, currencies, two-amount transfers, migration, per-currency month totals, budgets, the review inbox, completing a parsed voice draft from payee memory, and read-only analysis queries. Shell, intents and the MCP executable are thin adapters over Ledger.
- **Interpreter** (shrunk). Keeps capture parsing only, reduced to extracting amount, payee text and date. Report interpretation, question periods and report follow-ups are deleted.
- **CenttrailShell** (rewritten capture, simplified Home). New capture card, listening overlay, Home with per-currency totals, budget gauges and review count. Ask screen removed. Settings gains account currency and category budgets.
- **App Intents**. "Open capture listening" for the Action button and control; "Record entry" for the no-UI Siri phrase, which calls Ledger to complete and save the entry.
- **centtrail-mcp** (new executable target in the same package). A stdio MCP server that resolves the Mac app's ledger file, opens it through Ledger in read-only mode, and maps the MCP tools onto Ledger's analysis interface. No logic of its own beyond transport.

### Ledger interface changes (shape, not final signatures)

- `Account` gains `currency` (EUR | INR). Setting currency is refused once the account holds entries, except the one-time migration path.
- Entry amounts are stored in minor units of their account's currency. A transfer stores `sentAmount` (source account currency) and `receivedAmount` (destination account currency). Recording a cross-currency transfer without both amounts is refused; a same-currency transfer requires the two to be equal and the UI asks for one.
- Recording an expense or income for a payee whose default category is empty sets that default to the entry's category with inherited provenance. Recording for a payee with a default and a different category is an override and leaves the default unchanged. Import proposals are applied as defaults directly; the proposed-default table is retired after migration applies any outstanding proposals.
- `completeDraft(amount:payeeText:date:)` (name to taste): resolves the payee by name or alias, fills the default category and the payee's last-used account (else most recently used account), and reports which fields could not be filled. Used by both the voice path and the Siri intent.
- `recordForReview(...)`: saves an entry whose category could not be resolved under the reserved "Uncategorised" category with a needs-review flag. Correcting the category clears the flag and, if the payee has no default, sets it.
- `reviewInbox()`: entries flagged for review, newest first.
- `homeSummary(on:)` is replaced by a month summary returning: the current calendar month range up to today, spending totals keyed by currency (only currencies with spending), recent entries, review count, and per-budget gauges (category, currency, budget amount, spent, fraction). The previous-period comparison is removed.
- Budgets: a synced record per category holding currency and monthly amount in minor units; at most one budget per category. Spending against a budget counts only entries in that budget's currency.
- Analysis: `Ledger.openReadOnly(at:)`, `describeSchema()` returning prose plus view/column descriptions, and `query(sql:limit:)` that accepts exactly one read-only statement, enforces SQLite read-only access (read-only open and query-only mode, not string inspection alone), and returns columns, rows and a truncated flag.
- Views maintained by migrations: `spending` (expenses in spending categories, not trashed, with currency code and decimal amount; refunds are income and do not reduce it, per ADR 0003), `transfers_with_rate` (date, from/to accounts, sent and received amounts with currencies, effective rate when both present), `budgets` (category, currency, amount, current-month spent).

### Schema and migration

- Add `currency` to account (default EUR). Add `received_amount` to entry for transfers (nullable only for migrated rows). Add needs-review flag to entry. Add budget table. Add the reserved Uncategorised category, which does not count as a payee default and is excluded from payee suggestions.
- Migration is in place: all existing accounts become EUR; existing transfers keep their amount as sent with received empty and no review flag; outstanding proposed payee defaults are applied. The owner then marks the India account INR once through a one-time allowance, since its existing transfers record the EUR side only.
- All new tables and columns must sync through SQLiteData/CloudKit like existing records (ADR 0004).

### Capture interactions

- Action button / control → card opens with listening overlay active. In-app + → card without overlay. Mac Cmd-N → card without overlay.
- The overlay uses on-device speech recognition; the transcript goes to Interpreter for amount/payee/date extraction, then to Ledger's draft completion. The overlay closes on end of speech or tap outside.
- Siri phrase → parse → complete draft → save fully classified or for review → spoken confirmation. Never opens the app.

### MCP server

- Launched by the owner's MCP client over stdio; configured once in that client. It does not depend on the app running; data freshness depends on the Mac app's last iCloud sync.
- Locates the sandboxed Mac app's ledger in its container by default, with an override argument for the path. macOS may show a one-time prompt allowing the client to access another app's data.
- Tools: `describe_schema`, `query`. No write tools.

## Testing Decisions

- A good test drives Ledger's public interface on an in-memory ledger (or a temporary on-disk ledger for read-only analysis) and asserts on observable results: saved entries, payee defaults, summaries, inbox contents, query rows and refusals. Tests never inspect SQL text, table internals or private helpers.
- **Single seam: the Ledger public API.** All new behaviour is placed in Ledger so it is testable there: payee-memory learning, import proposals applied, draft completion for voice and Siri, review inbox, currencies, transfers, migration, month summary per currency, budgets and gauges, read-only analysis (schema description, views, refusal of writes and multiple statements, truncation).
- Migration is tested by building a ledger in the pre-migration shape (EUR-only, transfers, unaccepted proposals) and asserting post-migration behaviour through the public API.
- Interpreter, Shell, intents and the MCP executable get no new tests; they are kept thin enough to verify by hand on device. Existing tests for removed features (Ask chat and evaluation, report follow-ups, home comparison) are deleted; existing Interpreter and entry-point tests are adjusted only where removed behaviour forces it.
- Prior art: `RecordEntryTests`, `ClassificationTests` and `ImportTests` for recording and payee defaults; `HomeSummaryTests` and `SpendingTests` for summaries; `AccountTests` for accounts; `SyncedStoreTests` for synced records. Reuse the `recordEntry`/`namedCategory` helpers in the test support file.

## Out of Scope

- On-phone reporting beyond the Home month summary, and any natural-language or AI reporting on device.
- Currency conversion, market exchange rates, or any combined EUR+INR total.
- Currencies other than EUR and INR, and per-entry currencies that differ from the account.
- Budget rollover, overall budget, or non-monthly budget periods.
- Write access from the MCP server, and typed report tools.
- Automatic, bank-triggered or notification-based capture.
- Account balances, savings tracking and custom charts.
- Backfilling received amounts for historical transfers.

## Further Notes

- Product scope, design and the glossary need updating to match: remove "EUR only" and natural-language reporting; add glossary terms **Currency** (of an account), **Sent amount** / **Received amount**, **Budget**, **Review inbox**. Record ADRs for the account-currency model and for removing on-device reporting in favour of the local MCP server; ADR 0001 is superseded.
- Payee-memory fix is the smallest, highest-value slice and can ship first, independently of currency work.
- Risk to verify early: opening the sandboxed app's WAL-mode SQLite read-only from another process while the app writes, and the macOS container-access prompt for the MCP client.
