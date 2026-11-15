# 06: Cross-currency transfers

**What to build:** Sending euros to the Indian account records both the amount sent (EUR) and the amount received (INR), so the effective rate is in the data. Transfers are instant, so both amounts are required for a cross-currency transfer; a same-currency transfer asks for one amount. Migrated transfers keep only their EUR sent amount without being flagged. Spec: `../spec.md`.

**Blocked by:** 05 (Account currency and in-place migration)

**Status:** ready-for-agent

- [ ] Transfer mode in capture shows Sent (source currency) and Received (destination currency) when the accounts' currencies differ, and one amount when they match.
- [ ] Recording a cross-currency transfer without both amounts is refused with a clear message; same-currency transfers store equal amounts.
- [ ] Migrated transfers keep their amount as sent with no received amount and are valid.
- [ ] Transfers stay excluded from spending in both currencies.
- [ ] Editing a transfer preserves both amounts.
- [ ] If ticket 08 has landed, a `transfers_with_rate` view exposes date, accounts, sent/received amounts with currencies and the effective rate when both exist.
- [ ] Tested through the Ledger public API.
