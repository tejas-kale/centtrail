# 06: Refunds and the definition of spending

**What to build:** The owner records a refund linked to its original purchase, which takes the purchase's category, or records an unlinked refund with a required vendor and category. Refunds reduce spending in the month they are received. Spending excludes the Savings category, internal transfers and credit-card repayments.

**Blocked by:** 03

**Status:** ready-for-agent

- [ ] A €100 January purchase and a €20 February refund report €100 in January and −€20 in February
- [ ] A linked refund takes the original purchase's category, including after the purchase is recategorized
- [ ] Trashing or recategorizing the original purchase never leaves a linked refund without a valid category
- [ ] An unlinked refund cannot be saved without a vendor and category
- [ ] Savings entries, internal transfers and credit-card repayments are excluded from spending totals
- [ ] All spending figures match hand-computed fixtures to the cent
