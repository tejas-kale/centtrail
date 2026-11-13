# Expense tracker v1 design

Status: consolidated for shared-understanding review. No application has been implemented, and neither the model nor sync library has been validated. Product decisions are recorded in [product scope](product-scope.md); terminology is in the [glossary](../GLOSSARY.md).

## Product contract

Build a personal EUR income/expense tracker for an iPhone Air and M-series MacBook Pro on iOS/macOS 26+. Both devices work from local data offline and sync through the owner's iCloud account.

1. Capture through a short form or typed/dictated text, with a user-triggered shortcut and an editable confirmation. Every saved entry has an amount, kind, counterparty, reporting date, and category.
2. Infer categories from confirmed vendor/payer defaults and aliases. Allow entry-specific overrides. Changing a default also changes historical entries that inherited it.
3. Answer natural-language requests for totals, monthly/category breakdowns, period comparisons, and individual transaction searches. The model selects operations; application code validates parameters, builds SQL, and calculates results.
4. Import existing CSV history with category validation and duplicate review. Keep deleted entries in synced, recoverable trash for 30 days.
5. Keep manual capture and preset reports available without AI. Bank-triggered capture, account balances, INR transactions, foreign exchange, and savings tracking are outside v1.

## Proposed implementation shape

These are concrete implementation recommendations for this review, not claims of tested capabilities.

| Part | Responsibility |
| --- | --- |
| Native UI | Shared SwiftUI app structure, adapted for phone and Mac. Capture, transaction list/detail, reports, and management of categories, counterparties, imports, and trash. |
| Capture actions | An App Intent exposed through Shortcuts, usable from iPhone and a Mac keyboard shortcut. Open an editable draft; saving still requires confirmation. System dictation supplies text to the same parsing flow. |
| Shared domain logic | Exact money arithmetic, category resolution, refunds, reporting periods, and import validation. Preset reports and AI requests use the same calculations. |
| On-device interpreter | Evaluate Apple Foundation Models for capture-field extraction and typed report requests. Resolve supplied names against known categories/counterparties; clarify ambiguous matches. |
| Persistence and sync | Evaluate SQLiteData over an app-owned SQLite schema with CloudKit synchronization. Adopt only after the schema and ordinary offline/sync flow pass the evaluation below. |

Reporting requests contain an allowed operation and typed parameters, never arbitrary SQL from the model. Initial operations are total, breakdown, period comparison, and transaction search. Parameters cover the requested income/expense measure, dates, category/counterparty filters, amount conditions, and supported grouping. SQL identifiers and grouping choices come from application-owned definitions; user values are bound parameters.

Unsupported requests receive a plain explanation of the supported operations rather than an invented query. A query with an ambiguous vendor/category asks a short clarification before execution. A model failure leaves the manual report controls usable.

## Proposed logical records

This is a logical model for evaluating the library, not finalized database DDL.

| Record | Purpose |
| --- | --- |
| Category | Stable identity and display name from the owner's list. |
| Counterparty | Stable identity, display name, and default category. Acts as a vendor for expenses or a payer for income. |
| Counterparty alias | Explicitly confirmed alternative name pointing to one counterparty. |
| Transaction | Identity, income/expense/refund kind, exact EUR amount, selected reporting date, counterparty, category provenance/override, optional original-purchase link for refunds, and edit/trash state. |
| Import provenance | Import batch and source identifiers needed to identify repeat imports without collapsing legitimate identical purchases. |

Store EUR amounts in integer cents and determine their reporting effect from transaction kind. Preserve the selected reporting date as a calendar date rather than shifting it when devices change time zones. Every saved/imported transaction must resolve to a category; an unresolved AI suggestion is not a valid saved entry.

Distinguish inherited classification from an explicit override even when both currently name the same category. A vendor-default change must not silently remove an explicit override. Changing an individual transaction's category must not silently change the vendor's default.

Linked refunds use their original purchase's category; unlinked refunds require a vendor and category. The persistence evaluation must check that deleting or recategorizing the original purchase does not leave a refund without valid classification. Refunds reduce spending in their own selected reporting period, not the original purchase's period.

