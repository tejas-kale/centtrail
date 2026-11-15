# 09: Redesigned capture card

**What to build:** Recording an entry is one elegant card on iPhone and Mac. Expense · Income · Transfer sit at the top; below them a large amount and the payee; category, account and date appear as prefilled chips tapped only to change. The account defaults to the payee's last-used account, else the most recently used account; the date defaults to today. Frequent-payee chips and payee suggestions (names and aliases) remain. One Save button saves and closes. Editing an entry uses the same card. Spec: `../spec.md`.

**Blocked by:** 03 (Payees remember their category)

**Status:** ready-for-agent

- [ ] The card layout matches the agreed shape: kind selector at the top, big amount, payee, chip row, Save.
- [ ] Picking or typing a known payee fills category and the payee's last-used account.
- [ ] A new payee gets the most recently used account.
- [ ] Save reports a missing required field plainly and keeps the card open.
- [ ] The in-app + and Mac Cmd-N open the card; editing an entry opens it filled.
- [ ] Ledger exposes the payee's last-used account and most recently used account, tested through the Ledger public API.
- [ ] Verified by hand on iPhone and Mac, including Dynamic Type and dark mode.
