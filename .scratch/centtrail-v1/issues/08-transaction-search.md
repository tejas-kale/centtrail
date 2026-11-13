# 08: Transaction search

**What to build:** The owner searches transactions by vendor, amount or amount condition (e.g. over €50) and gets a list of matching entries they can open. This is the transaction search report operation of the Ledger core.

**Blocked by:** 03

**Status:** ledger implemented

- [ ] Search filters by counterparty (including via confirmed alias), category, date range and amount conditions
- [ ] Results show as a transaction list; tapping a result opens the entry
- [x] Trashed entries never appear
- [ ] User-supplied values are bound parameters; filters and grouping come only from application-owned definitions

## Comments

A confirmed alias and a greater-than amount are tested, and trashed entries are excluded. Category, date range and the other amount conditions are implemented on the ledger and have no test yet. The reports screen only offers a vendor field and an "over euros" field.
Opening a result is a navigation link to the entry. It has not been checked on a device.
Ledger queries bind counterparty names, category ids and amounts, and the filter and grouping clauses are fixed in the app. Tests do not read SQL, so that item stays open.
