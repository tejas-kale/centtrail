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
3. **Explicit `ON DELETE` actions**: All synced foreign keys must specify `ON DELETE CASCADE`, `ON DELETE SET NULL`, or `ON DELETE SET DEFAULT` (Centtrail uses `SET NULL` for account references and refuses removal while in use through the Ledger). SQLiteData 1.13.0 rejects `RESTRICT`/`NO ACTION` for single-foreign-key parent relationships; its validator permits them on tables with several foreign keys. The app keeps the stricter schema rule rather than relying on that exception.
4. **Defaults & reserved names**: Provide safe `DEFAULT` values for `NOT NULL` columns where needed and avoid CloudKit-reserved field names.
5. **Two-device verification**: Live CloudKit sync on iPhone Air and Mac is verified against the manual checklist in `docs/platform-feasibility.md` once `SyncEngine` is wired into the signed app targets.

## Bootstrap customization (v2 review)

Seeded category/account records have stable IDs and immutable default names. User names and removals live in a separate synced `reference_customization` record; effective SQL views combine them for Ledger reads and reports. A local initialization flag or physical deletion alone cannot prevent a late-installed device's newer seed upload from resetting a rename or restoring a removal. The separate overlay is never seeded, so bootstrap writes cannot overwrite user customization; removal retains a small synced tombstone. This fixes repeated local bootstrap and removes that source of cross-device conflict, while live two-device convergence still requires the manual checklist.
