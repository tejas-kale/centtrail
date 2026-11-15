# Centtrail

A capture-first personal expense tracker for iPhone and Mac, with iCloud sync, EUR and INR accounts, voice capture and local laptop analysis.

Record through one card, an Action button or Control Center listening shortcut, or a Siri phrase that saves without opening the app. Home shows this month’s spending separately by currency, optional category-budget gauges and entries awaiting review. A local read-only MCP server supports analysis with the owner’s local model; on-device parsing is reserved for capture.

- [Design and validation plan](docs/design.md)
- [Product scope](docs/product-scope.md)
- [Capture-first EUR/INR implementation spec](.scratch/capture-first-two-currencies/spec.md)
- [CSV import mapping and category list](docs/csv-import-mapping.md)
- [Domain glossary](GLOSSARY.md)
- [Account currencies and transfer amounts](docs/adr/0005-account-currencies-and-transfer-amounts.md)
- [Local read-only analysis](docs/adr/0006-local-read-only-analysis.md)
- [Category history](docs/adr/0002-retroactive-vendor-categories.md), [refunds](docs/adr/0003-refund-is-income.md) and [sync](docs/adr/0004-sync-first-with-sqlitedata.md)
- [Platform feasibility and evidence](docs/platform-feasibility.md)

## Local MCP analysis

Build the Mac stdio server with Xcode's Swift toolchain:

```sh
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --product centtrail-mcp
env DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift build -c release --show-bin-path
```

Use the reported directory's `centtrail-mcp` executable in your local MCP client's configuration, for example:

```json
{
  "mcpServers": {
    "centtrail": {
      "command": "/absolute/path/to/centtrail-mcp",
      "args": []
    }
  }
}
```

The default file is `~/Library/Containers/com.tejaskale.centtrail/Data/Library/Application Support/Centtrail/ledger-v2.sqlite`, the sandboxed Mac app's synced ledger. Pass `"args": ["--ledger", "/absolute/path/to/ledger.sqlite"]` to select another file. Open the updated app once to migrate an older ledger before using its analysis views. The server never creates, migrates or syncs the ledger. It works while the app is closed; freshness depends on the Mac app's last completed iCloud sync.

Configure the client with your local model to keep analysis on your devices. `describe_schema` explains the live tables/views and money rules; `query` returns columns, typed JSON rows and a `truncated` flag. Start with `SELECT currency, SUM(amount_cents) AS spending_minor FROM spending GROUP BY currency`. Integer monetary columns are minor units; decimal amount columns are divided by 100. Blobs are base64 strings. Never add EUR and INR together.

Queries are enforced read-only by SQLite open flags, query-only mode and a compile-time authorizer. One statement is allowed, capped at 100 rows by default (up to 500), 1 MiB of result values, 100 columns and about two seconds of SQLite execution. Row/response caps set `truncated`; oversized individual values or excessive execution fail clearly. Writes, schema changes, changing pragmas, attachment and multiple statements are refused. The MCP transport uses newline-delimited JSON-RPC on stdio; diagnostics use stderr, following the [MCP stdio specification](https://modelcontextprotocol.io/specification/2025-06-18/basic/transports).

SQLite WAL supports concurrent reads and app writes; [read-only WAL access](https://www.sqlite.org/wal.html#read_only_databases) requires usable `-wal`/`-shm` sidecars. Do not copy only the main file or mark a live ledger immutable. macOS may ask the MCP client for permission to access Centtrail's container. The prompt's exact wording and grant behaviour, and a real local-client session alongside the signed app, still require manual verification on the owner's Mac; they have not been observed by the automated tests. Keep the selected ledger's sidecars together and grant access to the client when macOS requests it.
