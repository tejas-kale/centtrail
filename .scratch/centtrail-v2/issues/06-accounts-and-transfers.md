# 06: Accounts and transfers

**What to build:** Every transaction names an **Account**. The + form gets an account picker for expenses and income, and a Transfer mode with amount, from-account, to-account and date (no payee or category), for sending euros to the owner's Indian account. Settings gets an Accounts editor. Accounts sync.

**Blocked by:** 04, 05

**Status:** ready-for-agent

- [ ] Accounts are seeded with N26, Revolut, Cash and India, and can be added, renamed and removed in Settings
- [ ] Removing an account in use is refused with a message
- [ ] Expense and income entries require an account; transfers require two different accounts
- [ ] A €500 N26 → India transfer appears in the transaction list and never in spending
- [ ] Ledger tests cover account requirements, transfer validation and spending exclusion
