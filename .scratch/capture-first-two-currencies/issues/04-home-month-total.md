# 04: Home shows this month's total only

**What to build:** Home becomes calm: it shows this calendar month's spending total (1st of the month to today) and recent entries, with no comparison to last month. The month summary in Ledger is reshaped accordingly. Spec: `../spec.md`.

**Blocked by:** 01 (Remove the Ask tab and report interpreter)

**Status:** complete

- [x] The Ledger month summary returns the current month range, the spending total and recent entries; previous-period and percentage fields are gone.
- [x] Spending excludes transfers, trashed entries and non-spending categories; refunds are income and do not reduce it (ADR 0003).
- [x] Home on iPhone and Mac shows the total and recent entries only.
- [x] Home summary tests are rewritten against the new summary; comparison tests are deleted.

Validation: Ledger month-summary tests were written red (missing `monthSummary`) then passed green. Full macOS package test suite passed; shared Home source shows only the month total and recent entries on both platforms. Integration iOS compile is recorded centrally. Tests cover month boundaries, all spending exclusions, future expenses, trashed entries, refunds as income, and recent history.
