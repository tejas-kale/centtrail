# 12: Review inbox

**What to build:** Entries that could not be fully classified are saved anyway and collected in a review inbox. Home shows "N to review"; tapping opens each entry in the capture card to fix it in one step. Fixing the category of an entry whose payee has no default also sets that default, so the payee never needs review again. Spec: `../spec.md`.

**Blocked by:** 03 (Payees remember their category), 04 (Home shows this month's total only)

**Status:** complete

- [x] A reserved Uncategorised category exists; it never becomes a payee default and is excluded from payee suggestions and budgets.
- [x] Ledger can record an entry for review (Uncategorised, needs-review flag) and lists the review inbox newest first.
- [x] Correcting a review entry's category clears the flag and sets the payee's default if it had none.
- [x] Review entries count in spending totals in their currency.
- [x] The month summary includes the review count; Home shows "N to review" only when N > 0 and opens the inbox.
- [x] Tested through the Ledger public API.
