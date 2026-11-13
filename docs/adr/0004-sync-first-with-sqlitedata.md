---
status: accepted
---

# Sync comes first, on SQLiteData with CloudKit

iCloud sync between the iPhone and the Mac is built before the app redesign, so the new screens are built once on the synced store.

## Decision

Adopt `pointfreeco/sqlite-data` (`SyncEngine` + CloudKit) for Centtrail's synced `Ledger` storage in ticket 04, rather than falling back to SwiftData. Existing 1.0 data is not migrated: the owner re-imports the CSV.

## Why

- **Preserves SQLite & reporting SQL**: Keeps the `Ledger`'s SQLite schema, app-built report SQL (ADR 0001), and existing test suite without rewriting storage or re-implementing grouped reports in Swift.
- **Toolchain & OS fit**: `sqlite-data` supports Swift 6 and iOS 17+ / macOS 14+, matching Centtrail's `.macOS("26.0")` and `.iOS("26.0")` targets.
- **Sync semantics**: `SyncEngine` provides field-wise last-edit-wins conflict resolution and handles out-of-order foreign key delivery via topological sorting and retry caching.

## Schema rules for ticket 04

1. **Globally unique primary keys**: Every synced table must use a globally unique primary key (`UUID` / `UUIDv7`, `TEXT PRIMARY KEY NOT NULL`).
2. **No non-PK `UNIQUE` constraints**: Remove `UNIQUE` constraints on non-primary-key columns (such as `category.name`, `counterparty.name`, and `counterparty_alias.name`) from synced tables and enforce/deduplicate them in application logic.
3. **Explicit `ON DELETE` actions**: All synced foreign keys must specify `ON DELETE CASCADE`, `ON DELETE SET NULL`, or `ON DELETE SET DEFAULT` (`RESTRICT` and `NO ACTION` are rejected by `SyncEngine`).
4. **Defaults & reserved names**: Provide safe `DEFAULT` values for `NOT NULL` columns where needed and avoid CloudKit-reserved field names.
5. **Two-device verification**: Live CloudKit sync on iPhone Air and Mac is verified against the manual checklist in `docs/platform-feasibility.md` once `SyncEngine` is wired into the signed app targets.