## Reporting behavior

1. Spending means expenses less refunds; transfers and credit-card repayments are excluded. Use exact arithmetic and exclude trashed entries.
2. An omitted period means the current calendar month, with the actual dates displayed. Explicit dates always take precedence.
3. A month-to-month comparison uses matching elapsed days where possible. If the previous month is shorter, compare its available days and label unequal lengths. Show both dates and the absolute change; percentage change is unavailable when the comparison base is zero.
4. Trends and comparisons default to charts with a table toggle; searches show a transaction list. A single total appears as a number with its filters/date range. Charts and tables use the same result data.
5. A typical natural-language query taking 5–7 seconds on the iPhone is acceptable. Measure interpretation plus database execution and presentation, not model generation alone.

## Import and sync defaults

CSV import previews column mappings, reporting-date selection, amounts, and categories before committing. Use an existing confirmed vendor/payer default where applicable; otherwise the missing category must be resolved. Invalid rows remain visible for correction rather than being silently dropped. The actual parser mappings depend on the forthcoming CSV sample.

Skip repeats established by reliable source identities or a previously imported file/row identity. Date, vendor, and amount alone do not establish identity: two identical purchases may both be legitimate. Ask the owner about uncertain matches across overlapping imports.

Use the sync library's normal conflict behavior, expected to merge independent fields and select the latest edit for same-field conflicts; verify the chosen version's behavior. The owner delegates rare edit races and does not want a custom conflict-resolution workflow. Use ordinary soft-delete and explicit-restore state for trash; do not make concurrent deletion scenarios a separate product feature.

Local capture and edits should not wait for iCloud. Reports use local data and indicate pending synchronization; cross-device convergence must be tested rather than assumed.

## Evaluation before committing to the stack

1. **Persistence:** On the two target devices using the same iCloud account, exercise create/edit, offline capture followed by sync, alias/category relationships, historical recategorization with overrides, refunds, and trash/restore. Check SQLiteData's schema constraints and default merge behavior against these records. If essential behavior is unsupported, document the gap before choosing custom synchronization.
2. **Deterministic reports:** Use small fixtures with known expected answers. Include a January purchase with a February refund, inherited versus overridden categories, omitted dates, unequal month lengths, empty periods, and vendor/amount searches. Monetary results must match exact expected values.
3. **Model interpretation:** Start with synthetic counterparties/categories and representative requests from each supported operation, including paraphrases and ambiguous/unsupported requests. Check the selected operation and all arguments, not just whether the output matches a schema. Required examples must produce the correct interpretation or the appropriate clarification; an incorrect answer that happens to be valid SQL is a failure.
4. **Latency and fallback:** Record cold and warm end-to-end timings on the iPhone against the 5–7-second expectation, and record Mac timings separately. Confirm that model-unavailable states preserve short-form capture and preset reports. Report measured results before deciding to adopt, change, or fine-tune a model.
5. **Capture/import:** Verify confirmation and required-category enforcement in both entry modes. With the eventual CSV sample, verify dates/decimals, repeated imports, uncertain duplicates, and valid income/expense/refund mapping. Do not claim compatibility with an unseen export format.

This workspace is Linux without Swift or Xcode. Apple framework, iCloud, shortcut, and device-performance tests must run in an Apple development environment. No such tests have been run in this session; [platform notes](platform-feasibility.md) separate sourced capabilities from unverified candidates.

## Deferred inputs

The owner will provide the expense snapshot/category list and CSV sample later. Synthetic data is sufficient to prepare the first feasibility evaluation; actual import mapping and category-specific model examples remain deferred until those inputs arrive. Final shared-understanding confirmation is pending before implementation or evaluation work begins.

## Recorded architectural decisions

- [ADR 0001: model-selected operations, app-built SQL](adr/0001-app-builds-reporting-sql.md).
- [ADR 0002: retroactive vendor category changes](adr/0002-retroactive-vendor-categories.md).

SQLiteData and Foundation Models are selected for evaluation, not yet adopted dependencies. Record adoption decisions after evidence from the evaluation.
