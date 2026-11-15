# 09: Redesigned capture card

**What to build:** Recording an entry is one elegant card on iPhone and Mac. Expense · Income · Transfer sit at the top; below them a large amount and the payee; category, account and date appear as prefilled chips tapped only to change. The account defaults to the payee's last-used account, else the most recently used account; the date defaults to today. Frequent-payee chips and payee suggestions (names and aliases) remain. One Save button saves and closes. Editing an entry uses the same card. Spec: `../spec.md`.

**Blocked by:** 03 (Payees remember their category)

**Status:** implemented; pending manual verification

- [x] The card layout matches the agreed shape: kind selector at the top, big amount, payee, chip row, Save.
- [x] Picking or typing a known payee fills category and the payee's last-used account.
- [x] A new payee gets the most recently used account.
- [x] Save reports a missing required field plainly and keeps the card open.
- [x] The in-app + and Mac Cmd-N open the card; editing an entry opens it filled.
- [x] Ledger exposes the payee's last-used account and most recently used account, tested through the Ledger public API.
- [ ] Verified by hand on iPhone and Mac, including Dynamic Type and dark mode.

Validation: Three Ledger public API tracer slices observed red then green for payee account memory (including income, aliases and trashed entries), recent-account fallback, and canonical suggestions matching aliases. Full package suite passed 84 Ledger-target and 6 Shell-target tests. Shared SwiftUI card compiles on macOS; iPhone/Mac visual, Dynamic Type, dark-mode and interaction checks remain pending. Account memory follows the existing frequent-payee ordering: newest reporting date, then recording order.
