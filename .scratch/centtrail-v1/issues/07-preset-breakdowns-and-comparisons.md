# 07: Preset breakdowns and comparisons

**What to build:** Without the model, the owner opens preset reports: monthly spending, spending by category, one category over months, and this month versus last month. Trends and comparisons show as charts with a table toggle. These are the breakdown and period-comparison report operations of the Ledger core.

**Blocked by:** 03

**Status:** ledger implemented

- [x] Breakdown groups spending by month, by category, or both, for a given date range
- [x] An omitted period uses the current calendar month, and the actual dates are shown
- [x] This-month-versus-last-month compares matching elapsed days (April 1–10 vs March 1–10)
- [x] When the previous month is shorter, the comparison uses its available days and labels the unequal lengths
- [x] A comparison shows both date ranges and the absolute change; the percentage is hidden when the base is zero
- [x] Empty periods return zero, not an error
- [ ] Chart and table views render the same result data

## Comments

The reports screen draws a chart and a table from the same breakdown rows. Neither view has been checked on a device.
