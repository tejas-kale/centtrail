---
status: accepted
---

# Move analysis to a local read-only MCP server

The owner prefers analysing finances with a local 9B–27B model on the laptop, so Centtrail removes the Ask tab and on-device report interpretation in favour of `centtrail-mcp`, launched over stdio by any MCP-capable client. This supersedes [ADR 0001](0001-app-builds-reporting-sql.md): instead of limiting analysis to model-selected report operations, Ledger exposes schema descriptions and arbitrary single-statement read-only queries, with SQLite read-only open/query-only enforcement and capped results. On-device parsing remains for capture only, and no financial data needs to leave the owner's devices for analysis.

The server opens the Mac app's synced ledger even when the app is closed; freshness therefore depends on the app's last sync. Spending, transfer-rate and budget views encode financial rules and expose currency codes and amount units so the model can query faithfully. There are no write tools; the trade-off for more flexible analysis is that the local model must understand the described schema and interpret query results.
