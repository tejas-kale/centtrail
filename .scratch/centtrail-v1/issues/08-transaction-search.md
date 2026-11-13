# 08: Transaction search

**What to build:** The owner searches transactions by vendor, amount or amount condition (e.g. over €50) and gets a list of matching entries they can open. This is the transaction search report operation of the Ledger core.

**Blocked by:** 03

**Status:** ledger implemented

- [x] Search filters by counterparty (including via confirmed alias), category, date range and amount conditions
- [ ] Results show as a transaction list; tapping a result opens the entry
- [x] Trashed entries never appear
- [ ] User-supplied values are bound parameters; filters and grouping come only from application-owned definitions

## Comments

The reports screen filters by vendor, an "over euros" amount, category, and an inclusive from/to date range. Ledger tests cover category alone, the date range including both endpoints, the two together, and vendor plus "over euros" composed with them. A confirmed alias and trashed entries stay covered by the existing search test. Equal, less-than, at-least and at-most amount conditions are implemented on the ledger and still have no dedicated test. Opening a result is a navigation link and has not been checked on a device. Ledger queries bind counterparty names, category ids, dates and amounts, and the filter and grouping clauses are fixed in the app. Tests do not read SQL, so that item stays open.
