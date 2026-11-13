# 08: Transaction search

**What to build:** The owner searches transactions by vendor, amount or amount condition (e.g. over €50) and gets a list of matching entries they can open. This is the transaction search report operation of the Ledger core.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] Search filters by counterparty (including via confirmed alias), category, date range and amount conditions
- [ ] Results show as a transaction list; tapping a result opens the entry
- [ ] Trashed entries never appear
- [ ] User-supplied values are bound parameters; filters and grouping come only from application-owned definitions
