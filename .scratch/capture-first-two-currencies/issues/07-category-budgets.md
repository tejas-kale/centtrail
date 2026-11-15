# 07: Category budgets with Home gauges

**What to build:** The owner can give any spending category an optional fixed monthly budget in one currency in Settings. Home shows a small gauge for each budgeted category: this month's spending in that currency against the budget, amber at 80% and red at 100%. Budgets reset each calendar month with no rollover and sync across devices. Spec: `../spec.md`.

**Blocked by:** 05 (Account currency and in-place migration)

**Status:** complete

- [x] Settings lets the owner set, change and remove a budget (amount and currency) per category; at most one per category.
- [x] Budgets are synced records.
- [x] The month summary returns per-budget gauges: category, currency, budget, spent this month in that currency, fraction.
- [x] Spending in the other currency does not count toward a budget.
- [x] Home shows gauges only for budgeted categories, with amber at ≥80% and red at ≥100%.
- [x] If ticket 08 has landed, a `budgets` view exposes each budget with current-month spending.
- [x] Tested through the Ledger public API.
