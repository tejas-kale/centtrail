# Expense tracker: design interview

## Confirmed: audience and platforms

- V1 is for one person: the owner, using an iPhone Air and an M-series MacBook Pro on iOS/macOS 26 or later.
- Data syncs through iCloud. Both devices support capture, edits, and reports offline using local data, then sync when available; show when changes are waiting to sync.
- Evaluate Point-Free SQLiteData for local SQL and CloudKit sync first. Verify the planned relationships and offline/conflict behavior before adopting it; custom sync is a fallback if needed.
- Conflicting edits use the most recent edit automatically, rather than asking the owner to resolve versions. The owner considers simultaneous edits and deletion/edit races unimportant and delegates those details: use the library's normal merge behavior without a bespoke conflict workflow.
- EUR only in v1; EUR/INR transfers, INR payments, and savings are deferred to v2.

## Confirmed: capture and classification

- Support both a short form with suggested fields and typed/dictated text parsed into fields, accessible through a convenient shortcut. Both end with an editable confirmation.
- User-triggered shortcuts are sufficient for v1. Bank-triggered capture is deferred until an integration is verified; it does not block v1.
- Capture amount, income/expense, payee, date, and a category from the owner's predefined categories. Category is mandatory for every saved entry.
- A category has many vendors; each vendor supplies one default category. Individual purchases may override that default. Changing the vendor default also recategorizes historical purchases that used the old default; purchase-specific overrides remain separate. See [ADR 0002](adr/0002-retroactive-vendor-categories.md).
- Explicitly confirmed aliases, such as “AMZN MKTP” and “Amazon,” resolve to one vendor. Do not silently merge different businesses.
- Income payers use the same classification rules: default category, confirmed aliases, and per-entry category overrides. For example, an employer may default to Salary.
- Short-form capture remains usable when the on-device model is unavailable. The owner will provide an expense snapshot later to establish the category list.

## Confirmed: financial semantics

- Record income and expenses without account balances. Exclude internal transfers and credit-card repayments from spending to avoid double counting.
- Refunds reduce spending in the original category in the month received: a €100 January grocery purchase and €20 February refund report €100 in January and −€20 in February.
- Link refunds to the original purchase when available; otherwise allow a refund with a required vendor and category.
- The owner chooses the reporting date. Keep it editable during entry and editing, and let CSV import map the chosen date column rather than mandate purchase date or bank posting date.
- V1 must import existing transaction history from CSV. Skip definite repeats and ask the owner to resolve uncertain duplicate matches; identical date/vendor/amount alone does not prove a duplicate.
- Deleted transactions remain in recoverable trash for 30 days, synced across devices.

## Confirmed: reporting

- Natural-language reporting covers totals, monthly/category breakdowns, changes between periods, and transaction search by vendor, amount, or individual purchase. Examples include total monthly spending and monthly spending on utilities, restaurants, software, and groceries.
- The on-device model selects operations and parameters; the app validates them and builds SQL. This replaces the initial model-written SQL proposal; see [ADR 0001](adr/0001-app-builds-reporting-sql.md).
- Evaluate Apple's built-in Foundation Models model first for capture parsing and report-operation selection; adoption depends on measured accuracy. Fine-tuning or another model remains a fallback, not a committed implementation.
- A typical natural-language report taking 5–7 seconds on the iPhone is acceptable. This is a target to evaluate, not measured performance.
- Trends and comparisons default to charts with a table toggle; transaction searches show a list. Preset charts remain usable when the on-device model is unavailable.
- Default comparison for “this month versus last month” uses matching elapsed days: on April 10, compare April 1–10 with March 1–10. When the previous month is shorter, use the available dates and visibly label unequal lengths: March 1–31 versus February 1–28 in a non-leap year. Explicit date ranges take precedence.
- If a query omits its period, use the current calendar month and visibly show the date range used.
- If a query ambiguously matches vendors or categories, ask a short clarification before executing it.

## Deferred inputs and validation

- The owner's snapshot will establish the category list; the CSV sample will establish actual column mappings and available duplicate identifiers.
- The [consolidated design](design.md) proposes entry points, operation structure, import validation, and evaluation criteria for final review.
- Apple's model and SQLiteData remain evaluation candidates. Their behavior and performance have not been tested on target devices.
- Rare conflict details are delegated implementation choices, not open product questions.
