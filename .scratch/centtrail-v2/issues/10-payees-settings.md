# 10: Payees: defaults and merge

**What to build:** Settings › Payees lists every payee with its default category. Changing a default recategorises past entries that used it while keeping explicit overrides (ADR 0002). The owner can merge two payees; the merged name stays as a payee alias so future entries and imports resolve to the surviving payee.

**Blocked by:** 05

**Status:** ready-for-agent

- [ ] Changing Amazon's default from Supermarket to Shopping moves inherited past entries but not overridden ones
- [ ] Merging "AMZN MKTP" into "Amazon" moves its transactions and keeps the name as an alias
- [ ] A later entry or import typed "AMZN MKTP" resolves to Amazon
- [ ] The old alias screen is gone
- [ ] Ledger tests cover merge and alias resolution
