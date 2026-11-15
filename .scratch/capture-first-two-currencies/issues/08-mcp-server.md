# 08: Read-only MCP server for laptop analysis

**What to build:** The owner's local model (9B–27B, through any MCP-capable client) can query the ledger on the Mac without any online model. A `centtrail-mcp` executable, launched by the MCP client over stdio, opens the Mac app's synced ledger read-only and offers `describe_schema` and `query`. Centtrail need not be running. Spec: `../spec.md`.

**Blocked by:** 01 (Remove the Ask tab and report interpreter)

**Status:** ready-for-agent

- [ ] Ledger can open a ledger file read-only; writes are impossible at the SQLite level (read-only open and query-only mode), not just by inspecting SQL text.
- [ ] Ledger's query accepts exactly one read-only statement and returns columns, rows and a truncated flag when the row cap is hit; writes, schema changes and multiple statements are refused with clear errors.
- [ ] Ledger describes the schema in plain words: tables, views, columns, minor units vs decimal amounts, spending rules.
- [ ] A `spending` view applies the spending rules (no transfers, no trashed entries, spending categories only, refunds not subtracted).
- [ ] `centtrail-mcp` maps the two tools onto Ledger, finds the sandboxed Mac app's ledger in its container by default and accepts a path override.
- [ ] Verified by hand: configured in a local MCP client, it answers a query while the Mac app is open and writing (WAL mode), and the macOS container-access prompt behaviour is noted in the README.
- [ ] Ledger-level behaviour is tested against a temporary on-disk ledger.
