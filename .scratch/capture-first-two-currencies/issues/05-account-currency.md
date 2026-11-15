# 05: Account currency and in-place migration

**What to build:** Every account has a currency, EUR or INR. The existing ledger migrates in place: all accounts become EUR, and the owner can mark the India account INR once in Settings. Expenses and income are stored in their account's currency and shown with € or ₹ everywhere. Home shows separate EUR and INR spending totals, never mixed or converted, hiding a currency with no spending this month. Spec: `../spec.md`.

**Blocked by:** 04 (Home shows this month's total only)

**Status:** ready-for-agent

- [ ] Accounts carry a currency; new accounts choose one in Settings; the field syncs.
- [ ] Migration sets every existing account to EUR and keeps all amounts unchanged.
- [ ] Changing an account's currency is refused once it holds entries, except a one-time allowance used to mark the India account INR after migration.
- [ ] The capture form and entry lists show the account's currency symbol.
- [ ] The month summary returns spending totals keyed by currency; Home shows one total per currency with spending.
- [ ] CSV import assigns imported rows the target account's currency.
- [ ] If ticket 08 has landed, the `spending` view and schema description include the currency code.
- [ ] Tested through the Ledger public API, including a pre-migration ledger.
