# 06: Refunds and the definition of spending

**What to build:** The owner records a refund linked to its original purchase, which takes the purchase's category, or records an unlinked refund with a required vendor and category. Refunds reduce spending in the month they are received. Spending excludes the Savings category, internal transfers and credit-card repayments.

**Blocked by:** 03

**Status:** resolved

- [x] A €100 January purchase and a €20 February refund report €100 in January and −€20 in February
- [x] A linked refund takes the original purchase's category, including after the purchase is recategorized
- [x] Trashing or recategorizing the original purchase never leaves a linked refund without a valid category
- [x] An unlinked refund cannot be saved without a vendor and category
- [x] Savings entries, internal transfers and credit-card repayments are excluded from spending totals
- [x] All spending figures match hand-computed fixtures to the cent

## Comments

The capture form can link a refund to an expense. The entry detail shows that link from the refund and lists the refund on the purchase. Linked refunds still use the ledger's spending rules. The screens have not been checked on a device.
