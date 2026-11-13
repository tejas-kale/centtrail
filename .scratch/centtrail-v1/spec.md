# Centtrail v1

Status: ready-for-agent

## Problem Statement

The owner tracks personal EUR income and expenses across N26, Revolut and cash, on an iPhone Air and an M-series MacBook Pro. Their current tool needs too much effort per entry. It cannot answer plain questions such as "how much did I spend on restaurants this month compared with last month?" without manual filtering. Two years of history sit in a CSV export from that tool, and moving to anything new must not lose it.

The owner wants:

- capture fast enough to do right after paying
- categories that fill themselves in from the vendor
- reports they can ask for in their own words, which still work offline and when Apple Intelligence is unavailable

## Solution

Centtrail is a native iPhone and Mac app that keeps the owner's transactions on each device and syncs them through the owner's iCloud account.

**Capture.** The owner records an entry from a Shortcut or keyboard shortcut. Either they fill a short form with suggested fields, or they type or dictate a sentence that the on-device model parses into a draft. The owner always confirms an editable draft before it is saved.

**Classification.** Every saved entry has a category. The category comes from the counterparty's default category unless the owner overrides it for that entry.

**Reports.** The owner asks questions in natural language. The on-device model picks one of four supported report operations and its parameters. The app validates them, builds the SQL, computes exact results and shows them as a number, chart, table or transaction list. Preset reports and manual capture work without the model.

**History.** Existing history comes in through a CSV import with a preview, category validation and duplicate review.

## User Stories

### Capture

1. As the owner, I want to start capture from a Shortcut on my iPhone, so that I can record a purchase seconds after paying.
2. As the owner, I want to start capture from a keyboard shortcut on my Mac, so that I can record entries while at my desk.
3. As the owner, I want a short form with amount, kind, counterparty, reporting date and category, so that I can record an entry without the model.
4. As the owner, I want to type a sentence such as "20 at Middle Eats yesterday", so that capture needs no field-by-field input.
5. As the owner, I want to dictate that sentence with system dictation, so that I can capture hands-free.
6. As the owner, I want parsed text to open as an editable draft, so that I can fix mistakes before anything is saved.
7. As the owner, I want nothing saved until I confirm, so that a wrong parse never becomes data.
8. As the owner, I want the category pre-filled from the counterparty's default category, so that I rarely choose it by hand.
9. As the owner, I want to override the category for one entry, so that an unusual purchase is classified correctly without changing the vendor.
10. As the owner, I want saving blocked until a category is set, so that every entry appears in category reports.
11. As the owner, I want the reporting date to default to today and stay editable, so that I can file a payment under the date I care about.
12. As the owner, I want to add a note to an entry, so that I remember context such as "for the stay on April 29–30".
13. As the owner, I want a new counterparty name to create a counterparty with the chosen category as its default, so that the next entry for it is pre-filled.
14. As the owner, I want capture to work offline, so that missing signal never stops me recording.
15. As the owner, I want capture to keep working when Apple Intelligence is unavailable, so that the form remains a reliable fallback.

### Classification

16. As the owner, I want to set a vendor's default category, so that its future and inherited past entries share one category.
17. As the owner, I want changing a vendor's default category to recategorize past entries that inherited it, so that history matches my current view (ADR 0002).
18. As the owner, I want entries with an explicit category override to keep their category when the vendor default changes, so that deliberate choices are never lost.
19. As the owner, I want changing one entry's category to leave the vendor's default alone, so that one-off purchases do not change the vendor.
20. As the owner, I want to confirm that "AMZN MKTP" is an alias of "Amazon", so that both names resolve to one vendor.
21. As the owner, I want different businesses never merged silently, so that reports do not mix vendors.
22. As the owner, I want payers such as my employer to follow the same default-category, alias and override rules as vendors, so that income is classified the same way.
23. As the owner, I want to manage my category list (the 26 categories in the CSV mapping), so that classification uses my own labels.
24. As the owner, I want the Savings category excluded from spending, so that money I put aside does not inflate my expenses.

### Refunds, transfers and trash

25. As the owner, I want to record a refund linked to its original purchase, so that it takes the purchase's category automatically.
26. As the owner, I want to record a refund without a link when I cannot find the purchase, so that I still capture it with a required vendor and category.
27. As the owner, I want a refund to reduce spending in the period it was received, so that a January purchase and February refund show €100 in January and −€20 in February.
28. As the owner, I want a linked refund to stay validly classified if its original purchase is recategorized or trashed, so that refunds never lose their category.
29. As the owner, I want internal transfers and credit-card repayments excluded from spending, so that money is not counted twice.
30. As the owner, I want deleted entries kept in a trash that syncs across devices, so that I can undo a mistaken delete on either device.
31. As the owner, I want to restore an entry from trash within 30 days, so that recovery has a clear window.
32. As the owner, I want trashed entries excluded from all reports, so that deleted data never affects totals.

### Reports

