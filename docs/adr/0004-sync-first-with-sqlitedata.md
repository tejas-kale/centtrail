---
status: accepted
---

# Sync comes first, on SQLiteData with SwiftData as the fallback

iCloud sync between the iPhone and the Mac is built before the app redesign, so the new screens are built once on the synced store. SQLiteData with CloudKit is preferred over SwiftData because it keeps the Ledger's SQLite schema, its app-built report SQL (ADR 0001) and its tests; SwiftData would mean rewriting the Ledger's storage and computing grouped reports in Swift, under CloudKit's model limits. SQLiteData is a newer third-party library, so a half-day two-device spike must pass before adoption; if it fails, the Ledger moves to SwiftData behind the same API. Existing 1.0 data is not migrated: the owner re-imports the CSV.
