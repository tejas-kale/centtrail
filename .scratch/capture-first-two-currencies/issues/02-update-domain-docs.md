# 02: Update domain docs and ADRs

**What to build:** The project's written design matches the new spec, so later tickets and agents work from the right vocabulary. Product scope and design drop "EUR only" and natural-language reporting; the glossary gains the new terms; new decisions are recorded. Spec: `../spec.md`.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [ ] Product scope and design describe capture-first Centtrail: redesigned card, voice for amount/payee/date, Action button/Control/Siri entry points, review inbox, account currencies, two-amount transfers, Home month totals per currency, category budgets, local read-only MCP server.
- [ ] Glossary defines **Currency** (of an account), **Sent amount**, **Received amount**, **Budget** and **Review inbox**, and updates **Internal transfer** and **Spending** for two currencies.
- [ ] New ADR: each account has one currency; entries use it; transfers store sent and received amounts; no conversion anywhere.
- [ ] New ADR: on-device reporting is removed in favour of a local read-only MCP server; ADR 0001 is marked superseded by it.
- [ ] README links stay valid.