33. As the owner, I want to ask "how much did I spend this month?", so that I get a single total with its date range.
34. As the owner, I want to ask for monthly spending by category, so that I can see where money goes.
35. As the owner, I want to ask for one category's spending over months, such as utilities or software, so that I can spot trends.
36. As the owner, I want "this month versus last month" to compare matching elapsed days, so that a partial month is compared fairly.
37. As the owner, I want unequal comparison periods labelled visibly, so that I am not misled by a 28-day February.
38. As the owner, I want comparisons to show both date ranges and the absolute change, so that I can read the result at a glance.
39. As the owner, I want the percentage change hidden when the base is zero, so that I never see a meaningless percentage.
40. As the owner, I want a query with no period to use the current calendar month and show its dates, so that the assumption is visible.
41. As the owner, I want explicit dates to override every default, so that I stay in control of the period.
42. As the owner, I want to search transactions by vendor, amount or amount condition, so that I can find an individual purchase.
43. As the owner, I want a short clarification when a name matches several vendors or categories, so that the answer is about what I meant.
44. As the owner, I want unsupported requests to explain the supported operations, so that I am never shown an invented answer.
45. As the owner, I want trends and comparisons as charts with a table toggle, so that I can see both the shape and the exact numbers.
46. As the owner, I want searches shown as a transaction list, so that I can open the entry I am looking for.
47. As the owner, I want preset reports available without the model, so that monthly totals and category breakdowns always work.
48. As the owner, I want a typical natural-language report in 5–7 seconds on my iPhone, so that asking stays faster than filtering by hand.
49. As the owner, I want all amounts computed exactly in cents, so that totals never show rounding drift.

### CSV import

50. As the owner, I want to import my existing CSV export, so that my history moves into Centtrail.
51. As the owner, I want a preview of column mappings, dates, amounts and categories before committing, so that a bad import never lands.
52. As the owner, I want to choose which column is the reporting date, so that imported history uses the date I care about.
53. As the owner, I want amounts signed negative imported as expenses and positive as income, so that kind is set without manual work.
54. As the owner, I want trailing spaces in payee and category names ignored, so that "REWE " and "REWE" are one vendor.
55. As the owner, I want rows with unknown categories or non-EUR currency held for correction rather than dropped, so that nothing disappears silently.
56. As the owner, I want definite repeat rows skipped when I import an overlapping file, so that re-importing is safe.
57. As the owner, I want uncertain matches shown for me to decide, so that two legitimate identical purchases are both kept.
58. As the owner, I want a new payee from the import to propose the row's category as its default, so that imported vendors are ready for capture.

### Sync and devices

59. As the owner, I want edits on one device to appear on the other through iCloud, so that both devices show the same history.
60. As the owner, I want to see when changes are waiting to sync, so that I know whether the other device is up to date.
61. As the owner, I want reports to run on local data, so that they work offline.
62. As the owner, I want conflicting edits resolved automatically with the latest edit winning, so that I never handle merge dialogs.

## Implementation Decisions

### Modules

**Ledger core (the deep module, and the only test seam).** A pure Swift package that owns every money and classification rule. Its public interface is a small set of commands and one query entry point:

