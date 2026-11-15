# 04: Home shows this month's total only

**What to build:** Home becomes calm: it shows this calendar month's spending total (1st of the month to today) and recent entries, with no comparison to last month. The month summary in Ledger is reshaped accordingly. Spec: `../spec.md`.

**Blocked by:** 01 (Remove the Ask tab and report interpreter)

**Status:** ready-for-agent

- [ ] The Ledger month summary returns the current month range, the spending total and recent entries; previous-period and percentage fields are gone.
- [ ] Spending excludes transfers, trashed entries and non-spending categories; refunds are income and do not reduce it (ADR 0003).
- [ ] Home on iPhone and Mac shows the total and recent entries only.
- [ ] Home summary tests are rewritten against the new summary; comparison tests are deleted.
