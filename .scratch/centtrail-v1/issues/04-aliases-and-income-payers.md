# 04: Aliases and income payers

**What to build:** The owner confirms that one name (e.g. "AMZN MKTP") is an alias of an existing counterparty ("Amazon"), and both names resolve to it in capture and reports. Income entries use payers that follow the same default category, alias and override rules as vendors.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] A confirmed alias resolves to its counterparty in capture
- [ ] Names are never merged without the owner's explicit confirmation
- [ ] An income entry with a payer pre-fills the payer's default category (e.g. employer → Salary)
- [ ] Payer overrides and default changes behave exactly as for vendors
- [ ] Income totals are reported separately from spending