- Recording and editing: record entry, edit entry, trash entry, restore entry, purge expired trash (given today's date).
- Classification: create or rename a category; create a counterparty; set a counterparty's default category; confirm an alias; set or clear an entry's category override.
- Import: preview import (rows plus mapping choice, returning per-row status: ready, needs correction, definite repeat, uncertain match); commit import (with the owner's decisions on uncertain matches).
- Reporting: run a report operation (a typed value, given today's date) and return a typed result.

The ledger takes today's date as an argument. It never reads the clock, which keeps period defaults and trash expiry deterministic. The ledger is backed by an app-owned SQLite schema. The UI, App Intent and interpreter talk only to this interface.

**Report operations (part of the Ledger core interface).** These are a closed set of four: total, breakdown, period comparison and transaction search. Their parameters are:

- measure: spending or income
- optional date range
- category and counterparty filters, by stable identity
- amount conditions
- grouping: by month, by category, or both

The ledger validates parameters and builds SQL from application-owned identifiers. User values are always bound parameters. The model never writes SQL (ADR 0001).

**Interpreter.** This module wraps Apple Foundation Models. It has two jobs:

- text to capture draft
- text to one of: a report operation, a clarification request listing candidate names, or an unsupported-request explanation

It resolves names against the ledger's categories, counterparties and confirmed aliases, and never invents an identity. When the model is unavailable, the interpreter reports that and every caller falls back to the manual form or the preset reports.

**Persistence and sync adapter.** This is SQLiteData over the app-owned schema, with CloudKit sync, chosen for evaluation first. It is adopted only after the two-device evaluation in the design doc passes. Custom sync with CKSyncEngine is the documented fallback. The adapter uses the library's default field-wise, latest-edit-wins merging, with no custom conflict workflow.

**App shell.** One SwiftUI app shared by iPhone and Mac. It has screens for capture, the transaction list and detail, reports, and management of categories, counterparties, imports and trash. An App Intent exposes capture to Shortcuts. The shell holds no business rules.

### Data rules

- Money is stored as integer EUR cents. Kind (income, expense, refund) decides how an amount counts in reports.
- The reporting date is a calendar date with no time zone. It must not shift when a device changes time zone.
- Every record has a globally unique stable identity, because sync requires it.
- A transaction records whether its category is inherited or overridden, even when both name the same category.
- A linked refund takes its category from the original purchase. An unlinked refund requires its own counterparty and category. Recategorizing or trashing the original must never leave a refund without a valid category.
- Spending is expenses minus refunds. It excludes internal transfers, credit-card repayments, the Savings category and trashed entries.
- Trash is a soft-delete flag with a trashed-on date. Entries older than 30 days are purged.

### Logical records

- **Category:** identity, display name, and a flag saying whether it counts as spending (false for Savings).
- **Counterparty:** identity, display name, default category. It acts as a vendor or a payer.
- **Counterparty alias:** identity, confirmed alternative name, owning counterparty.
- **Transaction:** identity, kind, cents, reporting date, counterparty, category provenance and optional override, optional original-purchase link, note, trash state.
- **Import provenance:** batch identity and source row fingerprint.

### CSV import (from the sample export)

| CSV column | Rule |
| --- | --- |
| `Date` | ISO timestamp with offset. Reporting date = the calendar date in the row's own offset; the time is dropped. The preview allows another date column. |
| `Amount` | Sign sets kind; the absolute value is stored in cents. |
| `Category` | Matched to the category list after trimming spaces. An unknown name holds the row for correction. |
| `Payee` | Matched to a counterparty or confirmed alias after trimming spaces. A new payee proposes the row's category as its default. |
| `Notes` | Imported as the entry note. |
| Currency and rate columns | Validation only. Any row that is not EUR→EUR at rate 1.0 is held. |
| `Source Account` | Used only for duplicate detection. |

`Folder`, `Target Account`, `Tags`, `Pending` and `Budget Book` are ignored in v1.

Duplicates: the export has no row ID.

- A definite repeat matches on full timestamp to the second, amount, payee and source account. It is skipped.
- A row that matches on date, amount and payee but differs in time is an uncertain match. The owner reviews it.

### Model choice

Apple's on-device Foundation Models is the first candidate for both interpreter jobs. It is adopted, replaced or fine-tuned only after the measured evaluation.

## Testing Decisions

**What makes a good test.** A test drives the Ledger core through its public commands and its report entry point, against a real in-memory SQLite database. It asserts only on returned results and observable state. It never asserts on internal tables, SQL text or private helpers, and it uses no mocks of the ledger's own parts. A refactor that keeps behavior must not break a test.

**What runs at the Ledger seam.** The seam covers all of these:

- exact cent arithmetic
- inherited versus overridden categories, including retroactive default changes
- alias resolution
- linked and unlinked refunds across months
- Savings and transfer exclusion
- trash, restore and 30-day purge with an injected date
- omitted periods
- matching elapsed days and unequal month lengths
- zero-base percentage
- empty periods
- vendor and amount search
- CSV preview and commit: date offsets, decimals, whitespace, unknown categories, non-EUR rows, definite repeats, uncertain matches and repeat imports

Fixtures are small and have hand-computed expected answers. The 29-row sample export is one fixture.

**Interpreter evaluation (not unit tests).** This is a fixture set of owner-style requests for each operation, including paraphrases, ambiguous names and unsupported requests. Each case is scored on the chosen operation and every argument, not on schema validity. It runs on device and records accuracy plus cold and warm latency. The latency budget is 5–7 seconds end to end on the iPhone, measured separately on the Mac.

**Manual device checklist.** For sync, Shortcuts and UI, run these on both devices signed in to the same iCloud account:

- create and edit
- offline capture, then sync
- pending-sync indicator
- trash and restore across devices
- model-unavailable fallback

**Prior art.** None. The repo has no code yet, so these tests set the pattern.

## Out of Scope

- Bank- or notification-triggered capture, and Apple Pay automation.
- Account balances, savings tracking beyond excluding the Savings category from spending, INR transactions and currency exchange.
- Category groups from the CSV `Folder` column (open question).
- Custom conflict-resolution workflows and special handling for delete/edit races.
- Model-written SQL and any report operation beyond the four listed.
- Users other than the owner, and sharing.

## Further Notes

- **Open: CSV format for refunds and transfers.** The sample has neither. Their CSV mapping, and how a transfer is recognized on import, waits for sample rows. Until then, import must hold any positive row in an expense category for review rather than guess.
- **Open: Folder column.** Whether `Folder` becomes a category group is undecided.
- **Build environment.** This workspace is Linux with no Swift or Xcode. All build, test and device work happens in an Apple development environment.
- **Evaluation first.** The persistence/sync evaluation and the interpreter evaluation come before the dependent features are built. SQLiteData and Foundation Models are candidates, not adopted dependencies.
- **Sources.** `docs/design.md`, `docs/product-scope.md`, `docs/csv-import-mapping.md`, `GLOSSARY.md` and ADRs 0001–0002.
