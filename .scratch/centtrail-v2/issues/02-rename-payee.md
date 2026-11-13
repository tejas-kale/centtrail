# 02: Rename Counterparty to Payee

**What to build:** One mechanical rename so code, tests and screens use the glossary's **Payee** for the other side of any expense or income. Vendor, Payer and Counterparty disappear from the Ledger API, Interpreter and app. No behaviour changes.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] The Ledger and Interpreter public APIs say Payee wherever they said counterparty, vendor or payer
- [ ] Payee aliases keep working under the new name
- [ ] The app shows "Payee" in every label
- [ ] All existing tests pass with only naming changes
